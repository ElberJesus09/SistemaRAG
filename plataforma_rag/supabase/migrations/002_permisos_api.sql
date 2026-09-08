-- Permisos necesarios para PostgREST y la API del servidor.
-- Ejecutar una vez desde Supabase > SQL Editor.

grant usage on schema public to anon, authenticated, service_role;

grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

grant select on public.profiles to authenticated;
grant select on public.documents to authenticated;
grant select on public.conversations to authenticated;
grant select on public.questions to authenticated;
grant select, insert, update on public.feedback to authenticated;
grant select on public.alerts to authenticated;
grant select on public.ingestion_jobs to authenticated;
grant select on public.audit_logs to authenticated;

alter default privileges in schema public
  grant all privileges on tables to service_role;
alter default privileges in schema public
  grant all privileges on sequences to service_role;
alter default privileges in schema public
  grant execute on functions to service_role;

-- La busqueda vectorial se mantiene disponible solo para el servidor.
revoke all on function public.match_chunks(extensions.vector, real, integer)
  from public, anon, authenticated;
grant execute on function public.match_chunks(extensions.vector, real, integer)
  to service_role;

revoke all on function public.increment_conversation_message_count(uuid)
  from public, anon, authenticated;
grant execute on function public.increment_conversation_message_count(uuid)
  to service_role;
