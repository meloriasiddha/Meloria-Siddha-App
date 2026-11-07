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
