-- =====================================================================
-- 0013 — Transakcje cykliczne (czynsz, abonamenty, wypłata)
-- =====================================================================
-- Szablon + data następnego naliczenia. Materializację robi apka przy
-- starcie: dla każdego aktywnego szablonu z next_due <= dziś wstawia
-- transakcję zwykłym flow z dedup_hash — hash liczy (data|kwota|nazwa),
-- więc oba telefony mogą materializować równolegle bez dubli — po czym
-- przesuwa next_due o miesiąc (optimistic guard na starej wartości).
--
-- day_of_month 29–31 w krótszych miesiącach naliczy się ostatniego dnia
-- miesiąca (clamp po stronie apki).

-- Nowe źródło transakcji: wpisy naliczone z szablonu cyklicznego.
alter type tx_source add value if not exists 'recurring';

create table recurring_transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  amount_cents bigint not null check (amount_cents > 0),
  type tx_type not null,
  category_id uuid not null references categories(id) on delete cascade,
  note text,
  day_of_month int not null check (day_of_month between 1 and 31),
  next_due date not null,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index recurring_transactions_household_idx
  on recurring_transactions (household_id);

-- RLS — wzorzec jak merchant_rules (członkowie gospodarstwa;
-- is_household_member jest security definer, patrz 0002).
alter table recurring_transactions enable row level security;
create policy "members read recurring" on recurring_transactions for select
  using (is_household_member(household_id));
create policy "members insert recurring" on recurring_transactions for insert
  with check (is_household_member(household_id) and created_by = auth.uid());
create policy "members update recurring" on recurring_transactions for update
  using (is_household_member(household_id));
create policy "members delete recurring" on recurring_transactions for delete
  using (is_household_member(household_id));

-- Bez realtime — lista czytana przy wejściu na ekran i po każdej zmianie.
