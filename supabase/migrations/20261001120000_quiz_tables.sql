-- Quiz des tables, mariage de Clare & Geoffrey
-- Deux tables : les équipes (une par table de mariage) et leurs réponses.
-- Accès anonyme en lecture et en insertion uniquement ; jamais de modification ni de suppression.

create table public.teams (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 40),
  table_no    text check (table_no is null or char_length(table_no) <= 12),
  created_at  timestamptz not null default now()
);

create table public.answers (
  id            uuid primary key default gen_random_uuid(),
  team_id       uuid not null references public.teams(id) on delete cascade,
  question_idx  int  not null check (question_idx between 0 and 99),
  choice        int  not null check (choice between -1 and 3),   -- -1 : temps écoulé
  correct       boolean not null,
  points        int  not null check (points between 0 and 150),
  created_at    timestamptz not null default now(),
  unique (team_id, question_idx)                                   -- une seule réponse par question
);

create index answers_team_id_idx on public.answers (team_id);

-- Exposition à l'API Data (les nouvelles tables ne le sont plus par défaut)
grant usage on schema public to anon, authenticated;
grant select, insert on table public.teams   to anon, authenticated;
grant select, insert on table public.answers to anon, authenticated;

-- RLS : tout le monde lit, tout le monde insère, personne ne modifie
alter table public.teams   enable row level security;
alter table public.answers enable row level security;

create policy "lecture publique des équipes"  on public.teams   for select to anon, authenticated using (true);
create policy "inscription d'une équipe"      on public.teams   for insert to anon, authenticated with check (true);
create policy "lecture publique des réponses" on public.answers for select to anon, authenticated using (true);
create policy "enregistrement d'une réponse"  on public.answers for insert to anon, authenticated with check (true);

-- Temps réel : le classement se rafraîchit à chaque insertion
alter publication supabase_realtime add table public.teams, public.answers;
