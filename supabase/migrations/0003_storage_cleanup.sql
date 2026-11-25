-- Re:live: delete photo files when someone leaves or is removed from a trip, or a trip is deleted.
--
-- Run after 0002_owners_covers_members.sql. Then deploy the `storage-cleanup` Edge Function and
-- turn on its schedule (see "Photo cleanup" in the README).
--
-- Leaving, removing and deleting take the photo rows away but used to leave the files behind,
-- unreadable but still taking up storage. Postgres can't delete storage files itself (that has to
-- go through the Storage API), so each of those actions now queues the folder to clean in the same
-- transaction, and the Edge Function deletes the files with the service key.

-- ---------------------------------------------------------------- queue

-- A folder in the trip-photos bucket whose files should go: "<trip>/<user>/" when someone leaves
-- or is removed, "<trip>/" when a trip is deleted. Only files uploaded before `queued_at` are
-- deleted, so photos from someone who rejoins straight away are safe.
create table public.storage_cleanup (
    id        bigint generated always as identity primary key,
    prefix    text not null check (prefix ~ '^[0-9a-f-]{36}/([0-9a-f-]{36}/)?$'),
    queued_at timestamptz not null default now()
);

-- Row-level security on with no policies: only the service role (the Edge Function) and the
-- security-definer functions below can touch it.
alter table public.storage_cleanup enable row level security;

-- ---------------------------------------------------------------- leave, remove, delete

-- Same as 0002, plus queueing that person's folder of the trip.
create or replace function public.remove_member(p_trip uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
    if not public.is_trip_owner(p_trip) then
        raise exception 'only the trip owner can remove members';
    end if;
    if p_user = auth.uid() then
        raise exception 'the owner can''t remove themselves; hand the trip on or delete it';
    end if;
    delete from public.photos where trip_id = p_trip and owner_id = p_user;
    delete from public.trip_members where trip_id = p_trip and user_id = p_user;
    insert into public.storage_cleanup (prefix) values (p_trip::text || '/' || p_user::text || '/');
end;
$$;

create or replace function public.leave_trip(p_trip uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
    if public.is_trip_owner(p_trip) then
        raise exception 'the owner can''t leave; hand the trip on or delete it';
    end if;
    delete from public.photos where trip_id = p_trip and owner_id = auth.uid();
    delete from public.trip_members where trip_id = p_trip and user_id = auth.uid();
    insert into public.storage_cleanup (prefix) values (p_trip::text || '/' || auth.uid()::text || '/');
end;
$$;

-- Everything under the trip goes: every member's photos and any uploaded cover.
create or replace function public.delete_trip(p_trip uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
    if not public.is_trip_owner(p_trip) then
        raise exception 'only the trip owner can delete it';
    end if;
    delete from public.trips where id = p_trip;
    insert into public.storage_cleanup (prefix) values (p_trip::text || '/');
end;
$$;

-- ---------------------------------------------------------------- for the Edge Function

-- Up to `p_limit` files to delete. A file qualifies when it's under a queued folder, was last
-- written before that folder was queued, and nothing points at it any more (no photo row and no
-- trip cover). The last check means a queued folder can never cost anyone a photo they still have.
create function public.storage_cleanup_files(p_limit int default 500)
returns table (name text)
language sql stable security definer set search_path = public, storage as $$
    select distinct o.name
      from public.storage_cleanup c
      join storage.objects o
        on o.bucket_id = 'trip-photos'
       and starts_with(o.name, c.prefix)
       and coalesce(o.updated_at, o.created_at) < c.queued_at
     where not exists (select 1 from public.photos p where p.storage_path = o.name)
       and not exists (select 1 from public.trips t where t.cover_path = o.name)
     limit p_limit;
$$;

-- Clears the queue entries whose folders have nothing left to delete.
create function public.storage_cleanup_finish() returns int
language plpgsql security definer set search_path = public, storage as $$
declare
    done int;
begin
    delete from public.storage_cleanup c
     where not exists (
        select 1 from storage.objects o
         where o.bucket_id = 'trip-photos'
           and starts_with(o.name, c.prefix)
           and coalesce(o.updated_at, o.created_at) < c.queued_at
           and not exists (select 1 from public.photos p where p.storage_path = o.name)
           and not exists (select 1 from public.trips t where t.cover_path = o.name)
     );
    get diagnostics done = row_count;
    return done;
end;
$$;

revoke execute on function public.storage_cleanup_files(int) from public, anon, authenticated;
revoke execute on function public.storage_cleanup_finish() from public, anon, authenticated;
grant  execute on function public.storage_cleanup_files(int) to service_role;
grant  execute on function public.storage_cleanup_finish() to service_role;

-- ---------------------------------------------------------------- files already left behind

-- Folders of people who left or were removed before this migration, and of deleted trips:
-- any folder in the bucket with no matching membership. Queued now so the first run clears them.
insert into public.storage_cleanup (prefix)
select distinct split_part(o.name, '/', 1) || '/' || split_part(o.name, '/', 2) || '/'
  from storage.objects o
 where o.bucket_id = 'trip-photos'
   and split_part(o.name, '/', 1) ~ '^[0-9a-f-]{36}$'
   and split_part(o.name, '/', 2) ~ '^[0-9a-f-]{36}$'
   and not exists (
       select 1 from public.trip_members m
        where m.trip_id::text = split_part(o.name, '/', 1)
          and m.user_id::text = split_part(o.name, '/', 2)
   );

-- ---------------------------------------------------------------- schedule

-- Runs the Edge Function every 10 minutes, so files go even if the app's own call after leaving
-- never arrives. Reads the project URL from Vault; add it once in the SQL Editor:
--     select vault.create_secret('https://<project ref>.supabase.co', 'project_url');
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
    'storage-cleanup',
    '*/10 * * * *',
    $$
    select net.http_post(
        url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
                   || '/functions/v1/storage-cleanup',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body    := '{}'::jsonb
    )
    where exists (select 1 from public.storage_cleanup);
    $$
);
