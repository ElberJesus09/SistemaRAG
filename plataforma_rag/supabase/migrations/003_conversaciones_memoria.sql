-- Conversaciones con limite de mensajes y memoria corta por chat.
-- Ejecutar desde Supabase > SQL Editor si ya aplicaste las migraciones anteriores.

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

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'questions_conversation_id_fkey'
  ) then
    alter table public.questions
      add constraint questions_conversation_id_fkey
      foreign key (conversation_id)
      references public.conversations(id)
      on delete set null;
  end if;
end;
$$;

create index if not exists conversations_user_idx
  on public.conversations(user_id, updated_at desc);

create index if not exists questions_conversation_idx
  on public.questions(conversation_id, created_at desc);

drop trigger if exists conversations_updated_at on public.conversations;
create trigger conversations_updated_at before update on public.conversations
for each row execute function public.set_updated_at();

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

alter table public.conversations enable row level security;

create policy "conversaciones propias" on public.conversations
for select to authenticated using ((select auth.uid()) = user_id or public.is_admin());

grant all privileges on public.conversations to service_role;
grant select on public.conversations to authenticated;

revoke all on function public.increment_conversation_message_count(uuid)
  from public, anon, authenticated;
grant execute on function public.increment_conversation_message_count(uuid)
  to service_role;

notify pgrst, 'reload schema';
