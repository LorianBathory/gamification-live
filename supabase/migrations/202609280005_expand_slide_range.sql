alter table public.presentation_rooms
  drop constraint if exists presentation_rooms_current_slide_check;

alter table public.presentation_rooms
  add constraint presentation_rooms_current_slide_check
  check (current_slide between 0 and 13);
