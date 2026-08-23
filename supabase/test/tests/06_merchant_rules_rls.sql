-- Test izolacji RLS dla `merchant_rules` (0012): reguły kategoryzacji
-- z importu wyciągów są per gospodarstwo — członek jednego gospodarstwa
-- nie widzi ani nie tworzy reguł w cudzym.
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
        'Spożywcze', 'shopping_cart', '#7AB87A', 'expense', true);

-- Reguła Rodziny1 (seed jako postgres — RLS bypass, jak dane zastane).
insert into merchant_rules (household_id, pattern, category_id, created_by)
values ('bbbb1111-0000-0000-0000-000000000001', 'zabka',
        'cccc1111-0000-0000-0000-000000000001',
        'aaaa1111-0000-0000-0000-000000000001');

set local role authenticated;

-- Członek Rodziny1 widzi swoją regułę.
set local test.uid = 'aaaa1111-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from merchant_rules) <> 1 then
    raise exception 'FAIL: u1 powinien widzieć 1 regułę własnego gosp.';
  end if;
end $$;

-- Członek Rodziny2 NIE widzi cudzej reguły.
set local test.uid = 'aaaa2222-0000-0000-0000-000000000002';
do $$ begin
  if (select count(*) from merchant_rules) <> 0 then
    raise exception 'FAIL: u2 NIE powinien widzieć reguł Rodziny1 (RLS)';
  end if;
end $$;

-- Członek Rodziny2 NIE wstawi reguły do cudzego gospodarstwa.
do $$ begin
  begin
    insert into merchant_rules (household_id, pattern, category_id, created_by)
    values ('bbbb1111-0000-0000-0000-000000000001', 'lidl',
            'cccc1111-0000-0000-0000-000000000001',
            'aaaa2222-0000-0000-0000-000000000002');
    raise exception 'FAIL: INSERT do cudzego gospodarstwa powinien być odrzucony';
  exception when insufficient_privilege or check_violation then
    null; -- oczekiwane: RLS with check odrzuca
  end;
end $$;

reset role;
rollback;
