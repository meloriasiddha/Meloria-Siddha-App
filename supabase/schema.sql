-- =====================================================================
-- Meloria Siddha App — Database schema (Phase 1: Staff app core)
-- Run this whole file once in Supabase → SQL Editor → New query → Run.
-- Safe to re-run: it uses "if not exists" where possible.
-- =====================================================================

-- ---------- Branches -------------------------------------------------
create table if not exists branches (
  id           serial primary key,
  code         text not null unique,          -- '1' for the current clinic
  name         text not null,
  address      text,
  phone        text,
  next_patient_number integer not null default 1
);

insert into branches (code, name, address, phone)
values ('1', 'Meloria Siddha and Varma Clinic',
        '18, Thendral Nagar, St Thomas Road, Maharaja Nagar, Tirunelveli - 627011',
        '+91 93446 98304')
on conflict (code) do nothing;

-- ---------- Staff (doctor / staff logins) ----------------------------
-- Each staff login is a Supabase Auth user + one row here.
create table if not exists staff_profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text not null,
  role       text not null check (role in ('doctor','staff')),
  branch_id  integer references branches(id) default 1,
  created_at timestamptz default now()
);

-- Helper used by every security rule below
create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff_profiles where id = auth.uid());
$$;

create or replace function is_doctor() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff_profiles where id = auth.uid() and role = 'doctor');
$$;

-- ---------- Patients -------------------------------------------------
create table if not exists patients (
  id            uuid primary key default gen_random_uuid(),
  patient_code  text unique,                  -- e.g. MEL1-0001 (auto)
  branch_id     integer not null references branches(id) default 1,
  name          text not null,
  age           integer,
  gender        text,
  phone         text,
  address       text,
  referred_by_type   text check (referred_by_type in ('patient','doctor','other')),
  referred_by_patient uuid references patients(id),
  referred_by_name   text,                    -- doctor name / other source
  sugar_fasting_max  numeric,                 -- per-patient limits (mg/dL)
  sugar_pp_max       numeric,
  sugar_low_min      numeric,
  created_at    timestamptz default now()
);
create index if not exists patients_name_idx  on patients (lower(name));
create index if not exists patients_phone_idx on patients (phone);

-- Auto patient ID: MEL + branch code + '-' + 4-digit number
create or replace function set_patient_code() returns trigger
language plpgsql security definer set search_path = public as $$
declare n integer; c text;
begin
  if new.patient_code is null then
    update branches set next_patient_number = next_patient_number + 1
      where id = new.branch_id
      returning next_patient_number - 1, code into n, c;
    new.patient_code := 'MEL' || c || '-' || lpad(n::text, 4, '0');
  end if;
  return new;
end $$;
drop trigger if exists trg_patient_code on patients;
create trigger trg_patient_code before insert on patients
  for each row execute function set_patient_code();

-- ---------- Allergies & current medications --------------------------
create table if not exists patient_allergies (
  id          uuid primary key default gen_random_uuid(),
  patient_id  uuid not null references patients(id) on delete cascade,
  kind        text check (kind in ('drug','food','other')) default 'drug',
  name        text not null,
  reaction    text,
  created_at  timestamptz default now()
);

create table if not exists current_medications (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references patients(id) on delete cascade,
  system        text check (system in ('siddha','allopathy','other')) default 'allopathy',
  name          text not null,
  dose          text,          -- e.g. 500 mg, 1 tsp
  frequency     text,          -- e.g. 1-0-1
  timing        text,          -- before food / after food
  since         text,          -- e.g. 2 years
  prescribed_by text,
  active        boolean default true,
  created_at    timestamptz default now()
);

-- ---------- Visits (one per clinic visit) ----------------------------
create table if not exists visits (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references patients(id) on delete cascade,
  branch_id       integer not null references branches(id) default 1,
  visit_date      date not null default current_date,
  visit_type      text default 'review' check (visit_type in ('first','review','therapy','program')),
  mode            text default 'offline' check (mode in ('offline','online')),
  status          text not null default 'waiting' check (status in ('waiting','with_doctor','done','cancelled')),
  -- vitals
  bp_systolic     integer,
  bp_diastolic    integer,
  pulse           integer,
  temperature     numeric,    -- °F
  spo2            integer,
  weight          numeric,    -- kg
  height          numeric,    -- cm
  random_sugar    numeric,    -- mg/dL
  main_complaint  text,
  created_by      uuid references auth.users(id) default auth.uid(),
  created_at      timestamptz default now()
);
create index if not exists visits_date_idx on visits (visit_date, status);

-- ---------- Consultation (doctor's case sheet for a visit) -----------
create table if not exists consultations (
  id               uuid primary key default gen_random_uuid(),
  visit_id         uuid not null unique references visits(id) on delete cascade,
  complaints       jsonb default '[]'::jsonb,   -- [{"complaint":"Knee pain","duration":"3 months"}]
  history_present  text,
  family_history   jsonb default '{}'::jsonb,   -- {"diabetes":true,"bp":false,"heart":false,"notes":""}
  personal_history jsonb default '{}'::jsonb,   -- {"alcohol":"never","alcohol_notes":"","smoking":"past",...}
  diet_plan        text,
  doctor_notes     text,
  next_visit       date,
  updated_at       timestamptz default now()
);

create table if not exists diet_templates (
  id     uuid primary key default gen_random_uuid(),
  name   text not null,
  body   text not null
);

-- ---------- Medicine stock -------------------------------------------
create table if not exists medicines (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  form        text,      -- choornam, lehyam, thailam, tablet, kashayam, capsule, syrup...
  unit        text,      -- g, ml, tablet, bottle
  price       numeric default 0,   -- selling price per unit (MRP)
  low_stock_alert integer default 10,
  active      boolean default true,
  created_at  timestamptz default now()
);

create table if not exists medicine_batches (
  id            uuid primary key default gen_random_uuid(),
  medicine_id   uuid not null references medicines(id) on delete cascade,
  batch_no      text not null,
  mfg_date      date,
  expiry_date   date,
  quantity      numeric not null default 0,
  purchase_price numeric,
  created_at    timestamptz default now()
);

-- ---------- Prescriptions (medicines given in a visit) ---------------
create table if not exists prescriptions (
  id           uuid primary key default gen_random_uuid(),
  visit_id     uuid not null references visits(id) on delete cascade,
  medicine_id  uuid not null references medicines(id),
  batch_id     uuid references medicine_batches(id),
  dose         text,      -- e.g. 1 tsp, 2 tablets
  frequency    text,      -- e.g. 1-0-1
  timing       text,      -- before food / after food
  days         integer,
  quantity     numeric default 0,   -- units dispensed (reduces stock)
  instructions text,
  created_at   timestamptz default now()
);

-- Reduce / restore stock automatically
create or replace function adjust_stock() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.batch_id is not null then
    update medicine_batches set quantity = quantity - coalesce(new.quantity,0) where id = new.batch_id;
  elsif tg_op = 'DELETE' and old.batch_id is not null then
    update medicine_batches set quantity = quantity + coalesce(old.quantity,0) where id = old.batch_id;
  end if;
  return null;
end $$;
drop trigger if exists trg_adjust_stock on prescriptions;
create trigger trg_adjust_stock after insert or delete on prescriptions
  for each row execute function adjust_stock();

-- ---------- Treatment advice list ------------------------------------
create table if not exists advice_items (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,          -- varmam, thokkanam, ottradam...
  description text,
  charge      numeric default 0,
  active      boolean default true
);

create table if not exists visit_advice (
  id         uuid primary key default gen_random_uuid(),
  visit_id   uuid not null references visits(id) on delete cascade,
  advice_id  uuid references advice_items(id),
  name       text not null,           -- copied so history stays even if list changes
  notes      text,
  sessions   integer default 1,
  charge     numeric default 0
);

-- ---------- Settings --------------------------------------------------
create table if not exists clinic_settings (
  id                 integer primary key default 1 check (id = 1),
  consultation_fee   numeric default 300,
  fee_valid_days     integer default 30,
  fee_valid_visits   integer default 4,
  gst_enabled        boolean default false,
  gstin              text,
  default_fasting_max numeric default 130,
  default_pp_max      numeric default 180,
  default_low_min     numeric default 70,
  sessions           jsonb default '[{"name":"Morning","start":"06:30","end":"07:30"},{"name":"Evening","start":"18:30","end":"21:00"}]'::jsonb,
  slot_first_min     integer default 20,
  slot_review_min    integer default 10
);
insert into clinic_settings (id) values (1) on conflict do nothing;

-- =====================================================================
-- Security: only logged-in staff (doctor/staff) can read or write.
-- (Patient-app rules are added in Phase 3.)
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['branches','patients','patient_allergies','current_medications',
    'visits','consultations','diet_templates','medicines','medicine_batches',
    'prescriptions','advice_items','visit_advice','clinic_settings']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists staff_all on %I', t);
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
  end loop;
end $$;

alter table staff_profiles enable row level security;
drop policy if exists staff_read on staff_profiles;
create policy staff_read on staff_profiles for select to authenticated using (is_staff() or id = auth.uid());
drop policy if exists doctor_manage on staff_profiles;
create policy doctor_manage on staff_profiles for all to authenticated using (is_doctor()) with check (is_doctor());

-- A few starter rows (edit or delete freely in the app)
insert into advice_items (name, description, charge)
select * from (values
  ('Varmam', 'Varmam therapy session', 0),
  ('Thokkanam', 'Thokkanam massage therapy', 0),
  ('Ottradam', 'Fomentation therapy', 0),
  ('Walking', 'Brisk walking 30 minutes daily', 0)
) v(name, description, charge)
where not exists (select 1 from advice_items);

insert into diet_templates (name, body)
select * from (values
  ('Diabetes – basic', 'Avoid sugar, sweets, white rice in excess, bakery items. Prefer millets, greens, vegetables. Small frequent meals. Dinner before 8 PM.'),
  ('General – light diet', 'Easily digestible food. Avoid oily, fried and cold foods. Drink warm water.')
) v(name, body)
where not exists (select 1 from diet_templates);
