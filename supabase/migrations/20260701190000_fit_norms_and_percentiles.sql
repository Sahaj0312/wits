-- Population norms for the onboarding fit test. No FK to auth.users so the
-- table can hold seeded population rows; real users are folded in by the RPC.
create table if not exists public.fit_norms (
  id bigint generated always as identity primary key,
  game text not null,
  age smallint not null,
  accuracy real not null check (accuracy >= 0 and accuracy <= 1),
  user_id uuid,
  is_seed boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists fit_norms_game_age_idx
  on public.fit_norms (game, age, accuracy);
create index if not exists fit_norms_user_idx
  on public.fit_norms (user_id) where user_id is not null;

alter table public.fit_norms enable row level security;
-- No client policies on purpose: reads/writes happen only through the
-- security-definer RPC below.

-- Age-banded percentile per fit-test game. p_scores: {"arrowStorm": 0.91, ...}
-- Returns {"arrowStorm": 62, ...} where the value is the share of the age-band
-- population scoring strictly below the caller. Also records the caller's
-- accuracies into fit_norms (replacing their previous fit-test rows).
create or replace function public.fit_percentiles(p_age int, p_scores jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  entry record;
  uid uuid := auth.uid();
  result jsonb := '{}'::jsonb;
  below int;
  total int;
  pct int;
  band int := 6;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  for entry in
    select key as game, value::real as acc from jsonb_each_text(p_scores)
  loop
    select count(*)::int,
           (count(*) filter (where fn.accuracy < entry.acc))::int
      into total, below
      from fit_norms fn
     where fn.game = entry.game
       and fn.age between p_age - band and p_age + band
       and (fn.user_id is null or fn.user_id <> uid);

    if total >= 20 then
      pct := least(99, greatest(1, round(100.0 * below / total)::int));
    else
      -- thin norms: fall back to the accuracy-derived figure the app used pre-norms
      pct := least(99, greatest(4, round(entry.acc * 100)::int));
    end if;

    delete from fit_norms where user_id = uid and game = entry.game;
    insert into fit_norms (game, age, accuracy, user_id, is_seed)
    values (entry.game, greatest(13, least(100, p_age)), entry.acc, uid, false);

    result := result || jsonb_build_object(entry.game, pct);
  end loop;

  return result;
end;
$$;

revoke all on function public.fit_percentiles(int, jsonb) from public;
grant execute on function public.fit_percentiles(int, jsonb) to authenticated;

-- Seed (applied once in production, kept here for reference / fresh envs):
-- 60 samples per age per game, ages 13-85. Accuracy peaks in the mid-20s,
-- declines with age, approx-normal noise.
-- insert into fit_norms (game, age, accuracy, is_seed)
-- select g.game, a.age,
--        greatest(0.15, least(1.0,
--          g.base
--          - g.slope * greatest(0, a.age - 27) / 58.0
--          - 0.05 * greatest(0, 20 - a.age) / 7.0
--          + (random() + random() + random() - 1.5) * g.sd * 1.7
--        ))::real, true
-- from (values
--   ('arrowStorm',   0.92, 0.11, 0.055),
--   ('crowdControl', 0.84, 0.22, 0.085),
--   ('echoGrid',     0.79, 0.24, 0.105)
-- ) as g(game, base, slope, sd)
-- cross join generate_series(13, 85) as a(age)
-- cross join generate_series(1, 60) as s(i);
