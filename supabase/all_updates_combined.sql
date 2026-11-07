-- =====================================================================
-- Meloria Siddha App — ALL updates in one file (2, 3, 4 + bill numbers from 1071)
-- Run once in Supabase → SQL Editor → New query → Run. Safe to run again.
-- =====================================================================

-- =====================================================================
-- Meloria Siddha App — Update 2: Appointments, calendar & health tracking
-- Run once in Supabase → SQL Editor → New query → Run.
-- Safe to re-run.
-- =====================================================================

-- ---------- Patient: consultation mode locked by doctor -------------
alter table patients add column if not exists locked_mode text
  check (locked_mode in ('offline','video','phone'));

-- ---------- Appointments ---------------------------------------------
create table if not exists appointments (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references patients(id) on delete cascade,
  branch_id       integer not null references branches(id) default 1,
  appt_date       date not null,
  start_time      time not null,
  duration_min    integer not null default 10,
  appt_type       text not null default 'review'
                  check (appt_type in ('initial','review','therapy','procedure','program')),
  mode            text not null default 'offline' check (mode in ('offline','video','phone')),
  status          text not null default 'booked'
                  check (status in ('booked','pending_payment','arrived','done','no_show','cancelled')),
  therapy_name    text,                 -- for therapy / procedure / program
  notes           text,
  payment_choice  text default 'clinic' check (payment_choice in ('clinic','online')),
  paid            boolean default false,
  meet_link       text,                 -- Google Meet (patient app phase)
  visit_id        uuid references visits(id) on delete set null,
  booked_by       text default 'staff' check (booked_by in ('staff','patient')),
  created_by      uuid references auth.users(id) default auth.uid(),
  created_at      timestamptz default now()
);
create index if not exists appointments_date_idx on appointments (appt_date, start_time);
create index if not exists appointments_patient_idx on appointments (patient_id);

-- ---------- Tracking plan (what each patient tracks) ------------------
create table if not exists patient_trackers (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references patients(id) on delete cascade,
  kind            text not null,        -- sugar, diet, weight, waist, hip, bp, spo2, periods, sleep, water, exercise, symptoms, custom
  label           text,                 -- custom name (for 'custom') or display override
  unit            text,                 -- for 'custom'
  slots           jsonb default '[]'::jsonb,   -- e.g. ["fasting","after_lunch"]
  frequency       text default 'daily' check (frequency in ('daily','alternate','weekly','days','as_needed')),
  days            jsonb default '[]'::jsonb,   -- for 'days': [1,3,5] (Mon=1)
  reminder_times  jsonb default '[]'::jsonb,   -- ["07:00","14:30"]
  target_low      numeric,
  target_high     numeric,
  start_date      date default current_date,
  end_date        date,
  active          boolean default true,
  created_at      timestamptz default now()
);
create index if not exists patient_trackers_patient_idx on patient_trackers (patient_id);

-- ---------- Tracking chat (entries, messages, test requests) ----------
create table if not exists tracking_messages (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references patients(id) on delete cascade,
  tracker_id    uuid references patient_trackers(id) on delete set null,
  kind          text not null check (kind in ('entry','message','request')),
  entry_type    text,                 -- tracker kind for entries / requests
  slot          text,                 -- fasting, after_lunch, breakfast...
  data          jsonb default '{}'::jsonb,   -- reading values
  body          text,                 -- message text / note
  due_date      date,                 -- for requests
  sender_type   text not null check (sender_type in ('patient','staff')),
  sender_id     uuid default auth.uid(),
  sender_name   text,
  read_by_staff boolean default false,
  read_by_patient boolean default false,
  created_at    timestamptz default now()
);
create index if not exists tracking_messages_patient_idx on tracking_messages (patient_id, created_at);
create index if not exists tracking_messages_unread_idx on tracking_messages (read_by_staff) where read_by_staff = false;

-- ---------- Security: staff (doctor/staff) full access ---------------
do $$
declare t text;
begin
  foreach t in array array['appointments','patient_trackers','tracking_messages']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists staff_all on %I', t);
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
  end loop;
end $$;

-- =====================================================================
-- Meloria Siddha App — Update 3: Billing, programs (packages), GST option
-- Run once in Supabase → SQL Editor → New query → Run. Safe to re-run.
-- =====================================================================

-- ---------- Settings: GST rate (off by default) ----------------------
alter table clinic_settings add column if not exists gst_rate numeric default 0;

-- ---------- Programs / packages --------------------------------------
create table if not exists programs (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  price         numeric not null default 0,
  duration_days integer not null default 90,
  description   text,
  active        boolean default true
);

insert into programs (name, price, duration_days, description)
select * from (values
  ('Diabetes program', 0, 90, 'Consultations included during the program'),
  ('PCOD program', 0, 90, 'Consultations included during the program'),
  ('Weight loss program', 0, 90, 'Consultations included during the program')
) v(name, price, duration_days, description)
where not exists (select 1 from programs);

create table if not exists patient_programs (
  id          uuid primary key default gen_random_uuid(),
  patient_id  uuid not null references patients(id) on delete cascade,
  program_id  uuid references programs(id),
  name        text not null,
  price       numeric default 0,
  start_date  date not null default current_date,
  end_date    date not null,
  status      text default 'active' check (status in ('active','completed','cancelled')),
  created_at  timestamptz default now()
);
create index if not exists patient_programs_patient_idx on patient_programs (patient_id);

-- ---------- Bills ----------------------------------------------------
create table if not exists bill_counters (
  branch_id integer not null references branches(id),
  year      integer not null,
  next_no   integer not null default 1,
  primary key (branch_id, year)
);

create table if not exists bills (
  id                   uuid primary key default gen_random_uuid(),
  bill_no              text unique,              -- MEL1-B-2026-0001 (auto)
  branch_id            integer not null references branches(id) default 1,
  patient_id           uuid not null references patients(id) on delete cascade,
  visit_id             uuid references visits(id) on delete set null,
  patient_program_id   uuid references patient_programs(id) on delete set null,
  bill_date            timestamptz not null default now(),
  subtotal             numeric not null default 0,
  discount             numeric not null default 0,
  gst_rate             numeric not null default 0,
  gst_amount           numeric not null default 0,
  total                numeric not null default 0,
  paid_amount          numeric not null default 0,
  payment_mode         text check (payment_mode in ('cash','upi','card','online','other')),
  status               text not null default 'paid' check (status in ('paid','partial','pending','cancelled')),
  consultation_charged boolean not null default false,   -- used for the "1 month / 4 visits" rule
  notes                text,
  created_by           uuid references auth.users(id) default auth.uid(),
  created_at           timestamptz default now()
);
create index if not exists bills_patient_idx on bills (patient_id, bill_date);
create index if not exists bills_date_idx on bills (bill_date);
create unique index if not exists bills_visit_unique on bills (visit_id) where visit_id is not null and status <> 'cancelled';

create table if not exists bill_items (
  id          uuid primary key default gen_random_uuid(),
  bill_id     uuid not null references bills(id) on delete cascade,
  sort        integer default 0,
  kind        text not null check (kind in ('consultation','medicine','treatment','program','other')),
  description text not null,
  detail      text,              -- batch / expiry / dosage line
  qty         numeric not null default 1,
  rate        numeric not null default 0,
  amount      numeric not null default 0
);
create index if not exists bill_items_bill_idx on bill_items (bill_id);

-- Auto bill number: MEL<branch>-B-<year>-<0001>
create or replace function set_bill_no() returns trigger
language plpgsql security definer set search_path = public as $$
declare y integer := extract(year from coalesce(new.bill_date, now()))::int; n integer; c text;
begin
  if new.bill_no is null then
    insert into bill_counters (branch_id, year, next_no) values (new.branch_id, y, 1)
      on conflict (branch_id, year) do nothing;
    update bill_counters set next_no = next_no + 1
      where branch_id = new.branch_id and year = y
      returning next_no - 1 into n;
    select code into c from branches where id = new.branch_id;
    new.bill_no := 'MEL' || c || '-B-' || y || '-' || lpad(n::text, 4, '0');
  end if;
  return new;
end $$;
drop trigger if exists trg_bill_no on bills;
create trigger trg_bill_no before insert on bills
  for each row execute function set_bill_no();

-- ---------- Security: staff (doctor/staff) full access ---------------
do $$
declare t text;
begin
  foreach t in array array['programs','patient_programs','bill_counters','bills','bill_items']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists staff_all on %I', t);
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
  end loop;
end $$;

-- =====================================================================
-- Meloria Siddha App — Update 4: continuous bill numbers (no yearly restart)
-- Bill numbers become MEL1-B-0001, MEL1-B-0002, … and never reset.
-- Run once in Supabase → SQL Editor → New query → Run. Safe to re-run.
-- =====================================================================

-- One running counter per branch (stored with year = 0).
-- Starts after any bills that already exist, so numbers never repeat.
insert into bill_counters (branch_id, year, next_no)
select b.id, 0, coalesce((select count(*) from bills where branch_id = b.id), 0) + 1
from branches b
on conflict (branch_id, year) do nothing;

create or replace function set_bill_no() returns trigger
language plpgsql security definer set search_path = public as $$
declare n integer; c text;
begin
  if new.bill_no is null then
    insert into bill_counters (branch_id, year, next_no) values (new.branch_id, 0, 1)
      on conflict (branch_id, year) do nothing;
    update bill_counters set next_no = next_no + 1
      where branch_id = new.branch_id and year = 0
      returning next_no - 1 into n;
    select code into c from branches where id = new.branch_id;
    new.bill_no := 'MEL' || c || '-B-' || lpad(n::text, 4, '0');
  end if;
  return new;
end $$;

-- ---------- Bill numbers start from 1071 (never goes backwards) ----------
update bill_counters set next_no = greatest(next_no, 1071) where branch_id = 1 and year = 0;

-- Check: shows the next bill number
select 'Next bill number: MEL1-B-' || lpad(next_no::text, 4, '0') as result from bill_counters where branch_id = 1 and year = 0;
