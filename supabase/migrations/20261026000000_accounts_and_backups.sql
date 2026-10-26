-- Deutschap accounts: one backup snapshot per user (docs/adr/0005-accounts-and-sync.md).
-- Run in the Supabase SQL editor or with `supabase db push`.

create table if not exists public.backups (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  revision   bigint      not null default 1,
  schema     integer     not null,
  device     text,
  data       text        not null,  -- the app's own export JSON, stored as is
  updated_at timestamptz not null default now(),
  constraint backups_size check (octet_length(data) < 20 * 1024 * 1024)
);

alter table public.backups enable row level security;

-- Each user sees and changes only their own row. Writes go through
-- push_backup so the revision check cannot be skipped.
create policy "own backup: read" on public.backups
  for select using (auth.uid() = user_id);
create policy "own backup: delete" on public.backups
  for delete using (auth.uid() = user_id);

-- Stores a new snapshot if the caller still has the latest revision
-- (p_expected null = no snapshot yet). Returns the new revision, or null
-- when another device pushed in between; the app then syncs again.
create or replace function public.push_backup(p_data text, p_schema integer, p_device text, p_expected bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  new_rev bigint;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  if p_expected is null then
    insert into public.backups (user_id, revision, schema, device, data)
    values (uid, 1, p_schema, p_device, p_data)
    on conflict (user_id) do nothing
    returning revision into new_rev;
  else
    update public.backups
       set revision = revision + 1, schema = p_schema, device = p_device, data = p_data, updated_at = now()
     where user_id = uid and revision = p_expected
    returning revision into new_rev;
  end if;
  return new_rev;
end;
$$;

-- Deletes the caller's account; the backup goes with it (on delete cascade).
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.push_backup(text, integer, text, bigint) from public, anon;
grant execute on function public.push_backup(text, integer, text, bigint) to authenticated;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
