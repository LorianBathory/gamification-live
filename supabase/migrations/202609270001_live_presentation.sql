create table if not exists public.presentation_rooms (
  id text primary key,
  current_slide integer not null default 0 check (current_slide between 0 and 10),
  horizontal_index integer not null default 0 check (horizontal_index between 0 and 3),
  reward_reveal integer not null default 0 check (reward_reveal between 0 and 3),
  achievement_gallery_index integer not null default 0 check (achievement_gallery_index between 0 and 3),
  quest_gallery_index integer not null default 0 check (quest_gallery_index between 0 and 2),
  example_count integer not null default 0 check (example_count >= 0),
  reset_version bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.presentation_participants (
  room_id text not null references public.presentation_rooms(id) on delete cascade,
  participant_id uuid not null,
  last_click_at timestamptz not null,
  primary key (room_id, participant_id)
);

alter table public.presentation_rooms enable row level security;
alter table public.presentation_participants enable row level security;

revoke all on table public.presentation_rooms from anon, authenticated;
revoke all on table public.presentation_participants from anon, authenticated;
grant select on table public.presentation_rooms to anon, authenticated;

drop policy if exists "Public rooms are readable" on public.presentation_rooms;
create policy "Public rooms are readable"
on public.presentation_rooms
for select
to anon, authenticated
using (true);

insert into public.presentation_rooms (id)
values ('gamification-live')
on conflict (id) do nothing;

create or replace function public.claim_presentation_example(
  p_room_id text,
  p_participant_id uuid,
  p_cooldown_seconds integer default 60
)
returns table (
  accepted boolean,
  example_count integer,
  next_allowed_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_interval interval := make_interval(secs => greatest(1, p_cooldown_seconds));
  v_claimed_at timestamptz;
  v_last_click timestamptz;
  v_count integer;
begin
  if not exists (select 1 from public.presentation_rooms where id = p_room_id) then
    raise exception 'Room not found';
  end if;

  insert into public.presentation_participants (room_id, participant_id, last_click_at)
  values (p_room_id, p_participant_id, v_now)
  on conflict (room_id, participant_id) do update
    set last_click_at = excluded.last_click_at
    where public.presentation_participants.last_click_at <= v_now - v_interval
  returning last_click_at into v_claimed_at;

  if v_claimed_at is null then
    select last_click_at
      into v_last_click
      from public.presentation_participants
      where room_id = p_room_id and participant_id = p_participant_id;

    select r.example_count
      into v_count
      from public.presentation_rooms r
      where r.id = p_room_id;

    return query select false, v_count, v_last_click + v_interval;
    return;
  end if;

  update public.presentation_rooms
    set example_count = example_count + 1,
        updated_at = v_now
    where id = p_room_id
    returning presentation_rooms.example_count into v_count;

  return query select true, v_count, v_now + v_interval;
end;
$$;

revoke all on function public.claim_presentation_example(text, uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_presentation_example(text, uuid, integer) to service_role;

grant select, insert, update, delete on table public.presentation_rooms to service_role;
grant select, insert, update, delete on table public.presentation_participants to service_role;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'presentation_rooms'
  ) then
    alter publication supabase_realtime add table public.presentation_rooms;
  end if;
end $$;
