-- Tables nommées : chaque carton QR correspond à une table prévue (numéro + nom).
-- Un seul téléphone par table : la 2e inscription est refusée, sauf si l'animateur
-- rouvre la table (10 minutes) pour changer de téléphone.

create table if not exists public.tables (
  no    int  primary key check (no between 1 and 40),
  name  text not null check (char_length(name) between 1 and 40)
);
alter table public.tables enable row level security;
grant select on public.tables to anon, authenticated;
create policy "tables prévues lisibles" on public.tables for select to anon, authenticated using (true);

alter table public.teams add column if not exists reopen_until timestamptz;

-- Classement : expose aussi la fenêtre de réouverture (pour proposer la reprise sur un autre téléphone)
create or replace view public.leaderboard as
  select t.id, t.name, t.table_no, t.created_at,
         coalesce(sum(a.points), 0)::int as score,
         count(a.id)::int as answered,
         t.reopen_until
  from public.teams t left join public.answers a on a.team_id = t.id
  group by t.id;

-- Inscription par carton : nom imposé par la table prévue, une seule fois
create or replace function public.join_table(p_no int)
returns table (id uuid, name text, table_no text)
language plpgsql security definer set search_path = public, extensions as $$
declare t tables%rowtype; existing teams%rowtype;
begin
  select * into t from tables where tables.no = p_no;
  if not found then
    raise exception 'Table inconnue' using errcode = 'P0007';
  end if;
  select * into existing from teams where teams.table_no = p_no::text;
  if found then
    raise exception 'teams_table_no_unique' using errcode = '23505';
  end if;
  return query
    insert into teams (name, table_no) values (t.name, p_no::text)
    returning teams.id, teams.name, teams.table_no;
end $$;
grant execute on function public.join_table(int) to anon, authenticated;

-- Liste des tables prévues (remplace tout) ; le nombre attendu suit
create or replace function public.admin_set_table_list(p_pin text, p_names jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  perform assert_pin(p_pin);
  if jsonb_typeof(p_names) <> 'array' then
    raise exception 'Liste attendue';
  end if;
  delete from tables where true;
  insert into tables (no, name)
    select ord::int, trim(val) from jsonb_array_elements_text(p_names) with ordinality as e(val, ord)
    where trim(val) <> '';
  select count(*) into n from tables;
  if n > 0 then
    update game set expected_tables = n, updated_at = now() where id = 1;
  end if;
end $$;
grant execute on function public.admin_set_table_list(text, jsonb) to anon, authenticated;

-- Rouvre une table 10 minutes : un autre téléphone peut la reprendre (scores conservés)
create or replace function public.admin_reopen_team(p_pin text, p_id uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  update teams set reopen_until = now() + interval '10 minutes' where id = p_id;
end $$;
grant execute on function public.admin_reopen_team(text, uuid) to anon, authenticated;

-- 8 tables par défaut, à renommer depuis l'espace animateur
insert into public.tables (no, name)
  select g, 'Table ' || g from generate_series(1, 8) g
  on conflict (no) do nothing;
update public.game set expected_tables = 8, updated_at = now() where id = 1;
