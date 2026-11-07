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
