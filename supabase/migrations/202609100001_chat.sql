-- Apply with the Supabase CLI or SQL editor. No service-role key is used by the app.
create table public.conversations (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  title text not null check (char_length(title) between 1 and 40),
  model text not null,
  is_pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  next_sequence bigint not null default 0
);
create table public.chat_runs (
  id uuid primary key,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null unique,
  assistant_id uuid not null unique default gen_random_uuid(),
  prompt text not null,
  model text not null,
  status text not null default 'streaming' check (status in ('streaming','completed','stopped','error','interrupted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  lease_until timestamptz not null default now() + interval '120 seconds'
);
create table public.messages (
  id uuid primary key,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  turn_id uuid not null references public.chat_runs(id) on delete cascade,
  sequence bigint not null,
  role text not null check (role in ('user','assistant')),
  content text not null default '',
  reasoning text,
  model text not null,
  status text not null check (status in ('streaming','completed','stopped','error','interrupted')),
  error_code text,
  error_message text,
  thinking_seconds integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (conversation_id, sequence)
);
create index conversations_owner_order on public.conversations(user_id, is_pinned desc, updated_at desc, id) where deleted_at is null;
create index messages_room_order on public.messages(conversation_id, sequence desc);
create unique index one_running_turn_per_room on public.chat_runs(conversation_id) where status = 'streaming';

alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.chat_runs enable row level security;
create policy own_conversations on public.conversations for select to authenticated using (user_id = (select auth.uid()));
create policy create_conversation on public.conversations for insert to authenticated with check (user_id = (select auth.uid()) and deleted_at is null);
create policy edit_conversation on public.conversations for update to authenticated using (user_id = (select auth.uid()) and deleted_at is null) with check (user_id = (select auth.uid()) and deleted_at is null);
create policy own_messages on public.messages for select to authenticated using (
  user_id = (select auth.uid()) and exists (select 1 from public.conversations c where c.id = conversation_id and c.user_id = (select auth.uid()) and c.deleted_at is null)
);
create policy own_runs on public.chat_runs for select to authenticated using (
  user_id = (select auth.uid()) and exists (select 1 from public.conversations c where c.id = conversation_id and c.user_id = (select auth.uid()) and c.deleted_at is null)
);
revoke all on public.conversations, public.messages, public.chat_runs from anon, authenticated;
grant select on public.conversations, public.messages, public.chat_runs to authenticated;
grant insert (id, user_id, title, model) on public.conversations to authenticated;
grant update (title, model, is_pinned) on public.conversations to authenticated;

create function public.touch_conversation() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := clock_timestamp(); return new; end $$;
create trigger touch_conversation before update on public.conversations for each row execute function public.touch_conversation();

-- Mutations are atomic RPCs. SECURITY DEFINER is necessary because clients may
-- SELECT messages/runs, but may not forge sequence numbers, owners or leases.
-- Every RPC explicitly verifies auth.uid(); none accepts a caller-supplied owner.
create function public.recover_chat(p_conversation_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.conversations where id = p_conversation_id and user_id = auth.uid() and deleted_at is null for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  with expired as (
    update public.chat_runs set status = 'interrupted', updated_at = now()
    where conversation_id = p_conversation_id and status = 'streaming' and lease_until < now()
    returning assistant_id
  ) update public.messages set status = 'interrupted', error_code = 'INTERRUPTED',
    error_message = 'การตอบกลับถูกขัดจังหวะ', updated_at = now()
    where id in (select assistant_id from expired);
end $$;

create function public.begin_chat(p_conversation_id uuid, p_request_id uuid, p_message_id uuid, p_prompt text, p_model text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.chat_runs; n bigint;
begin
  if p_request_id is null or p_message_id is null or p_prompt is null or p_model is null or char_length(trim(p_prompt)) not between 1 and 32000 or char_length(trim(p_model)) not between 1 and 200 then raise exception 'INVALID_INPUT'; end if;
  perform public.recover_chat(p_conversation_id);
  select * into r from public.chat_runs where id = p_request_id;
  if found then
    if r.user_id <> auth.uid() or r.conversation_id <> p_conversation_id then raise exception 'ROOM_NOT_FOUND'; end if;
    if r.message_id <> p_message_id or r.prompt <> p_prompt or r.model <> p_model then raise exception 'REQUEST_CONFLICT'; end if;
    return jsonb_build_object('started', false, 'run', to_jsonb(r));
  end if;
  if exists(select 1 from public.chat_runs where conversation_id = p_conversation_id and status = 'streaming') then raise exception 'ROOM_BUSY'; end if;
  update public.conversations set next_sequence = next_sequence + 2, model = p_model where id = p_conversation_id returning next_sequence into n;
  insert into public.chat_runs(id, conversation_id, user_id, message_id, prompt, model)
    values(p_request_id, p_conversation_id, auth.uid(), p_message_id, p_prompt, p_model) returning * into r;
  insert into public.messages(id, conversation_id, user_id, turn_id, sequence, role, content, model, status)
    values (p_message_id, p_conversation_id, auth.uid(), r.id, n-1, 'user', p_prompt, p_model, 'completed'),
           (r.assistant_id, p_conversation_id, auth.uid(), r.id, n, 'assistant', '', p_model, 'streaming');
  return jsonb_build_object('started', true, 'run', to_jsonb(r));
end $$;

create function public.save_chat(p_request_id uuid, p_content text, p_reasoning text, p_status text,
  p_error_code text default null, p_error_message text default null, p_thinking_seconds integer default null)
returns text language plpgsql security definer set search_path = '' as $$
declare r public.chat_runs;
begin
  if p_content is null or p_status is null or p_status not in ('streaming','completed','stopped','error','interrupted') then raise exception 'INVALID_INPUT'; end if;
  -- Lock the room first in every RPC to prevent deadlocks with stop/recovery.
  perform 1 from public.conversations c join public.chat_runs t on t.conversation_id=c.id
    where t.id=p_request_id and c.user_id=auth.uid() and c.deleted_at is null for update of c;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  select * into r from public.chat_runs where id = p_request_id for update;
  if r.status <> 'streaming' then return r.status; end if;
  if r.lease_until < now() then
    perform public.recover_chat(r.conversation_id); return 'interrupted';
  end if;
  if p_status = 'completed' and trim(p_content) = '' then raise exception 'EMPTY_ANSWER'; end if;
  update public.messages set content = case when p_status='stopped' and char_length(content)>char_length(p_content) then content else p_content end,
    reasoning = case when p_status='stopped' and char_length(reasoning)>char_length(coalesce(p_reasoning,'')) then reasoning else nullif(p_reasoning,'') end, status = p_status,
    error_code = p_error_code, error_message = p_error_message, thinking_seconds = coalesce(p_thinking_seconds,thinking_seconds), updated_at = now()
    where id = r.assistant_id;
  update public.chat_runs set status = p_status, updated_at = now(), lease_until = now()+interval '120 seconds' where id = r.id;
  if p_status <> 'streaming' then update public.conversations set updated_at = now() where id = r.conversation_id; end if;
  return p_status;
end $$;

create function public.stop_chat(p_request_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare r public.chat_runs;
begin
  perform 1 from public.conversations c join public.chat_runs t on t.conversation_id=c.id
    where t.id=p_request_id and c.user_id=auth.uid() and c.deleted_at is null for update of c;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  select * into r from public.chat_runs where id=p_request_id for update;
  if r.status = 'streaming' then
    update public.chat_runs set status='stopped', updated_at=now() where id=r.id;
    update public.messages set status='stopped', updated_at=now() where id=r.assistant_id;
    update public.conversations set updated_at=now() where id=r.conversation_id;
  end if;
  return case when r.status='streaming' then 'stopped' else r.status end;
end $$;

create function public.delete_conversation(p_conversation_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.conversations where id=p_conversation_id and user_id=auth.uid() and deleted_at is null for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  update public.chat_runs set status='stopped', updated_at=now() where conversation_id=p_conversation_id and status='streaming';
  update public.messages set status='stopped', updated_at=now() where conversation_id=p_conversation_id and status='streaming';
  update public.conversations set deleted_at=now() where id=p_conversation_id;
end $$;

revoke all on function public.recover_chat(uuid), public.begin_chat(uuid,uuid,uuid,text,text), public.save_chat(uuid,text,text,text,text,text,integer), public.stop_chat(uuid), public.delete_conversation(uuid) from public, anon;
grant execute on function public.recover_chat(uuid), public.begin_chat(uuid,uuid,uuid,text,text), public.save_chat(uuid,text,text,text,text,text,integer), public.stop_chat(uuid), public.delete_conversation(uuid) to authenticated;
alter publication supabase_realtime add table public.conversations, public.messages;
