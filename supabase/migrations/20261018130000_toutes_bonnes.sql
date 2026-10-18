-- « Toutes les réponses sont bonnes » : correct = -1 (question 20 de Camille).
-- Toute réponse marque alors les points, et la révélation surligne tous les choix.

alter table public.questions drop constraint if exists questions_correct_check;
alter table public.questions add constraint questions_correct_check
  check (correct >= -1 and correct < jsonb_array_length(options));

create or replace function public.submit_answer(p_team_id uuid, p_question_id uuid, p_choice int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype; q questions%rowtype; elapsed numeric; pts int; n_answers int; n_teams int; ok boolean;
begin
  select * into g from game where id = 1 for update;
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
  if p_choice < 0 or p_choice >= jsonb_array_length(q.options) then
    raise exception 'Réponse inconnue' using errcode = 'P0005';
  end if;
  ok := (q.correct = -1 or q.correct = p_choice);
  if ok then
    pts := 100 + round(50 * greatest(0, g.seconds - elapsed) / g.seconds);
  else
    pts := 0;
  end if;
  insert into answers (team_id, question_id, choice, correct, points)
  values (p_team_id, p_question_id, p_choice, ok, pts);

  select count(*) into n_answers from answers where question_id = p_question_id;
  select count(*) into n_teams from teams;
  if n_answers >= n_teams then
    update game set status = 'suspense', updated_at = now() where id = 1;
  end if;
end $$;
