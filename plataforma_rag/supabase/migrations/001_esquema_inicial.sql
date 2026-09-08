-- Plataforma RAG: esquema inicial para Supabase/PostgreSQL.
-- Ejecutar completo desde Supabase > SQL Editor.

create extension if not exists vector with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'user' check (role in ('user', 'admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  source_document_id text not null unique,
  filename text not null,
  title text not null,
  status text not null default 'processing' check (status in ('processing', 'active', 'failed', 'archived')),
  chunk_count integer not null default 0 check (chunk_count >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chunks (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  chunk_id text not null unique,
  title text not null,
  content text not null,
  embedding_text text not null,
  page_start integer check (page_start is null or page_start > 0),
  page_end integer check (page_end is null or page_end > 0),
  estimated_tokens integer check (estimated_tokens is null or estimated_tokens > 0),
  quality_score integer check (quality_score is null or quality_score between 0 and 100),
  metadata jsonb not null default '{}'::jsonb,
  embedding extensions.vector(768) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text,
  summary text,
  message_count integer not null default 0 check (message_count >= 0),
  max_messages integer not null default 20 check (max_messages between 1 and 100),
  status text not null default 'active' check (status in ('active', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  conversation_id uuid references public.conversations(id) on delete set null,
  question text not null,
  normalized_question text not null,
  answer text,
  status text not null check (status in ('answered', 'no_results', 'error')),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  retrieval_ms integer check (retrieval_ms is null or retrieval_ms >= 0),
  generation_ms integer check (generation_ms is null or generation_ms >= 0),
  top_similarity real,
  sources jsonb not null default '[]'::jsonb,
  input_tokens integer,
  output_tokens integer,
  generation_model text,
  error_code text,
  created_at timestamptz not null default now()
);

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating smallint not null check (rating between -1 and 1),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (question_id, user_id)
);

create table if not exists public.alerts (
  id uuid primary key default gen_random_uuid(),
  type text not null,
  severity text not null check (severity in ('info', 'warning', 'error', 'critical')),
  title text not null,
  message text not null,
  status text not null default 'open' check (status in ('open', 'acknowledged', 'resolved')),
  question_id uuid references public.questions(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.ingestion_jobs (
  id uuid primary key default gen_random_uuid(),
  filename text not null,
  status text not null check (status in ('processing', 'completed', 'failed')),
  chunks_total integer not null default 0,
  chunks_processed integer not null default 0,
  error_message text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

create index if not exists chunks_document_id_idx on public.chunks(document_id);
create index if not exists chunks_embedding_hnsw_idx
  on public.chunks using hnsw (embedding vector_cosine_ops);
create index if not exists questions_created_at_idx on public.questions(created_at desc);
create index if not exists questions_normalized_idx on public.questions(normalized_question);
create index if not exists questions_user_idx on public.questions(user_id, created_at desc);
create index if not exists questions_conversation_idx on public.questions(conversation_id, created_at desc);
create index if not exists conversations_user_idx on public.conversations(user_id, updated_at desc);
create index if not exists alerts_status_idx on public.alerts(status, created_at desc);
create index if not exists audit_created_at_idx on public.audit_logs(created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
drop trigger if exists documents_updated_at on public.documents;
create trigger documents_updated_at before update on public.documents
for each row execute function public.set_updated_at();
drop trigger if exists chunks_updated_at on public.chunks;
create trigger chunks_updated_at before update on public.chunks
for each row execute function public.set_updated_at();
drop trigger if exists conversations_updated_at on public.conversations;
create trigger conversations_updated_at before update on public.conversations
for each row execute function public.set_updated_at();
drop trigger if exists feedback_updated_at on public.feedback;
create trigger feedback_updated_at before update on public.feedback
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), 'user')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and is_active = true
  );
$$;

create or replace function public.match_chunks(
  query_embedding extensions.vector(768),
  match_threshold real default 0.55,
  match_count integer default 6
)
returns table (
  chunk_id text,
  document_filename text,
  title text,
  content text,
  page_start integer,
  page_end integer,
  similarity real
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    c.chunk_id,
    d.filename as document_filename,
    c.title,
    c.content,
    c.page_start,
    c.page_end,
    (1 - (c.embedding <=> query_embedding))::real as similarity
  from public.chunks c
  join public.documents d on d.id = c.document_id
  where d.status = 'active'
    and (1 - (c.embedding <=> query_embedding)) >= match_threshold
  order by c.embedding <=> query_embedding
  limit least(greatest(match_count, 1), 20);
$$;

create or replace function public.increment_conversation_message_count(conversation_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
  set message_count = message_count + 1
  where id = conversation_uuid;
end;
$$;

alter table public.profiles enable row level security;
alter table public.documents enable row level security;
alter table public.chunks enable row level security;
alter table public.conversations enable row level security;
alter table public.questions enable row level security;
alter table public.feedback enable row level security;
alter table public.alerts enable row level security;
alter table public.ingestion_jobs enable row level security;
alter table public.audit_logs enable row level security;

create policy "perfil propio o administrador" on public.profiles
for select to authenticated using ((select auth.uid()) = id or public.is_admin());
create policy "documentos visibles para autenticados" on public.documents
for select to authenticated using (status = 'active' or public.is_admin());
create policy "chunks visibles para autenticados" on public.chunks
for select to authenticated using (public.is_admin());
create policy "conversaciones propias" on public.conversations
for select to authenticated using ((select auth.uid()) = user_id or public.is_admin());
create policy "preguntas propias" on public.questions
for select to authenticated using ((select auth.uid()) = user_id or public.is_admin());
create policy "feedback propio" on public.feedback
for all to authenticated using ((select auth.uid()) = user_id or public.is_admin())
with check ((select auth.uid()) = user_id or public.is_admin());
create policy "alertas para administradores" on public.alerts
for select to authenticated using (public.is_admin());
create policy "cargas para administradores" on public.ingestion_jobs
for select to authenticated using (public.is_admin());
create policy "auditoria para administradores" on public.audit_logs
for select to authenticated using (public.is_admin());

revoke all on function public.match_chunks(extensions.vector, real, integer) from public, anon, authenticated;
grant execute on function public.match_chunks(extensions.vector, real, integer) to service_role;
revoke all on function public.increment_conversation_message_count(uuid) from public, anon, authenticated;
grant execute on function public.increment_conversation_message_count(uuid) to service_role;

grant usage on schema public to anon, authenticated, service_role;
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant select on public.profiles, public.documents, public.conversations, public.questions,
  public.alerts, public.ingestion_jobs, public.audit_logs to authenticated;
grant select, insert, update on public.feedback to authenticated;

alter default privileges in schema public grant all privileges on tables to service_role;
alter default privileges in schema public grant all privileges on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

-- Tras registrar el primer usuario, conviertelo en administrador con:
-- update public.profiles set role = 'admin' where id = 'UUID_DEL_USUARIO';
