-- Suspense et médias.
-- 1) Une question se ferme automatiquement quand toutes les tables ont répondu : état « suspense ».
-- 2) Pendant le suspense, l'animateur peut donner la parole aux mariés (ask_couple).
-- 3) Une photo ou une vidéo peut accompagner la révélation.

alter table public.questions
  add column media_url  text check (media_url is null or char_length(media_url) <= 2000),
  add column media_type text check (media_type is null or media_type in ('image', 'video', 'youtube'));

alter table public.game drop constraint game_status_check;
alter table public.game add constraint game_status_check
  check (status in ('lobby', 'question', 'suspense', 'reveal', 'board', 'finished'));
alter table public.game add column ask_couple boolean not null default false;

-- Répartition des votes par réponse (sans dire laquelle est la bonne)
create view public.choice_counts as
  select question_id, choice, count(*)::int as n from public.answers group by question_id, choice;
grant select on public.choice_counts to anon, authenticated;

-- Sauvegarde d'une question avec média (nouvelle signature)
drop function if exists public.admin_save_question(text, uuid, int, text, text, jsonb, int, text);
create or replace function public.admin_save_question(
  p_pin text, p_id uuid, p_position int, p_course text, p_text text, p_options jsonb, p_correct int, p_anecdote text,
  p_media_url text default null, p_media_type text default null
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  perform assert_pin(p_pin);
  if p_id is null then
    insert into questions (position, course, text, options, correct, anecdote, media_url, media_type)
    values (p_position, p_course, p_text, p_options, p_correct, coalesce(p_anecdote, ''), nullif(p_media_url, ''), nullif(p_media_type, ''))
    returning id into v_id;
  else
    update questions set position = p_position, course = p_course, text = p_text, options = p_options,
      correct = p_correct, anecdote = coalesce(p_anecdote, ''), media_url = nullif(p_media_url, ''), media_type = nullif(p_media_type, '')
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end $$;
grant execute on function public.admin_save_question(text, uuid, int, text, text, jsonb, int, text, text, text) to anon, authenticated;

-- Changement d'état : remet aussi la parole aux mariés à zéro
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
    ask_couple = false,
    updated_at = now()
  where id = 1;
end $$;

create or replace function public.admin_ask_couple(p_pin text, p_ask boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  update game set ask_couple = p_ask, updated_at = now() where id = 1;
end $$;
grant execute on function public.admin_ask_couple(text, boolean) to anon, authenticated;

-- Réponse d'une table : ferme la question quand toutes les tables ont répondu
create or replace function public.submit_answer(p_team_id uuid, p_question_id uuid, p_choice int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype; q questions%rowtype; elapsed numeric; pts int; n_answers int; n_teams int;
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
  if q.correct = p_choice then
    pts := 100 + round(50 * greatest(0, g.seconds - elapsed) / g.seconds);
  else
    pts := 0;
  end if;
  insert into answers (team_id, question_id, choice, correct, points)
  values (p_team_id, p_question_id, p_choice, q.correct = p_choice, pts);

  select count(*) into n_answers from answers where question_id = p_question_id;
  select count(*) into n_teams from teams;
  if n_answers >= n_teams then
    update game set status = 'suspense', updated_at = now() where id = 1;
  end if;
end $$;

-- Révélation : rien tant que la question est ouverte ou en suspense
drop function if exists public.reveal_question(uuid, uuid);
create or replace function public.reveal_question(p_question_id uuid, p_team_id uuid)
returns table (correct int, anecdote text, media_url text, media_type text, my_choice int, my_correct boolean, my_points int)
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype;
begin
  select * into g from game where id = 1;
  if g.status in ('question', 'suspense') and g.current_question_id = p_question_id then
    raise exception 'La question est encore ouverte' using errcode = 'P0003';
  end if;
  return query
    select q.correct, q.anecdote, q.media_url, q.media_type, a.choice, a.correct, a.points
    from questions q
    left join answers a on a.question_id = q.id and a.team_id = p_team_id
    where q.id = p_question_id;
end $$;
grant execute on function public.reveal_question(uuid, uuid) to anon, authenticated;

-- Stockage des photos et vidéos : bucket public « media », dépôt ouvert (lien connu des seuls invités), 50 Mo max
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 52428800, array['image/*', 'video/*'])
on conflict (id) do nothing;
create policy "médias du quiz lisibles" on storage.objects for select to anon, authenticated using (bucket_id = 'media');
create policy "dépôt de médias du quiz" on storage.objects for insert to anon, authenticated with check (bucket_id = 'media');
