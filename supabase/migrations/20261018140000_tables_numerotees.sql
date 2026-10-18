-- Un QR code par table (#/jouer/N) : numéro unique, nombre de tables attendues,
-- et verrou de lancement que l'animateur peut lever.

alter table public.game
  add column if not exists expected_tables int not null default 10 check (expected_tables between 1 and 30),
  add column if not exists require_all boolean not null default true;

-- Un seul numéro de table par équipe
create unique index if not exists teams_table_no_unique on public.teams (table_no) where table_no is not null;

create or replace function public.admin_set_tables(p_pin text, p_expected int, p_require boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  update game set
    expected_tables = coalesce(p_expected, expected_tables),
    require_all = coalesce(p_require, require_all),
    updated_at = now()
  where id = 1;
end $$;
grant execute on function public.admin_set_tables(text, int, boolean) to anon, authenticated;

-- Lancement de la partie refusé tant que les tables attendues ne sont pas toutes inscrites (verrou levable)
create or replace function public.admin_set_game(p_pin text, p_status text, p_question_id uuid, p_seconds int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype; n int;
begin
  perform assert_pin(p_pin);
  select * into g from game where id = 1 for update;
  if p_status = 'question' and g.status = 'lobby' and g.require_all then
    select count(*) into n from teams;
    if n < g.expected_tables then
      raise exception 'Il manque des tables : % inscrite(s) sur %', n, g.expected_tables using errcode = 'P0006';
    end if;
  end if;
  update game set
    status = p_status,
    current_question_id = p_question_id,
    seconds = coalesce(p_seconds, seconds),
    question_started_at = case when p_status = 'question' and (status <> 'question' or current_question_id is distinct from p_question_id or paused) then now() else question_started_at end,
    paused = false, paused_at = null,
    ask_couple = false,
    updated_at = now()
  where id = 1;
end $$;
