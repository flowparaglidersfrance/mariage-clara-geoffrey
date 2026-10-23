-- Rideau : écran noir sur le grand écran tant que l'animateur n'a pas démarré.
alter table public.game add column if not exists curtain boolean not null default true;

create or replace function public.admin_curtain(p_pin text, p_on boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  update game set curtain = coalesce(p_on, false), updated_at = now() where id = 1;
end $$;
grant execute on function public.admin_curtain(text, boolean) to anon, authenticated;

-- Tout changement d'état par l'animateur lève le rideau (ex. « Lancer la question 1 »)
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
    curtain = false,
    updated_at = now()
  where id = 1;
end $$;

-- La remise à zéro rebaisse le rideau
create or replace function public.admin_reset(p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  delete from answers where true;
  delete from teams where true;
  update game set status = 'lobby', current_question_id = null, question_started_at = null, paused = false, paused_at = null, ask_couple = false, curtain = true, updated_at = now() where id = 1;
end $$;
