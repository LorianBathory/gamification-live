drop function if exists public.claim_presentation_example(text, uuid, integer);

create or replace function public.claim_presentation_example(
  p_room_id text,
  p_participant_id uuid,
  p_cooldown_seconds integer default 60,
  p_max_examples integer default 42
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
  v_max_examples integer := greatest(1, p_max_examples);
  v_claimed_at timestamptz;
  v_last_click timestamptz;
  v_count integer;
begin
  select room.example_count
    into v_count
    from public.presentation_rooms as room
    where room.id = p_room_id
    for update;

  if v_count is null then
    raise exception 'Room not found';
  end if;

  if v_count >= v_max_examples then
    return query select false, v_count, null::timestamptz;
    return;
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

    return query select false, v_count, v_last_click + v_interval;
    return;
  end if;

  update public.presentation_rooms as room
    set example_count = least(room.example_count + 1, v_max_examples),
        updated_at = v_now
    where room.id = p_room_id
    returning room.example_count into v_count;

  return query select true, v_count, v_now + v_interval;
end;
$$;

revoke all on function public.claim_presentation_example(text, uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.claim_presentation_example(text, uuid, integer, integer) to service_role;
