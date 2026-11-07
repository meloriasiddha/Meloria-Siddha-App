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
