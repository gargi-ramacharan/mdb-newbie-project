-- Re:live: trip owners, covers, and managing who is on a trip.
--
-- Run after 0001_init.sql (SQL Editor, or `supabase db push`).
-- For Sign in with Apple, also turn on Authentication > Providers > Apple and
-- Authentication > Settings > "Allow manual linking" (lets an anonymous account keep its
-- trips when it signs in with Apple).

-- ---------------------------------------------------------------- columns

-- Who runs the trip. Starts as whoever created it; can be handed to another member.
alter table public.trips add column owner_id uuid references public.profiles (id);
update public.trips set owner_id = created_by where owner_id is null;
alter table public.trips alter column owner_id set default auth.uid();
alter table public.trips alter column owner_id set not null;

-- The album photo picked as the cover, or an uploaded cover in the photo bucket.
-- Neither set means the app picks one.
alter table public.trips add column cover_photo_id uuid;
alter table public.trips add column cover_path text;

-- ---------------------------------------------------------------- helpers

create function public.is_trip_owner(p_trip uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from public.trips where id = p_trip and owner_id = auth.uid());
$$;

-- ---------------------------------------------------------------- owner actions
-- All writes to trips and memberships go through these functions, which check who is asking.

-- Changes a trip's details and cover. Owner only.
create function public.update_trip(
    p_id uuid, p_name text, p_start timestamptz, p_end timestamptz, p_places jsonb,
    p_cover_photo_id uuid, p_cover_path text
) returns void
language plpgsql security definer set search_path = public as $$
begin
    if not public.is_trip_owner(p_id) then
        raise exception 'only the trip owner can change it';
    end if;
    update public.trips
       set name = p_name, start_date = p_start, end_date = p_end,
           places = coalesce(p_places, '[]'::jsonb),
           cover_photo_id = p_cover_photo_id, cover_path = p_cover_path
     where id = p_id;
end;
$$;

-- Takes someone off a trip, with the photos they added. Owner only; the owner can't be removed.
-- Their photo files stay in the bucket; nobody can read them once the rows are gone.
create function public.remove_member(p_trip uuid, p_user uuid) returns void
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
end;
$$;

-- Hands the trip to another member. Owner only.
create function public.transfer_trip(p_trip uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
    if not public.is_trip_owner(p_trip) then
        raise exception 'only the trip owner can hand it on';
    end if;
    if not exists (select 1 from public.trip_members where trip_id = p_trip and user_id = p_user) then
        raise exception 'that person isn''t on this trip';
    end if;
    update public.trips set owner_id = p_user where id = p_trip;
end;
$$;

-- Leaves a trip, taking your photos with you. The owner has to hand it on or delete it first.
create function public.leave_trip(p_trip uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
    if public.is_trip_owner(p_trip) then
        raise exception 'the owner can''t leave; hand the trip on or delete it';
    end if;
    delete from public.photos where trip_id = p_trip and owner_id = auth.uid();
    delete from public.trip_members where trip_id = p_trip and user_id = auth.uid();
end;
$$;

-- Deletes a trip for everyone. Owner only. Members and photo rows go with it (on delete cascade).
create function public.delete_trip(p_trip uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
    if not public.is_trip_owner(p_trip) then
        raise exception 'only the trip owner can delete it';
    end if;
    delete from public.trips where id = p_trip;
end;
$$;

revoke execute on function public.update_trip(uuid, text, timestamptz, timestamptz, jsonb, uuid, text) from public, anon;
revoke execute on function public.remove_member(uuid, uuid) from public, anon;
revoke execute on function public.transfer_trip(uuid, uuid) from public, anon;
revoke execute on function public.leave_trip(uuid) from public, anon;
revoke execute on function public.delete_trip(uuid) from public, anon;
grant  execute on function public.update_trip(uuid, text, timestamptz, timestamptz, jsonb, uuid, text) to authenticated;
grant  execute on function public.remove_member(uuid, uuid) to authenticated;
grant  execute on function public.transfer_trip(uuid, uuid) to authenticated;
grant  execute on function public.leave_trip(uuid) to authenticated;
grant  execute on function public.delete_trip(uuid) to authenticated;

-- Leaving now goes through leave_trip, which stops the owner walking away from their trip.
drop policy "trip_members: leave" on public.trip_members;

-- ---------------------------------------------------------------- photo storage

-- Lets you delete files under your own folder of a trip, for photos you take out of the album
-- and covers you replace. (Covers live at <trip id>/<owner id>/cover-<uuid>.jpg.)
create policy "trip-photos: delete own" on storage.objects
    for delete to authenticated
    using (bucket_id = 'trip-photos'
           and (storage.foldername(name))[2] = auth.uid()::text);
