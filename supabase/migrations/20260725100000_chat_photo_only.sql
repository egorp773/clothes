-- Chat media is intentionally limited to photographs for new messages.
-- Existing video rows remain readable for history compatibility.

create or replace function public.reject_new_chat_video()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.type = 'video' then
    raise exception 'chat_video_messages_disabled' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.reject_new_chat_video() from public, anon, authenticated;

drop trigger if exists reject_new_chat_video_before_insert
  on public.chat_messages;
create trigger reject_new_chat_video_before_insert
before insert on public.chat_messages
for each row
execute function public.reject_new_chat_video();

update storage.buckets
set file_size_limit = 20971520,
    allowed_mime_types = array[
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif'
]::text[]
where id = 'chat-media';

notify pgrst, 'reload schema';
