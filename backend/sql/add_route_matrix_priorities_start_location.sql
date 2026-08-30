-- Run once in Supabase SQL Editor before deploying this milestone.

alter table public.user_saved_places
  add column if not exists priority integer not null default 0,
  add column if not exists is_locked boolean not null default false,
  add column if not exists must_visit boolean not null default false;

alter table public.trips
  add column if not exists start_location_type text,
  add column if not exists start_location_name text,
  add column if not exists start_latitude double precision,
  add column if not exists start_longitude double precision;

create table if not exists public.route_matrix_cache (
  id uuid primary key,
  trip_id uuid not null references public.trips(id) on delete cascade,
  from_place_id uuid references public.places(id) on delete cascade,
  to_place_id uuid references public.places(id) on delete cascade,
  from_location_type text not null,
  from_name text,
  from_latitude double precision,
  from_longitude double precision,
  to_location_type text not null,
  to_name text,
  to_latitude double precision,
  to_longitude double precision,
  from_key text not null,
  to_key text not null,
  distance_meters integer not null check (distance_meters >= 0),
  static_duration_seconds integer not null check (static_duration_seconds >= 0),
  traffic_duration_seconds integer check (
    traffic_duration_seconds is null or traffic_duration_seconds >= 0
  ),
  travel_mode text not null default 'driving',
  calculated_at timestamptz not null,
  expires_at timestamptz,
  constraint ck_route_matrix_from_location check (
    from_place_id is not null or
    (from_latitude is not null and from_longitude is not null)
  ),
  constraint ck_route_matrix_to_location check (
    to_place_id is not null or
    (to_latitude is not null and to_longitude is not null)
  )
);

create unique index if not exists uq_route_matrix_cache_trip_pair_mode
  on public.route_matrix_cache (trip_id, from_key, to_key, travel_mode);

create index if not exists ix_route_matrix_cache_trip_id
  on public.route_matrix_cache (trip_id);

create index if not exists ix_route_matrix_cache_expires_at
  on public.route_matrix_cache (expires_at);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_user_saved_places_priority'
  ) then
    alter table public.user_saved_places
      add constraint ck_user_saved_places_priority check (priority >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_trips_start_location_type'
  ) then
    alter table public.trips
      add constraint ck_trips_start_location_type check (
        start_location_type is null or start_location_type in
        ('arrival', 'hotel', 'current_location', 'custom')
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_trips_start_latitude'
  ) then
    alter table public.trips
      add constraint ck_trips_start_latitude check (
        start_latitude is null or start_latitude between -90 and 90
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_trips_start_longitude'
  ) then
    alter table public.trips
      add constraint ck_trips_start_longitude check (
        start_longitude is null or start_longitude between -180 and 180
      );
  end if;
end $$;
