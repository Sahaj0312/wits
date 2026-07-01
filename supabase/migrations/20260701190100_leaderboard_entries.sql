-- Global per-game leaderboard: one row per (game, user) holding the best base
-- score (bonus multipliers excluded — luck must not rank). No FK to auth.users
-- so seeded bot entries can exist. Maintained by a trigger on game_sessions.
create table if not exists public.leaderboard_entries (
  game text not null,
  user_id uuid not null,
  best_score integer not null default 0,
  display_name text,
  is_bot boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (game, user_id)
);

-- Rank = index range scan on this, so the RPC stays fast at any user count.
create index if not exists leaderboard_game_score_idx
  on public.leaderboard_entries (game, best_score desc);

alter table public.leaderboard_entries enable row level security;

drop policy if exists "leaderboard readable by signed-in users" on public.leaderboard_entries;
create policy "leaderboard readable by signed-in users"
  on public.leaderboard_entries for select to authenticated using (true);
-- No insert/update policies: rows are written only by the trigger below.

create or replace function public.sync_leaderboard_entry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s integer := coalesce(new.base_score, new.score, 0);
  name text;
begin
  if s <= 0 or new.user_id is null then
    return new;
  end if;
  select display_name into name from profiles where id = new.user_id;
  insert into leaderboard_entries (game, user_id, best_score, display_name, is_bot, updated_at)
  values (new.game, new.user_id, s, name, false, now())
  on conflict (game, user_id) do update
    set best_score = greatest(leaderboard_entries.best_score, excluded.best_score),
        display_name = coalesce(excluded.display_name, leaderboard_entries.display_name),
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists game_sessions_leaderboard on public.game_sessions;
create trigger game_sessions_leaderboard
after insert on public.game_sessions
for each row execute function public.sync_leaderboard_entry();

-- One-round-trip leaderboard snapshot: top N + caller's rank + total players.
create or replace function public.game_leaderboard(p_game text, p_top int default 5)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  my_score int;
  my_rank int;
  total int;
  top jsonb;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select best_score into my_score
    from leaderboard_entries where game = p_game and user_id = uid;

  select count(*)::int into total
    from leaderboard_entries where game = p_game;

  if my_score is not null then
    select (1 + count(*))::int into my_rank
      from leaderboard_entries
     where game = p_game and best_score > my_score;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
             'name', coalesce(t.display_name, 'player'),
             'score', t.best_score,
             'me', t.user_id = uid)
           order by t.best_score desc), '[]'::jsonb)
    into top
    from (
      select display_name, best_score, user_id
        from leaderboard_entries
       where game = p_game
       order by best_score desc
       limit greatest(1, least(20, p_top))
    ) t;

  return jsonb_build_object('total', total, 'rank', my_rank, 'score', my_score, 'top', top);
end;
$$;

revoke all on function public.game_leaderboard(text, int) from public;
grant execute on function public.game_leaderboard(text, int) to authenticated;

-- Backfill from every session already recorded.
insert into leaderboard_entries (game, user_id, best_score, display_name, is_bot)
select gs.game, gs.user_id, max(coalesce(gs.base_score, gs.score, 0)), p.display_name, false
  from game_sessions gs
  left join profiles p on p.id = gs.user_id
 where coalesce(gs.base_score, gs.score, 0) > 0
 group by gs.game, gs.user_id, p.display_name
on conflict (game, user_id) do update
  set best_score = greatest(leaderboard_entries.best_score, excluded.best_score);
