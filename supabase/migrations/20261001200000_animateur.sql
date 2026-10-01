-- Version 2 : partie pilotée par l'animateur.
-- Tout ce qui est sensible (bonne réponse, calcul des points, PIN) est géré côté serveur.
-- Les données de la v1 étaient des essais : on repart de zéro.

drop table if exists public.answers cascade;
drop table if exists public.teams cascade;

create extension if not exists pgcrypto with schema extensions;

-- ---------- Réglages privés (PIN animateur) : aucun accès anon ----------
create table public.settings (
  key   text primary key,
  value text not null
);
alter table public.settings enable row level security;
-- PIN initial : 2026 (à changer depuis l'espace animateur)
insert into public.settings (key, value) values ('pin_hash', extensions.crypt('2026', extensions.gen_salt('bf')));

-- ---------- Questions : la bonne réponse et l'anecdote ne sont jamais lisibles directement ----------
create table public.questions (
  id          uuid primary key default gen_random_uuid(),
  position    int  not null,
  course      text not null check (course in ('Entrée', 'Plat', 'Dessert')),
  text        text not null check (char_length(text) between 1 and 300),
  options     jsonb not null check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) = 4),
  correct     int  not null check (correct between 0 and 3),
  anecdote    text not null default '' check (char_length(anecdote) <= 500),
  created_at  timestamptz not null default now()
);
alter table public.questions enable row level security;

-- Vue publique sans la réponse (vue « definer » volontaire : elle n'expose que des colonnes sûres)
create view public.questions_public as
  select id, position, course, text, options from public.questions;
grant select on public.questions_public to anon, authenticated;

-- ---------- État de la partie : une seule ligne ----------
create table public.game (
  id                   int primary key default 1 check (id = 1),
  status               text not null default 'lobby' check (status in ('lobby', 'question', 'reveal', 'board', 'finished')),
  current_question_id  uuid references public.questions(id) on delete set null,
  question_started_at  timestamptz,
  seconds              int not null default 45 check (seconds between 10 and 180),
  updated_at           timestamptz not null default now()
);
insert into public.game (id) values (1);
alter table public.game enable row level security;
grant select on public.game to anon, authenticated;
create policy "état de la partie public" on public.game for select to anon, authenticated using (true);

-- ---------- Tables (équipes) ----------
create table public.teams (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 40),
  table_no    text check (table_no is null or char_length(table_no) <= 12),
  created_at  timestamptz not null default now()
);
alter table public.teams enable row level security;
grant select, insert on public.teams to anon, authenticated;
create policy "tables publiques"        on public.teams for select to anon, authenticated using (true);
create policy "inscription d'une table" on public.teams for insert to anon, authenticated with check (true);

-- ---------- Réponses : écrites uniquement via submit_answer, jamais lisibles directement ----------
create table public.answers (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references public.teams(id) on delete cascade,
  question_id  uuid not null references public.questions(id) on delete cascade,
  choice       int  not null check (choice between 0 and 3),
  correct      boolean not null,
  points       int  not null check (points between 0 and 150),
  created_at   timestamptz not null default now(),
  unique (team_id, question_id)
);
create index answers_team_id_idx on public.answers (team_id);
create index answers_question_id_idx on public.answers (question_id);
alter table public.answers enable row level security;

-- Classement et compteurs : vues « definer » qui n'exposent que des agrégats
create view public.leaderboard as
  select t.id, t.name, t.table_no, t.created_at,
         coalesce(sum(a.points), 0)::int as score,
         count(a.id)::int as answered
  from public.teams t left join public.answers a on a.team_id = t.id
  group by t.id;
grant select on public.leaderboard to anon, authenticated;

create view public.answer_counts as
  select question_id, count(*)::int as answered from public.answers group by question_id;
grant select on public.answer_counts to anon, authenticated;

-- ---------- Fonctions ----------
create or replace function public.server_time() returns timestamptz
language sql stable as $$ select now() $$;
grant execute on function public.server_time() to anon, authenticated;

create or replace function public.check_pin(p_pin text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select value into h from settings where key = 'pin_hash';
  perform pg_sleep(0.3);  -- freine les essais en rafale
  return h is not null and h = crypt(coalesce(p_pin, ''), h);
end $$;
grant execute on function public.check_pin(text) to anon, authenticated;

create or replace function public.assert_pin(p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select value into h from settings where key = 'pin_hash';
  if h is null or h <> crypt(coalesce(p_pin, ''), h) then
    raise exception 'Code PIN incorrect' using errcode = '28000';
  end if;
end $$;
revoke execute on function public.assert_pin(text) from public, anon, authenticated;

create or replace function public.admin_change_pin(p_pin text, p_new text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  if p_new !~ '^[0-9]{4,8}$' then raise exception 'Le nouveau code doit comporter 4 à 8 chiffres'; end if;
  update settings set value = crypt(p_new, gen_salt('bf')) where key = 'pin_hash';
end $$;
grant execute on function public.admin_change_pin(text, text) to anon, authenticated;

-- Lecture complète des questions (avec réponse) pour l'animateur
create or replace function public.admin_questions(p_pin text)
returns setof public.questions
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  return query select * from questions order by position;
end $$;
grant execute on function public.admin_questions(text) to anon, authenticated;

create or replace function public.admin_save_question(
  p_pin text, p_id uuid, p_position int, p_course text, p_text text, p_options jsonb, p_correct int, p_anecdote text
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  perform assert_pin(p_pin);
  if p_id is null then
    insert into questions (position, course, text, options, correct, anecdote)
    values (p_position, p_course, p_text, p_options, p_correct, coalesce(p_anecdote, ''))
    returning id into v_id;
  else
    update questions set position = p_position, course = p_course, text = p_text, options = p_options,
      correct = p_correct, anecdote = coalesce(p_anecdote, '') where id = p_id returning id into v_id;
  end if;
  return v_id;
end $$;
grant execute on function public.admin_save_question(text, uuid, int, text, text, jsonb, int, text) to anon, authenticated;

create or replace function public.admin_reorder_questions(p_pin text, p_ids uuid[]) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  update questions q set position = u.pos
  from unnest(p_ids) with ordinality as u(id, pos) where q.id = u.id;
end $$;
grant execute on function public.admin_reorder_questions(text, uuid[]) to anon, authenticated;

create or replace function public.admin_delete_question(p_pin text, p_id uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  delete from questions where id = p_id;
end $$;
grant execute on function public.admin_delete_question(text, uuid) to anon, authenticated;

create or replace function public.admin_delete_team(p_pin text, p_id uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  delete from teams where id = p_id;
end $$;
grant execute on function public.admin_delete_team(text, uuid) to anon, authenticated;

-- Changement d'état de la partie
create or replace function public.admin_set_game(p_pin text, p_status text, p_question_id uuid, p_seconds int) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  update game set
    status = p_status,
    current_question_id = p_question_id,
    seconds = coalesce(p_seconds, seconds),
    question_started_at = case when p_status = 'question' then now() else question_started_at end,
    updated_at = now()
  where id = 1;
end $$;
grant execute on function public.admin_set_game(text, text, uuid, int) to anon, authenticated;

-- Remise à zéro : efface les tables et les réponses, garde les questions
create or replace function public.admin_reset(p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  delete from answers; delete from teams;
  update game set status = 'lobby', current_question_id = null, question_started_at = null, updated_at = now() where id = 1;
end $$;
grant execute on function public.admin_reset(text) to anon, authenticated;

-- Réponse d'une table : correction et points calculés ici, à partir de l'heure de lancement
create or replace function public.submit_answer(p_team_id uuid, p_question_id uuid, p_choice int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype; q questions%rowtype; elapsed numeric; pts int;
begin
  select * into g from game where id = 1;
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
grant execute on function public.submit_answer(uuid, uuid, int) to anon, authenticated;

-- Révélation : bonne réponse, anecdote et résultat de la table, seulement une fois la question fermée
create or replace function public.reveal_question(p_question_id uuid, p_team_id uuid)
returns table (correct int, anecdote text, my_choice int, my_correct boolean, my_points int)
language plpgsql security definer set search_path = public, extensions as $$
declare g game%rowtype;
begin
  select * into g from game where id = 1;
  if g.status = 'question' and g.current_question_id = p_question_id then
    raise exception 'La question est encore ouverte' using errcode = 'P0003';
  end if;
  return query
    select q.correct, q.anecdote, a.choice, a.correct, a.points
    from questions q
    left join answers a on a.question_id = q.id and a.team_id = p_team_id
    where q.id = p_question_id;
end $$;
grant execute on function public.reveal_question(uuid, uuid) to anon, authenticated;

-- Temps réel : état de la partie et inscriptions
alter publication supabase_realtime add table public.game, public.teams;

-- ---------- Trame de questions (à personnaliser depuis l'espace animateur) ----------
insert into public.questions (position, course, text, options, correct, anecdote) values
 (1,'Entrée','Où Clare et Geoffrey se sont-ils rencontrés ?','["Dans un bar","Au travail","Sur une application","Par des amis communs"]',3,'À compléter : la scène de la rencontre en une phrase.'),
 (2,'Entrée','En quelle année ont-ils échangé leur premier baiser ?','["2015","2017","2019","2021"]',1,'À compléter : le lieu ou la circonstance.'),
 (3,'Entrée','Qui a fait le premier pas ?','["Clare","Geoffrey","Les deux en même temps","Personne ne s''en souvient"]',0,'À compléter : la version de Clare et celle de Geoffrey ne concordent pas forcément…'),
 (4,'Entrée','Quelle a été leur première destination de vacances en amoureux ?','["Lisbonne","La Corse","Rome","Les Alpes"]',2,'À compléter : une anecdote de ce premier voyage.'),
 (5,'Entrée','Quel surnom Geoffrey donne-t-il à Clare ?','["Ma puce","Chaton","Boss","Clarinette"]',3,'À compléter : l''origine du surnom.'),
 (6,'Plat','Qui cuisine le plus souvent à la maison ?','["Clare","Geoffrey","Le livreur","Belle-maman"]',1,'À compléter : le plat signature du chef.'),
 (7,'Plat','Qui est systématiquement en retard ?','["Clare","Geoffrey","Les deux","Aucun, ils sont parfaits"]',0,'À compléter : le record de retard à battre.'),
 (8,'Plat','Quel film ont-ils vu le plus de fois ensemble ?','["Love Actually","Le Seigneur des anneaux","Intouchables","Dirty Dancing"]',0,'À compléter : combien de fois, et qui s''endort avant la fin.'),
 (9,'Plat','Qui tient le volant sur les longs trajets ?','["Clare","Geoffrey","Ils alternent","Ils prennent le train"]',1,'À compléter : qui est le pire copilote.'),
 (10,'Plat','Combien de temps ont-ils vécu ensemble avant les fiançailles ?','["Moins d''un an","Deux ans","Trois ans","Plus de cinq ans"]',2,'À compléter : le premier appartement, le premier meuble monté ensemble…'),
 (11,'Dessert','Où Geoffrey a-t-il fait sa demande ?','["Sur une plage","Au sommet d''une montagne","Dans leur cuisine","Au restaurant"]',1,'À compléter : la bague était-elle cachée depuis longtemps ?'),
 (12,'Dessert','Qui a pleuré en premier le jour de la demande ?','["Clare","Geoffrey","La mère de Clare","Le chien"]',1,'À compléter : combien de mouchoirs.'),
 (13,'Dessert','Combien d''invités sont présents ce soir ?','["Environ 60","Environ 85","Environ 100","Environ 120"]',1,'À compléter : le nombre exact.'),
 (14,'Dessert','Sur quelle chanson vont-ils ouvrir le bal ?','["Perfect, Ed Sheeran","La Vie en rose","Can''t Help Falling in Love","Une surprise"]',3,'À compléter : vous le saurez dans quelques minutes.'),
 (15,'Dessert','Quel est leur grand projet pour l''année qui vient ?','["Un voyage au bout du monde","Un chien","Une maison","Un bébé"]',0,'À compléter : la destination ou le projet, si ce n''est pas secret.');
