-- Remise à zéro : Supabase exige une clause WHERE sur les DELETE issus de l'API.
create or replace function public.admin_reset(p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform assert_pin(p_pin);
  delete from answers where true;
  delete from teams where true;
  update game set status = 'lobby', current_question_id = null, question_started_at = null, updated_at = now() where id = 1;
end $$;

-- Les privilèges par défaut de Supabase donnent accès aux nouvelles tables : on les retire explicitement
-- sur tout ce qui ne doit passer que par les vues et les fonctions.
revoke all on table public.questions, public.answers, public.settings from anon, authenticated;
