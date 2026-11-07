-- =====================================================================
-- Meloria Siddha App — Update 5: Patient app
--   * patient self sign-up (phone + PIN), linked to records only after staff confirm
--   * reversal programs with page content and plans
--   * clinic closed days / doctor not-available times
--   * secure functions: patients can only ever reach their OWN records
-- Run once in Supabase → SQL Editor → New query → Run. Safe to re-run.
-- =====================================================================

-- ---------- Patients: app status + date of birth ---------------------
alter table patients add column if not exists dob date;
alter table patients add column if not exists status text not null default 'active';
do $$ begin
  alter table patients add constraint patients_status_chk check (status in ('active','app_pending'));
exception when duplicate_object then null; end $$;

-- Patient code is given only to active patients (app sign-ups get one when staff confirm)
create or replace function assign_patient_code(p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare n integer; c text; b integer; code text;
begin
  select branch_id, patient_code into b, code from patients where id = p_id;
  if code is not null then return code; end if;
  update branches set next_patient_number = next_patient_number + 1
    where id = b returning next_patient_number - 1, branches.code into n, c;
  code := 'MEL' || c || '-' || lpad(n::text, 4, '0');
  update patients set patient_code = code where id = p_id;
  return code;
end $$;

create or replace function set_patient_code() returns trigger
language plpgsql security definer set search_path = public as $$
declare n integer; c text;
begin
  if new.patient_code is null and coalesce(new.status, 'active') = 'active' then
    update branches set next_patient_number = next_patient_number + 1
      where id = new.branch_id
      returning next_patient_number - 1, code into n, c;
    new.patient_code := 'MEL' || c || '-' || lpad(n::text, 4, '0');
  end if;
  return new;
end $$;

-- ---------- App accounts ---------------------------------------------
create table if not exists app_accounts (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  phone       text not null,
  full_name   text not null,
  dob         date,
  status      text not null default 'pending' check (status in ('pending','linked','rejected')),
  created_at  timestamptz default now()
);

create table if not exists account_patients (
  user_id     uuid not null references auth.users(id) on delete cascade,
  patient_id  uuid not null references patients(id) on delete cascade,
  primary key (user_id, patient_id)
);

create or replace function my_patient_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select patient_id from account_patients where user_id = auth.uid();
$$;

-- ---------- Appointments: extra fields --------------------------------
alter table appointments add column if not exists program_interest text;
alter table appointments add column if not exists refund_choice text;

-- ---------- Availability: closed days / sessions, doctor not available --
create table if not exists clinic_blocks (
  id          uuid primary key default gen_random_uuid(),
  block_date  date not null,
  start_time  time,          -- null = whole day
  end_time    time,
  kind        text not null default 'closed' check (kind in ('closed','unavailable')),
  reason      text,
  created_at  timestamptz default now()
);
create index if not exists clinic_blocks_date_idx on clinic_blocks (block_date);

-- ---------- Programs: page content + plans ----------------------------
alter table programs add column if not exists subtitle text;
alter table programs add column if not exists who_for text;
alter table programs add column if not exists steps jsonb default '[]'::jsonb;
alter table programs add column if not exists includes text;
alter table programs add column if not exists tracking_template text;
alter table programs add column if not exists color text;
alter table programs add column if not exists sort integer default 0;

update programs set name = 'Diabetes Remission Program' where name = 'Diabetes program';
update programs set name = 'PCOS Remission Program' where name = 'PCOD program';
update programs set name = 'Weight Loss Program' where name = 'Weight loss program';
insert into programs (name, price, duration_days)
select v.n, 17999, 365 from (values ('Diabetes Remission Program'),('PCOS Remission Program'),
  ('Weight Loss Program'),('Fatty Liver Remission Program'),('Cholesterol Remission Program')) v(n)
where not exists (select 1 from programs p where p.name = v.n);

update programs set sort = 1, color = '#2B6670', tracking_template = 'Diabetes',
  subtitle = 'Lower your sugar levels and reduce dependence on medicines – with Siddha care, a personal diet plan and doctor-guided daily tracking.',
  who_for = 'Adults with type 2 diabetes or prediabetes who want to bring sugar levels down under medical supervision.',
  steps = '["Detailed first consultation – history, medicines, sugar reports, lifestyle","Personal Siddha treatment plan, with Varmam therapy where suitable","South Indian diet plan with portion guidance","Daily sugar, meal and weight tracking in the app","Regular reviews – the doctor adjusts your plan from your readings","Existing medicines are never stopped suddenly; any change is planned with you"]',
  includes = 'Consultations during the program, diet plan, app tracking with doctor feedback, reminders and progress reviews.'
where name = 'Diabetes Remission Program' and subtitle is null;

update programs set sort = 2, color = '#6B5679', tracking_template = 'PCOD',
  subtitle = 'Support regular cycles and hormonal balance naturally – Siddha medicines, a weight-focused diet plan and cycle tracking.',
  who_for = 'Women with PCOS/PCOD symptoms such as irregular periods, weight gain, acne or hair changes.',
  steps = '["First consultation – cycle history, symptoms, reports, lifestyle","Siddha medicines and therapies for hormonal balance","Diet and activity plan focused on weight and insulin balance","Track periods, weight, waist, hip and meals in the app","Monthly reviews of cycle regularity and symptoms"]',
  includes = 'Consultations, diet and exercise plan, cycle and weight tracking, doctor feedback in the app.'
where name = 'PCOS Remission Program' and subtitle is null;

update programs set sort = 3, color = '#4F7564', tracking_template = 'Weight loss',
  subtitle = 'Steady, healthy weight loss without crash diets – a realistic diet plan, Siddha support and weekly progress checks.',
  who_for = 'Adults who want steady, healthy weight loss.',
  steps = '["Body assessment – weight, waist, hip, BMI, eating habits","Personal diet plan with realistic portions and meal timing","Siddha medicines and therapies for digestion and metabolism, where suitable","Daily tracking of weight, meals, water and exercise","Weekly progress checks and plan adjustments"]',
  includes = 'Consultations, diet plan, activity guidance, tracking with doctor feedback, progress reviews.'
where name = 'Weight Loss Program' and subtitle is null;

update programs set sort = 4, color = '#8A6A3F', tracking_template = 'Weight loss',
  subtitle = 'Reduce liver fat step by step – Siddha liver care, a focused diet plan and gradual weight and waist targets.',
  who_for = 'People diagnosed with fatty liver (NAFLD) on scan or with raised liver enzymes.',
  steps = '["First consultation with scan and liver function reports","Siddha liver-supportive medicines and diet plan","Gradual weight and waist reduction targets","Track weight, waist, meals and exercise in the app","Repeat reports at review points to see progress"]',
  includes = 'Consultations, diet plan, tracking with doctor feedback, guidance on repeat tests.'
where name = 'Fatty Liver Remission Program' and subtitle is null;

update programs set sort = 5, color = '#7A4A4A', tracking_template = 'Weight loss',
  subtitle = 'Improve your lipid profile through diet, lifestyle and Siddha care, reviewed with your reports.',
  who_for = 'People with high cholesterol or triglycerides.',
  steps = '["First consultation with lipid profile and heart-risk history","Siddha medicines where suitable, plus a heart-friendly diet plan","Activity plan to suit your age and fitness","Track weight, meals and exercise, and add lab values in the app","Review with repeat lipid profile at set intervals"]',
  includes = 'Consultations, diet and activity plan, tracking with doctor feedback, review of reports.'
where name = 'Cholesterol Remission Program' and subtitle is null;

create table if not exists program_plans (
  id          uuid primary key default gen_random_uuid(),
  program_id  uuid not null references programs(id) on delete cascade,
  months      integer not null,
  price       numeric not null,
  recommended boolean default false,
  note        text,
  unique (program_id, months)
);
insert into program_plans (program_id, months, price, recommended, note)
select p.id, v.m, v.pr, v.rec, v.note from programs p
cross join (values (1, 1999, false, null::text), (3, 4999, false, null), (6, 9999, false, null),
                   (12, 17999, true, 'Includes treatment & post-treatment follow-up')) v(m, pr, rec, note)
where p.name like '%Program' and p.active
on conflict (program_id, months) do nothing;

-- ---------- Doctor profile + clinic UPI (shown in the patient app) -----
alter table clinic_settings add column if not exists doctor_name text default 'Dr J J Amala Janice Seelan';
alter table clinic_settings add column if not exists doctor_qualification text default 'BSMS';
alter table clinic_settings add column if not exists doctor_title text default 'Siddha Physician';
alter table clinic_settings add column if not exists doctor_specialty text default 'Specialist – Diabetes & Varmam';
alter table clinic_settings add column if not exists doctor_reg_no text default '8239/A';
alter table clinic_settings add column if not exists doctor_experience_area text default 'Diabetes & Pain Management';
alter table clinic_settings add column if not exists doctor_experience_since date default '2023-11-07';
alter table clinic_settings add column if not exists clinic_upi_id text;

-- ---------- Requests from the app --------------------------------------
create table if not exists program_requests (
  id          uuid primary key default gen_random_uuid(),
  patient_id  uuid not null references patients(id) on delete cascade,
  program_id  uuid references programs(id),
  program_name text,
  months      integer,
  price       numeric,
  status      text default 'new' check (status in ('new','enrolled','declined')),
  created_at  timestamptz default now()
);

create table if not exists pin_reset_requests (
  id          uuid primary key default gen_random_uuid(),
  phone       text not null,
  status      text default 'new' check (status in ('new','done')),
  created_at  timestamptz default now()
);

-- Staff-only access to the new tables (patients use the functions below)
do $$
declare t text;
begin
  foreach t in array array['app_accounts','account_patients','clinic_blocks','program_plans',
                           'program_requests','pin_reset_requests']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists staff_all on %I', t);
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
  end loop;
end $$;

-- =====================================================================
-- Helper: is a slot free?
-- =====================================================================
create or replace function slot_free(p_date date, p_start time, p_dur integer, p_exclude uuid default null)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare s jsonb; ok boolean := false; p_end time := p_start + make_interval(mins => p_dur);
begin
  -- inside a clinic session
  for s in select jsonb_array_elements(sessions) from clinic_settings where id = 1 loop
    if p_start >= (s->>'start')::time and p_end <= (s->>'end')::time then ok := true; end if;
  end loop;
  if not ok then return false; end if;
  -- not in the past (Indian time)
  if (p_date + p_start) <= (now() at time zone 'Asia/Kolkata') then return false; end if;
  -- not closed / doctor not available
  if exists (select 1 from clinic_blocks b where b.block_date = p_date
             and (b.start_time is null or (p_start < b.end_time and p_end > b.start_time))) then
    return false;
  end if;
  -- no overlapping appointment
  if exists (select 1 from appointments a where a.appt_date = p_date
             and a.status not in ('cancelled','no_show')
             and (p_exclude is null or a.id <> p_exclude)
             and p_start < a.start_time + make_interval(mins => a.duration_min)
             and p_end > a.start_time) then
    return false;
  end if;
  return true;
end $$;

create or replace function suggested_type(p_patient uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when max(visit_date) is null or max(visit_date) < current_date - 90
              then 'initial' else 'review' end
  from visits where patient_id = p_patient and status <> 'cancelled';
$$;

-- =====================================================================
-- PATIENT APP FUNCTIONS (each checks the patient belongs to the caller)
-- =====================================================================
create or replace function app_register(p_name text, p_phone text, p_dob date)
returns json language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); pid uuid;
begin
  if uid is null then raise exception 'Not signed in'; end if;
  insert into app_accounts (user_id, phone, full_name, dob) values (uid, p_phone, p_name, p_dob)
    on conflict (user_id) do update set full_name = excluded.full_name, dob = excluded.dob;
  if not exists (select 1 from account_patients where user_id = uid) then
    insert into patients (name, phone, dob, age, status, branch_id)
      values (p_name, p_phone, p_dob, extract(year from age(p_dob))::int, 'app_pending', 1)
      returning id into pid;
    insert into account_patients (user_id, patient_id) values (uid, pid);
  end if;
  return app_me();
end $$;

create or replace function app_me() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'account', (select row_to_json(a) from app_accounts a where a.user_id = auth.uid()),
    'patients', coalesce((select json_agg(json_build_object(
        'id', p.id, 'name', p.name, 'patient_code', p.patient_code, 'status', p.status,
        'dob', p.dob, 'age', p.age, 'gender', p.gender, 'phone', p.phone, 'locked_mode', p.locked_mode)
        order by p.created_at)
      from patients p where p.id in (select my_patient_ids())), '[]'::json));
$$;

create or replace function app_doctor() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('name', doctor_name, 'qualification', doctor_qualification, 'title', doctor_title,
    'specialty', doctor_specialty, 'reg_no', doctor_reg_no, 'experience_area', doctor_experience_area,
    'experience_years', greatest(0, extract(year from age(current_date, doctor_experience_since))::int),
    'upi_id', clinic_upi_id, 'sessions', sessions, 'slot_first_min', slot_first_min,
    'slot_review_min', slot_review_min)
  from clinic_settings where id = 1;
$$;

create or replace function app_programs() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
    'id', p.id, 'name', p.name, 'subtitle', p.subtitle, 'who_for', p.who_for, 'steps', p.steps,
    'includes', p.includes, 'color', p.color,
    'plans', coalesce((select json_agg(json_build_object('months', pl.months, 'price', pl.price,
                 'recommended', pl.recommended, 'note', pl.note) order by pl.months)
               from program_plans pl where pl.program_id = p.id), '[]'::json))
    order by p.sort, p.name), '[]'::json)
  from programs p where p.active and p.name like '%Program';
$$;

create or replace function app_day(p_date date) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'blocks', coalesce((select json_agg(json_build_object('start', start_time, 'end', end_time, 'kind', kind))
                        from clinic_blocks where block_date = p_date), '[]'::json),
    'busy', coalesce((select json_agg(json_build_object('start', start_time, 'dur', duration_min))
                      from appointments where appt_date = p_date and status not in ('cancelled','no_show')), '[]'::json));
$$;

create or replace function app_appointments(p_patient uuid) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(row_to_json(a) order by a.appt_date desc, a.start_time desc), '[]'::json)
  from (select id, appt_date, start_time, duration_min, appt_type, mode, status, therapy_name,
               meet_link, payment_choice, paid, booked_by, program_interest, refund_choice
        from appointments where patient_id = p_patient
          and p_patient in (select my_patient_ids())) a;
$$;

create or replace function app_book(p_patient uuid, p_date date, p_time time, p_mode text,
                                    p_payment text, p_program text default null, p_notes text default null)
returns json language plpgsql security definer set search_path = public as $$
declare t text; dur integer; locked text; st text; r appointments;
begin
  if p_patient not in (select my_patient_ids()) then raise exception 'Not allowed'; end if;
  select locked_mode into locked from patients where id = p_patient;
  if locked is not null and locked <> p_mode then raise exception 'The doctor has set % consultation for you', locked; end if;
  if p_mode not in ('offline','video','phone') then raise exception 'Invalid mode'; end if;
  t := suggested_type(p_patient);
  select case when t = 'initial' then slot_first_min else slot_review_min end into dur from clinic_settings where id = 1;
  if not slot_free(p_date, p_time, dur) then raise exception 'Sorry, this slot was just taken. Please choose another.'; end if;
  st := case when p_mode <> 'offline' then 'pending_payment' else 'booked' end;
  insert into appointments (patient_id, appt_date, start_time, duration_min, appt_type, mode, status,
                            payment_choice, booked_by, program_interest, notes, created_by)
    values (p_patient, p_date, p_time, dur, t, p_mode, st,
            case when p_mode <> 'offline' then 'online' else coalesce(p_payment, 'clinic') end,
            'patient', p_program, p_notes, auth.uid())
    returning * into r;
  return row_to_json(r);
end $$;

create or replace function app_cancel(p_appt uuid, p_refund text default null) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  select * into a from appointments where id = p_appt;
  if a.id is null or a.patient_id not in (select my_patient_ids()) then raise exception 'Not allowed'; end if;
  if (a.appt_date + a.start_time) - interval '30 minutes' < (now() at time zone 'Asia/Kolkata') then
    raise exception 'Appointments can be cancelled up to 30 minutes before.';
  end if;
  update appointments set status = 'cancelled',
    refund_choice = case when paid then coalesce(p_refund, 'credit') else null end
  where id = p_appt;
end $$;

create or replace function app_reschedule(p_appt uuid, p_date date, p_time time) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  select * into a from appointments where id = p_appt;
  if a.id is null or a.patient_id not in (select my_patient_ids()) then raise exception 'Not allowed'; end if;
  if (a.appt_date + a.start_time) - interval '30 minutes' < (now() at time zone 'Asia/Kolkata') then
    raise exception 'Appointments can be changed up to 30 minutes before.';
  end if;
  if not slot_free(p_date, p_time, a.duration_min, a.id) then raise exception 'Sorry, this slot is not available.'; end if;
  update appointments set appt_date = p_date, start_time = p_time where id = p_appt;
end $$;

create or replace function app_visits(p_patient uuid) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(v order by v.created_at desc), '[]'::json) from (
    select vi.id, vi.visit_date, vi.visit_type, vi.mode, vi.main_complaint, vi.created_at,
           c.complaints, c.diet_plan, c.next_visit,
           (select coalesce(json_agg(json_build_object('name', m.name, 'form', m.form, 'unit', m.unit,
                    'dose', p.dose, 'frequency', p.frequency, 'timing', p.timing, 'days', p.days,
                    'quantity', p.quantity, 'instructions', p.instructions,
                    'batch_no', b.batch_no, 'expiry_date', b.expiry_date) order by p.created_at), '[]'::json)
            from prescriptions p join medicines m on m.id = p.medicine_id
            left join medicine_batches b on b.id = p.batch_id where p.visit_id = vi.id) as medicines,
           (select coalesce(json_agg(json_build_object('name', a.name, 'sessions', a.sessions, 'notes', a.notes)), '[]'::json)
            from visit_advice a where a.visit_id = vi.id) as advice
    from visits vi left join consultations c on c.visit_id = vi.id
    where vi.patient_id = p_patient and vi.status <> 'cancelled'
      and p_patient in (select my_patient_ids())
  ) v;
$$;

create or replace function app_bills(p_patient uuid) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(row_to_json(b) order by b.bill_date desc), '[]'::json)
  from (select id, bill_no, bill_date, total, paid_amount, status from bills
        where patient_id = p_patient and status <> 'cancelled'
          and p_patient in (select my_patient_ids())) b;
$$;

create or replace function app_bill(p_bill uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'bill', row_to_json(b),
    'items', (select coalesce(json_agg(row_to_json(i) order by i.sort), '[]'::json) from bill_items i where i.bill_id = b.id),
    'patient', (select json_build_object('name', p.name, 'patient_code', p.patient_code, 'age', p.age,
                       'gender', p.gender, 'phone', p.phone) from patients p where p.id = b.patient_id),
    'visit', (select json_build_object('visit_type', v.visit_type, 'mode', v.mode) from visits v where v.id = b.visit_id),
    'next_visit', (select c.next_visit from consultations c where c.visit_id = b.visit_id),
    'doctor', (select doctor_name from clinic_settings where id = 1))
  from bills b where b.id = p_bill and b.patient_id in (select my_patient_ids());
$$;

create or replace function app_trackers(p_patient uuid) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(row_to_json(t) order by t.created_at), '[]'::json)
  from patient_trackers t where t.patient_id = p_patient and t.active
    and p_patient in (select my_patient_ids());
$$;

create or replace function app_thread(p_patient uuid) returns json
language plpgsql security definer set search_path = public as $$
declare r json;
begin
  if p_patient not in (select my_patient_ids()) then return '[]'::json; end if;
  update tracking_messages set read_by_patient = true where patient_id = p_patient and sender_type = 'staff' and not read_by_patient;
  select coalesce(json_agg(row_to_json(m) order by m.created_at), '[]'::json) into r
  from (select id, tracker_id, kind, entry_type, slot, data, body, due_date, sender_type, sender_name, created_at
        from tracking_messages where patient_id = p_patient
        order by created_at desc limit 300) m;
  return r;
end $$;

create or replace function app_post(p_patient uuid, p_kind text, p_tracker uuid, p_entry_type text,
                                    p_slot text, p_data jsonb, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if p_patient not in (select my_patient_ids()) then raise exception 'Not allowed'; end if;
  if p_kind not in ('entry','message') then raise exception 'Invalid'; end if;
  select name into nm from patients where id = p_patient;
  insert into tracking_messages (patient_id, tracker_id, kind, entry_type, slot, data, body,
                                 sender_type, sender_name, read_by_staff, read_by_patient)
  values (p_patient, p_tracker, p_kind, p_entry_type, p_slot, coalesce(p_data, '{}'::jsonb), p_body,
          'patient', nm, false, true);
end $$;

create or replace function app_join_program(p_patient uuid, p_program uuid, p_months integer) returns void
language plpgsql security definer set search_path = public as $$
declare nm text; pr numeric;
begin
  if p_patient not in (select my_patient_ids()) then raise exception 'Not allowed'; end if;
  select name into nm from programs where id = p_program;
  select price into pr from program_plans where program_id = p_program and months = p_months;
  insert into program_requests (patient_id, program_id, program_name, months, price)
    values (p_patient, p_program, nm, p_months, pr);
end $$;

-- Forgot PIN: allowed without signing in; only records the request
create or replace function app_request_pin_reset(p_phone text) returns void
language sql security definer set search_path = public as $$
  insert into pin_reset_requests (phone) values (left(regexp_replace(p_phone, '\D', '', 'g'), 15));
$$;
grant execute on function app_request_pin_reset(text) to anon;

-- =====================================================================
-- STAFF FUNCTIONS (doctor / staff only)
-- =====================================================================
-- Link an app account to an existing patient record; moves anything the
-- account did while pending (bookings, tracker, requests) to that record.
create or replace function staff_link_account(p_user uuid, p_patient uuid) returns void
language plpgsql security definer set search_path = public as $$
declare pend uuid;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  for pend in select ap.patient_id from account_patients ap join patients p on p.id = ap.patient_id
              where ap.user_id = p_user and p.status = 'app_pending' loop
    update appointments set patient_id = p_patient where patient_id = pend;
    update tracking_messages set patient_id = p_patient where patient_id = pend;
    update patient_trackers set patient_id = p_patient where patient_id = pend;
    update program_requests set patient_id = p_patient where patient_id = pend;
    delete from account_patients where patient_id = pend;
    delete from patients where id = pend;
  end loop;
  insert into account_patients (user_id, patient_id) values (p_user, p_patient) on conflict do nothing;
  update patients set dob = coalesce(patients.dob, a.dob) from app_accounts a
    where patients.id = p_patient and a.user_id = p_user;
  update app_accounts set status = 'linked' where user_id = p_user;
end $$;

-- Confirm an app sign-up as a brand-new patient (gives the MEL1 ID)
create or replace function staff_confirm_new(p_user uuid) returns text
language plpgsql security definer set search_path = public as $$
declare pend uuid; code text;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  for pend in select ap.patient_id from account_patients ap join patients p on p.id = ap.patient_id
              where ap.user_id = p_user and p.status = 'app_pending' loop
    update patients set status = 'active' where id = pend;
    code := assign_patient_code(pend);
  end loop;
  update app_accounts set status = 'linked' where user_id = p_user;
  return code;
end $$;

create or replace function staff_reject_account(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  update app_accounts set status = 'rejected' where user_id = p_user;
end $$;

-- Set a temporary PIN for a patient account (forgot PIN)
create or replace function staff_reset_pin(p_phone text, p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  if length(p_pin) <> 6 then raise exception 'PIN must be 6 digits'; end if;
  select user_id into uid from app_accounts
    where right(regexp_replace(phone, '\D', '', 'g'), 10) = right(regexp_replace(p_phone, '\D', '', 'g'), 10)
    limit 1;
  if uid is null then raise exception 'No app account for this phone number'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf')) where id = uid;
  update pin_reset_requests set status = 'done'
    where right(phone, 10) = right(regexp_replace(p_phone, '\D', '', 'g'), 10) and status = 'new';
end $$;

-- App sign-ups list for staff, with possible matches by phone number
create or replace function staff_app_signups() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(x order by x.created_at desc), '[]'::json) from (
    select a.user_id, a.phone, a.full_name, a.dob, a.status, a.created_at,
      (select coalesce(json_agg(json_build_object('id', p.id, 'name', p.name, 'patient_code', p.patient_code,
                 'age', p.age, 'phone', p.phone)), '[]'::json)
       from patients p where p.status = 'active'
         and right(regexp_replace(p.phone, '\D', '', 'g'), 10) = right(regexp_replace(a.phone, '\D', '', 'g'), 10)) as matches,
      (select coalesce(json_agg(json_build_object('id', p.id, 'name', p.name, 'patient_code', p.patient_code,
                 'status', p.status)), '[]'::json)
       from account_patients ap join patients p on p.id = ap.patient_id where ap.user_id = a.user_id) as linked
    from app_accounts a where is_staff()
  ) x;
$$;
