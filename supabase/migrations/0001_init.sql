-- Re:live backend: profiles, trips, members, photos, the private photo bucket, and the
-- row-level security that keeps a trip's album visible only to its members.
--
-- Run it once in the Supabase dashboard (SQL Editor), or with `supabase db push`.
-- Before the app can sign in, enable Authentication > Providers > Anonymous sign-ins.

-- ---------------------------------------------------------------- tables

create table public.profiles (
    id         uuid primary key references auth.users (id) on delete cascade,
    name       text not null check (char_length(name) between 1 and 80),
    created_at timestamptz not null default now()
);

create table public.trips (
    id          uuid primary key,
    name        text not null check (char_length(name) between 1 and 120),
    -- Any moment on the first and last day, pinned to noon at the destination.
    start_date  timestamptz not null,
    end_date    timestamptz not null check (end_date >= start_date),
    -- [{ id, name, latitude, longitude, radiusKm, timeZoneID }] exactly as the app encodes `Place`.
    places      jsonb not null default '[]'::jsonb,
    invite_code text not null unique,
    created_by  uuid not null references auth.users (id) default auth.uid(),
    created_at  timestamptz not null default now()
);

create table public.trip_members (
    trip_id   uuid not null references public.trips (id) on delete cascade,
    user_id   uuid not null references public.profiles (id) on delete cascade,
    -- Which copy-paper colour this person gets on this trip.
    copy      int  not null default 0,
    joined_at timestamptz not null default now(),
    primary key (trip_id, user_id)
);

create table public.photos (
    id           uuid primary key,
    trip_id      uuid not null references public.trips (id) on delete cascade,
    owner_id     uuid not null references public.profiles (id) default auth.uid(),
    taken_at     timestamptz not null,
    latitude     double precision,
    longitude    double precision,
    -- Object path in the `trip-photos` bucket: <trip id>/<owner id>/<photo id>.jpg
    storage_path text not null,
    created_at   timestamptz not null default now()
);

create index photos_trip_idx on public.photos (trip_id, taken_at);
create index trip_members_user_idx on public.trip_members (user_id);

-- ---------------------------------------------------------------- helpers
-- security definer so the policies below don't recurse into themselves.

create function public.is_trip_member(p_trip uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.trip_members where trip_id = p_trip and user_id = auth.uid()
    );
$$;

create function public.shares_trip_with(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1
        from public.trip_members mine
        join public.trip_members theirs on theirs.trip_id = mine.trip_id
        where mine.user_id = auth.uid() and theirs.user_id = p_user
    );
$$;

-- ---------------------------------------------------------------- row-level security

alter table public.profiles     enable row level security;
alter table public.trips        enable row level security;
alter table public.trip_members enable row level security;
alter table public.photos       enable row level security;

-- You can see yourself and anyone you share a trip with.
create policy "profiles: read self and trip-mates" on public.profiles
    for select to authenticated using (id = auth.uid() or public.shares_trip_with(id));
create policy "profiles: create own" on public.profiles
    for insert to authenticated with check (id = auth.uid());
create policy "profiles: update own" on public.profiles
    for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Trips and memberships are written only through create_trip / join_trip below.
create policy "trips: members read" on public.trips
    for select to authenticated using (public.is_trip_member(id));
create policy "trip_members: members read" on public.trip_members
    for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_members: leave" on public.trip_members
    for delete to authenticated using (user_id = auth.uid());

create policy "photos: members read" on public.photos
    for select to authenticated using (public.is_trip_member(trip_id));
create policy "photos: add own" on public.photos
    for insert to authenticated
    with check (owner_id = auth.uid() and public.is_trip_member(trip_id));
-- Needed for the app's idempotent upsert when an upload is retried.
create policy "photos: update own" on public.photos
    for update to authenticated
    using (owner_id = auth.uid())
    with check (owner_id = auth.uid() and public.is_trip_member(trip_id));
create policy "photos: delete own" on public.photos
    for delete to authenticated using (owner_id = auth.uid());

-- ---------------------------------------------------------------- invite flow

-- Creates a trip with you as its first member and returns its invite code.
-- Safe to call again with the same id (a retry after a dropped connection).
create function public.create_trip(
    p_id uuid, p_name text, p_start timestamptz, p_end timestamptz, p_places jsonb
) returns text
language plpgsql security definer set search_path = public as $$
declare
    v_code text;
    v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
    if auth.uid() is null then
        raise exception 'not signed in';
    end if;

    select invite_code into v_code from public.trips where id = p_id and created_by = auth.uid();
    if found then
        return v_code;
    end if;

    loop
        select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
          into v_code from generate_series(1, 6);
        exit when not exists (select 1 from public.trips where invite_code = v_code);
    end loop;

    insert into public.trips (id, name, start_date, end_date, places, invite_code, created_by)
    values (p_id, p_name, p_start, p_end, coalesce(p_places, '[]'::jsonb), v_code, auth.uid());
    insert into public.trip_members (trip_id, user_id, copy) values (p_id, auth.uid(), 0);
    return v_code;
end;
$$;

-- Joins the trip that has this invite code. Returns its id, or null if there is none.
create function public.join_trip(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
    v_trip uuid;
begin
    if auth.uid() is null then
        raise exception 'not signed in';
    end if;
    select id into v_trip from public.trips where invite_code = upper(trim(p_code));
    if v_trip is null then
        return null;
    end if;
    insert into public.trip_members (trip_id, user_id, copy)
    values (v_trip, auth.uid(), (select count(*)::int % 5 from public.trip_members where trip_id = v_trip))
    on conflict do nothing;
    return v_trip;
end;
$$;

revoke execute on function public.create_trip(uuid, text, timestamptz, timestamptz, jsonb) from public, anon;
revoke execute on function public.join_trip(text) from public, anon;
grant  execute on function public.create_trip(uuid, text, timestamptz, timestamptz, jsonb) to authenticated;
grant  execute on function public.join_trip(text) to authenticated;

-- ---------------------------------------------------------------- photo storage

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('trip-photos', 'trip-photos', false, 10485760, array['image/jpeg'])
on conflict (id) do nothing;

-- Objects live at <trip id>/<owner id>/<photo id>.jpg. Members of the trip can read them;
-- you can only write under your own folder of a trip you belong to.
create policy "trip-photos: members read" on storage.objects
    for select to authenticated
    using (bucket_id = 'trip-photos'
           and public.is_trip_member(((storage.foldername(name))[1])::uuid));

create policy "trip-photos: write own" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'trip-photos'
                and (storage.foldername(name))[2] = auth.uid()::text
                and public.is_trip_member(((storage.foldername(name))[1])::uuid));

create policy "trip-photos: overwrite own" on storage.objects
    for update to authenticated
    using (bucket_id = 'trip-photos'
           and (storage.foldername(name))[2] = auth.uid()::text
           and public.is_trip_member(((storage.foldername(name))[1])::uuid));
