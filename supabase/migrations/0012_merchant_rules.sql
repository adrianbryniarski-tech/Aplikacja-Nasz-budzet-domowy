-- =====================================================================
-- 0012 — Reguły kategoryzacji sklepów (import wyciągów bankowych)
-- =====================================================================
-- Apka uczy się od domowników: gdy przy imporcie wyciągu ktoś poprawi
-- kategorię dla danego sklepu (np. "ŻABKA" → Spożywcze), zapisujemy
-- regułę per gospodarstwo. Kolejne importy przypisują ją automatycznie.
--
-- pattern = znormalizowany fragment opisu transakcji (lower-case, bez
--           polskich znaków — normalizacja jak w TransactionHasher po
--           stronie Dart). Dopasowanie: `opis CONTAINS pattern`,
--           najdłuższy wygrywa. Wbudowana lista popularnych sieci jest
--           w kodzie apki; te reguły mają nad nią pierwszeństwo.

create table merchant_rules (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  pattern text not null check (char_length(pattern) between 2 and 60),
  category_id uuid not null references categories(id) on delete cascade,
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  unique (household_id, pattern)
);
create index merchant_rules_household_idx on merchant_rules (household_id);

-- RLS — wzorzec jak investment_sales (członkowie gospodarstwa;
-- is_household_member jest security definer, patrz 0002).
alter table merchant_rules enable row level security;
create policy "members read merchant_rules" on merchant_rules for select
  using (is_household_member(household_id));
create policy "members insert merchant_rules" on merchant_rules for insert
  with check (is_household_member(household_id) and created_by = auth.uid());
create policy "members update merchant_rules" on merchant_rules for update
  using (is_household_member(household_id));
create policy "members delete merchant_rules" on merchant_rules for delete
  using (is_household_member(household_id));

-- Bez realtime — reguły czytamy jednorazowo przy imporcie, nie streamujemy.
