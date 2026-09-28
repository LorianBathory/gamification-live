alter table public.presentation_rooms
  add column if not exists thought_bubble_1_open boolean not null default false,
  add column if not exists thought_bubble_2_open boolean not null default false,
  add column if not exists thought_bubble_3_open boolean not null default false;
