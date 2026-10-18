-- Questions à plusieurs bonnes réponses (Q10 : Soleil et Pluie ; Q20 : les trois).
-- La table coche toutes les réponses qu'elle pense bonnes puis valide.
-- Points : 100 au prorata (bonnes cochées − mauvaises cochées) / nombre de bonnes,
-- plus le bonus de rapidité (jusqu'à 50) uniquement si la sélection est exacte.

alter table public.questions
  add column if not exists multi    boolean not null default false,
  add column if not exists corrects int[];
alter table public.questions drop constraint if exists questions_multi_check;
alter table public.questions add constraint questions_multi_check
  check (not multi or (corrects is not null and cardinality(corrects) >= 1));

-- Une réponse multiple : choice vide, choices rempli
alter table public.answers alter column choice drop not null;
alter table public.answers drop constraint if exists answers_choice_check;
alter table public.answers add constraint answers_choice_check check (choice is null or choice between 0 and 3);
alter table public.answers add column if not exists choices int[];
alter table public.answers drop constraint if exists answers_one_kind_check;
alter table public.answers add constraint answers_one_kind_check
  check ((choice is not null and choices is null) or (choice is null and choices is not null));

-- Les téléphones doivent savoir qu'ils peuvent cocher plusieurs réponses (sans connaître lesquelles)
create or replace view public.questions_public as
  select id, position, course, text, options, multi from public.questions;

-- Répartition des votes : une réponse multiple compte une voix par case cochée
create or replace view public.choice_counts as
  select question_id, choice, count(*)::int as n
  from (
    select question_id, choice from public.answers where choice is not null
    union all
    select a.question_id, c.choice from public.answers a, unnest(a.choices) as c(choice)
  ) v
  group by question_id, choice;

-- Sauvegarde d'une question : nouveaux paramètres multi / corrects
drop function if exists public.admin_save_question(text, uuid, int, text, text, jsonb, int, text, text, text);
create or replace function public.admin_save_question(
  p_pin text, p_id uuid, p_position int, p_course text, p_text text, p_options jsonb, p_correct int, p_anecdote text,
  p_media_url text default null, p_media_type text default null, p_multi boolean default false, p_corrects int[] default null
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_corrects int[];
begin
  perform assert_pin(p_pin);
  if coalesce(p_multi, false) then
    select array_agg(distinct c order by c) into v_corrects from unnest(p_corrects) c
      where c >= 0 and c < jsonb_array_length(p_options);
    if v_corrects is null or cardinality(v_corrects) = 0 then
      raise exception 'Cochez au moins une bonne réponse';
    end if;
  end if;
  if p_id is null then
    insert into questions (position, course, text, options, correct, anecdote, media_url, media_type, multi, corrects)
    values (p_position, p_course, p_text, p_options, p_correct, coalesce(p_anecdote, ''), nullif(p_media_url, ''), nullif(p_media_type, ''), coalesce(p_multi, false), v_corrects)
    returning id into v_id;
  else
    update questions set position = p_position, course = p_course, text = p_text, options = p_options,
      correct = p_correct, anecdote = coalesce(p_anecdote, ''), media_url = nullif(p_media_url, ''), media_type = nullif(p_media_type, ''),
      multi = coalesce(p_multi, false), corrects = v_corrects
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end $$;
grant execute on function public.admin_save_question(text, uuid, int, text, text, jsonb, int, text, text, text, boolean, int[]) to anon, authenticated;

-- Réponse multiple d'une table
create or replace function public.submit_answers(p_team_id uuid, p_question_id uuid, p_choices int[]) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype; q questions%rowtype; elapsed numeric; pts int; n_answers int; n_teams int;
        picks int[]; n_good int; good_ticked int; bad_ticked int; ratio numeric; exact boolean;
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
  if not q.multi then
    raise exception 'Cette question n''accepte qu''une réponse' using errcode = 'P0005';
  end if;
  select array_agg(distinct c order by c) into picks from unnest(p_choices) c
    where c >= 0 and c < jsonb_array_length(q.options);
  if picks is null or cardinality(picks) = 0 then
    raise exception 'Réponse inconnue' using errcode = 'P0005';
  end if;
  n_good := cardinality(q.corrects);
  select count(*) into good_ticked from unnest(picks) c where c = any (q.corrects);
  bad_ticked := cardinality(picks) - good_ticked;
  ratio := greatest(0, good_ticked - bad_ticked)::numeric / n_good;
  exact := (good_ticked = n_good and bad_ticked = 0);
  if exact then
    pts := 100 + round(50 * greatest(0, g.seconds - elapsed) / g.seconds);
  else
    pts := round(100 * ratio);
  end if;
  insert into answers (team_id, question_id, choice, choices, correct, points)
  values (p_team_id, p_question_id, null, picks, exact, pts);

  select count(*) into n_answers from answers where question_id = p_question_id;
  select count(*) into n_teams from teams;
  if n_answers >= n_teams then
    update game set status = 'suspense', updated_at = now() where id = 1;
  end if;
end $$;
grant execute on function public.submit_answers(uuid, uuid, int[]) to anon, authenticated;

-- Révélation : expose aussi les bonnes réponses multiples et les cases cochées par la table
drop function if exists public.reveal_question(uuid, uuid);
create or replace function public.reveal_question(p_question_id uuid, p_team_id uuid)
returns table (correct int, anecdote text, media_url text, media_type text, my_choice int, my_correct boolean, my_points int,
               multi boolean, corrects int[], my_choices int[])
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype;
begin
  select * into g from game where id = 1;
  if g.status in ('question', 'suspense') and g.current_question_id = p_question_id then
    raise exception 'La question est encore ouverte' using errcode = 'P0003';
  end if;
  return query
    select q.correct, q.anecdote, q.media_url, q.media_type, a.choice, a.correct, a.points, q.multi, q.corrects, a.choices
    from questions q
    left join answers a on a.question_id = q.id and a.team_id = p_team_id
    where q.id = p_question_id;
end $$;
grant execute on function public.reveal_question(uuid, uuid) to anon, authenticated;
