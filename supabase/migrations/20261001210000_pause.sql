-- Pause : gèle le chrono, bloque les réponses, affiche un écran d'attente partout.
alter table public.game
  add column paused    boolean not null default false,
  add column paused_at timestamptz;

create or replace function public.admin_pause(p_pin text, p_paused boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype;
begin
  perform assert_pin(p_pin);
  select * into g from game where id = 1;
  if p_paused and not g.paused then
    update game set paused = true, paused_at = now(), updated_at = now() where id = 1;
  elsif not p_paused and g.paused then
    -- on décale le départ de la question de la durée de la pause : le temps restant est conservé
    update game set
      question_started_at = case when status = 'question' and question_started_at is not null and paused_at is not null
                                 then question_started_at + (now() - paused_at) else question_started_at end,
      paused = false, paused_at = null, updated_at = now()
    where id = 1;
  end if;
end $$;
grant execute on function public.admin_pause(text, boolean) to anon, authenticated;

-- Tout changement d'état par l'animateur lève la pause
create or replace function public.admin_set_game(p_pin text, p_status text, p_question_id uuid, p_seconds int) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  update game set
    status = p_status,
    current_question_id = p_question_id,
    seconds = coalesce(p_seconds, seconds),
    question_started_at = case when p_status = 'question' and (status <> 'question' or current_question_id is distinct from p_question_id or paused) then now() else question_started_at end,
    paused = false, paused_at = null,
    updated_at = now()
  where id = 1;
end $$;

-- Pas de réponse pendant la pause
create or replace function public.submit_answer(p_team_id uuid, p_question_id uuid, p_choice int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype; q questions%rowtype; elapsed numeric; pts int;
begin
  select * into g from game where id = 1;
  if g.paused then
    raise exception 'La partie est en pause' using errcode = 'P0004';
  end if;
  if g.status <> 'question' or g.current_question_id is distinct from p_question_id then
    raise exception 'Cette question n''est plus ouverte' using errcode = 'P0001';
  end if;
  elapsed := extract(epoch from (now() - g.question_started_at));
  if elapsed > g.seconds + 3 then
    raise exception 'Temps écoulé' using errcode = 'P0002';
  end if;
  select * into q from questions where id = p_question_id;
  if q.correct = p_choice then
    pts := 100 + round(50 * greatest(0, g.seconds - elapsed) / g.seconds);
  else
    pts := 0;
  end if;
  insert into answers (team_id, question_id, choice, correct, points)
  values (p_team_id, p_question_id, p_choice, q.correct = p_choice, pts);
end $$;
