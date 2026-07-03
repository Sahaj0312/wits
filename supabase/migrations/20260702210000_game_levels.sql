-- Star-map progression (docs/level-progression-redesign.md §7).
-- One row per (user, game, level): best stars + best quality ever earned.
-- Client upserts with merge-duplicates; the trigger keeps values monotone so
-- a stale device can never downgrade progress.

create table if not exists public.game_levels (
  user_id uuid not null references auth.users (id) on delete cascade,
  game text not null,
  level int not null check (level >= 1),
  stars int not null default 0 check (stars between 0 and 3),
  best_quality double precision not null default 0 check (best_quality >= 0 and best_quality <= 1),
  updated_at timestamptz not null default now(),
  primary key (user_id, game, level)
);

alter table public.game_levels enable row level security;

create policy "game_levels_select_own" on public.game_levels
  for select using (auth.uid() = user_id);
create policy "game_levels_insert_own" on public.game_levels
  for insert with check (auth.uid() = user_id);
create policy "game_levels_update_own" on public.game_levels
  for update using (auth.uid() = user_id);

-- Progress is monotone: merges never lower stars or quality.
create or replace function public.game_levels_keep_best()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  new.stars := greatest(new.stars, old.stars);
  new.best_quality := greatest(new.best_quality, old.best_quality);
  return new;
end;
$$;

drop trigger if exists game_levels_keep_best on public.game_levels;
create trigger game_levels_keep_best
  before update on public.game_levels
  for each row execute function public.game_levels_keep_best();

-- The map level a session served (null for legacy/marathonless runs).
alter table public.game_sessions add column if not exists map_level int;
