alter table public.presentation_rooms
  add column if not exists about_reveal integer not null default 0
  check (about_reveal between 0 and 3);
