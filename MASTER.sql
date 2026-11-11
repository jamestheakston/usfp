-- ============================================================
-- USFP — Master schema
-- Run once in the Supabase SQL editor (or `supabase db push`).
--
-- Model: every Scout group has camps. Parents and Scouts share
-- read access to camp data; only parents (account_type = 'parent'
-- in auth user_metadata) can create/edit/delete it.
-- ============================================================

-- ---------- Tables ----------

create table if not exists public.camps (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  location         text,
  start_date       date,
  end_date         date,
  fundraising_target numeric(10,2) default 0,
  created_at       timestamptz not null default now()
);

create table if not exists public.camp_tasks (
  id         uuid primary key default gen_random_uuid(),
  camp_id    uuid not null references public.camps(id) on delete cascade,
  title      text not null,
  due_date   date,
  done       boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.transactions (
  id          uuid primary key default gen_random_uuid(),
  camp_id     uuid not null references public.camps(id) on delete cascade,
  description text not null,
  type        text not null check (type in ('income', 'cost')),
  amount      numeric(10,2) not null,
  entry_date  date not null default current_date,
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now()
);

create table if not exists public.kit_items (
  id         uuid primary key default gen_random_uuid(),
  camp_id    uuid not null references public.camps(id) on delete cascade,
  name       text not null,
  status     text not null default 'needed' check (status in ('packed', 'needed')),
  owner_id   uuid references auth.users(id),
  sort_order int not null default 0
);

create table if not exists public.team_members (
  id           uuid primary key default gen_random_uuid(),
  camp_id      uuid not null references public.camps(id) on delete cascade,
  user_id      uuid references auth.users(id) on delete set null,
  display_name text not null,
  member_role  text not null default 'scout' check (member_role in ('scout', 'leader', 'parent')),
  forms_done   boolean not null default false,
  created_at   timestamptz not null default now()
);

create index if not exists camp_tasks_camp_idx     on public.camp_tasks(camp_id);
create index if not exists transactions_camp_idx    on public.transactions(camp_id);
create index if not exists kit_items_camp_idx       on public.kit_items(camp_id);
create index if not exists team_members_camp_idx    on public.team_members(camp_id);

-- ---------- Role helpers ----------
-- account_type lives in auth user_metadata, which is exposed in the
-- JWT as auth.jwt() -> 'user_metadata'.

create or replace function public.is_parent()
returns boolean language sql stable as $$
  select coalesce(auth.jwt() -> 'user_metadata' ->> 'account_type', '') = 'parent';
$$;

create or replace function public.is_scout()
returns boolean language sql stable as $$
  select coalesce(auth.jwt() -> 'user_metadata' ->> 'account_type', '') = 'scout';
$$;

create or replace function public.is_member(camp uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from public.team_members tm
    where tm.camp_id = camp and tm.user_id = auth.uid()
  );
$$;

-- ---------- Row Level Security ----------

alter table public.camps          enable row level security;
alter table public.camp_tasks     enable row level security;
alter table public.transactions   enable row level security;
alter table public.kit_items      enable row level security;
alter table public.team_members   enable row level security;

-- Everyone signed in can READ shared camp data.
create policy "authenticated read camps"     on public.camps        for select to authenticated using (true);
create policy "authenticated read tasks"     on public.camp_tasks   for select to authenticated using (true);
create policy "authenticated read txns"      on public.transactions for select to authenticated using (true);
create policy "authenticated read kit"       on public.kit_items    for select to authenticated using (true);
create policy "authenticated read members"   on public.team_members for select to authenticated using (true);

-- Only parents can WRITE shared camp data (everything scouts see).
create policy "parents insert camps"     on public.camps        for insert to authenticated with check (public.is_parent());
create policy "parents update camps"     on public.camps        for update to authenticated using (public.is_parent()) with check (public.is_parent());
create policy "parents delete camps"     on public.camps        for delete to authenticated using (public.is_parent());

create policy "parents insert tasks"     on public.camp_tasks   for insert to authenticated with check (public.is_parent());
create policy "parents update tasks"     on public.camp_tasks   for update to authenticated using (public.is_parent()) with check (public.is_parent());
create policy "parents delete tasks"     on public.camp_tasks   for delete to authenticated using (public.is_parent());

create policy "parents insert txns"      on public.transactions for insert to authenticated with check (public.is_parent());
create policy "parents update txns"      on public.transactions for update to authenticated using (public.is_parent()) with check (public.is_parent());
create policy "parents delete txns"      on public.transactions for delete to authenticated using (public.is_parent());

create policy "parents insert kit"       on public.kit_items    for insert to authenticated with check (public.is_parent());
create policy "parents update kit"       on public.kit_items    for update to authenticated using (public.is_parent()) with check (public.is_parent());
create policy "parents delete kit"       on public.kit_items    for delete to authenticated using (public.is_parent());

create policy "parents insert members"   on public.team_members for insert to authenticated with check (public.is_parent());
create policy "parents update members"   on public.team_members for update to authenticated using (public.is_parent()) with check (public.is_parent());
create policy "parents delete members"   on public.team_members for delete to authenticated using (public.is_parent());

-- Scouts may mark their OWN kit item as packed/unpacked.
create policy "scouts update own kit"    on public.kit_items
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ---------- Seed: Kandersteg 2026 ----------

insert into public.camps (name, location, start_date, end_date, fundraising_target)
values ('Kandersteg 2026', 'Kandersteg, Switzerland', '2026-07-12', '2026-07-19', 8000)
on conflict do nothing;

insert into public.camp_tasks (camp_id, title, due_date, done, sort_order)
select c.id, t.title, t.due_date, t.done, t.sort_order
from public.camps c
cross join (values
  ('Confirm campsite booking',     '2026-11-08'::date, true,  1),
  ('Submit grant application',     '2026-11-04'::date, true,  2),
  ('Collect medical forms',        '2026-11-18'::date, false, 3),
  ('Book group travel insurance',  '2026-11-25'::date, false, 4)
) as t(title, due_date, done, sort_order)
where c.name = 'Kandersteg 2026'
on conflict do nothing;

insert into public.transactions (camp_id, description, type, amount, entry_date)
select c.id, t.description, t.type, t.amount, t.entry_date::date
from public.camps c
cross join (values
  ('Autumn quiz night',        'income', 1240, '2026-11-08'),
  ('Kandersteg campsite',      'cost',   1850, '2026-11-06'),
  ('Local community grant',    'income', 1500, '2026-11-04'),
  ('Group travel insurance',   'cost',    420, '2026-11-01')
) as t(description, type, amount, entry_date)
where c.name = 'Kandersteg 2026'
on conflict do nothing;
