-- Test izolacji RLS dla `recurring_transactions` (0013): szablony
-- transakcji cyklicznych są per gospodarstwo — członek jednego
-- gospodarstwa nie widzi, nie tworzy ani nie zmienia cudzych.
\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email) values
  ('aaaa1111-0000-0000-0000-000000000001', 'm1@x.pl'),
  ('aaaa2222-0000-0000-0000-000000000002', 'm2@x.pl');
insert into households (id, name) values
  ('bbbb1111-0000-0000-0000-000000000001', 'Rodzina1'),
  ('bbbb2222-0000-0000-0000-000000000002', 'Rodzina2');
insert into household_members (household_id, user_id, role) values
  ('bbbb1111-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001', 'owner'),
  ('bbbb2222-0000-0000-0000-000000000002',
   'aaaa2222-0000-0000-0000-000000000002', 'owner');
insert into categories (id, household_id, name, icon, color, type, is_system)
values ('cccc1111-0000-0000-0000-000000000001',
        'bbbb1111-0000-0000-0000-000000000001',
        'Mieszkanie', 'home', '#7AB87A', 'expense', true);

-- Szablon Rodziny1 (seed jako postgres — RLS bypass, jak dane zastane).
insert into recurring_transactions
  (household_id, name, amount_cents, type, category_id,
   day_of_month, next_due, created_by)
values ('bbbb1111-0000-0000-0000-000000000001', 'Czynsz', 250000, 'expense',
        'cccc1111-0000-0000-0000-000000000001',
        10, '2026-09-10', 'aaaa1111-0000-0000-0000-000000000001');

set local role authenticated;

-- Członek Rodziny1 widzi swój szablon.
set local test.uid = 'aaaa1111-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from recurring_transactions) <> 1 then
    raise exception 'FAIL: u1 powinien widzieć 1 szablon własnego gosp.';
  end if;
end $$;

-- Członek Rodziny2 NIE widzi cudzego szablonu.
set local test.uid = 'aaaa2222-0000-0000-0000-000000000002';
do $$ begin
  if (select count(*) from recurring_transactions) <> 0 then
    raise exception 'FAIL: u2 NIE powinien widzieć szablonów Rodziny1 (RLS)';
  end if;
end $$;

-- Członek Rodziny2 NIE wstawi szablonu do cudzego gospodarstwa.
do $$ begin
  begin
    insert into recurring_transactions
      (household_id, name, amount_cents, type, category_id,
       day_of_month, next_due, created_by)
    values ('bbbb1111-0000-0000-0000-000000000001', 'Sabotaż', 100, 'expense',
            'cccc1111-0000-0000-0000-000000000001',
            1, '2026-09-01', 'aaaa2222-0000-0000-0000-000000000002');
    raise exception 'FAIL: INSERT do cudzego gospodarstwa powinien być odrzucony';
  exception when insufficient_privilege or check_violation then
    null; -- oczekiwane: RLS with check odrzuca
  end;
end $$;

-- Członek Rodziny2 NIE zmieni cudzego szablonu (update przez RLS = 0 wierszy).
do $$ begin
  update recurring_transactions set amount_cents = 1;
  if found then
    raise exception 'FAIL: UPDATE cudzego szablonu powinien objąć 0 wierszy';
  end if;
end $$;

reset role;
rollback;
