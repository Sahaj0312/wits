-- Population norms for the activity-page skill scores (WPI domains + overall).
-- Same shape as fit_norms: no FK to auth.users so the table can hold seeded
-- population rows; real users are folded in by the RPC on every refresh.
create table if not exists public.stat_norms (
  id bigint generated always as identity primary key,
  domain text not null,          -- 'overall' or a CognitiveDomain rawValue
  age smallint not null,
  score real not null check (score >= 0 and score <= 5000),
  user_id uuid,
  is_seed boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists stat_norms_domain_age_idx
  on public.stat_norms (domain, age, score);
create index if not exists stat_norms_user_idx
  on public.stat_norms (user_id) where user_id is not null;

alter table public.stat_norms enable row level security;
-- No client policies on purpose: reads/writes happen only through the
-- security-definer RPC below.

-- Whole-population percentile + distribution parameters per skill score.
-- p_scores: {"overall": 2870, "focus": 3100, ...} (0...5000 WPI values).
-- Returns {"overall": {"pct": 62, "mean": 2601.4, "sd": 548.2, "n": 23360}, ...}
-- where pct is the share of ALL users scoring strictly below the caller, and
-- mean/sd describe that population so the client can draw the distribution
-- curve. mean/sd are null when norms are too thin (n < 20). The caller's age
-- is still recorded (p_age) so age-banded norms stay possible later, but the
-- comparison itself is against every user of the app.
-- Also records the caller's scores into stat_norms (replacing their previous rows).
create or replace function public.stat_percentiles(p_age int, p_scores jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  entry record;
  uid uuid := auth.uid();
  result jsonb := '{}'::jsonb;
  total int;
  below int;
  avg_score double precision;
  sd_score double precision;
  pct int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  for entry in
    select key as domain, value::real as score from jsonb_each_text(p_scores)
  loop
    select count(*)::int,
           (count(*) filter (where sn.score < entry.score))::int,
           avg(sn.score)::double precision,
           stddev_samp(sn.score)::double precision
      into total, below, avg_score, sd_score
      from stat_norms sn
     where sn.domain = entry.domain
       and (sn.user_id is null or sn.user_id <> uid);

    if total >= 20 then
      pct := least(99, greatest(1, round(100.0 * below / total)::int));
    else
      -- thin norms: score-proportional estimate, no curve parameters
      pct := least(99, greatest(1, round(100.0 * entry.score / 5000.0)::int));
      avg_score := null;
      sd_score := null;
    end if;

    delete from stat_norms where user_id = uid and domain = entry.domain;
    insert into stat_norms (domain, age, score, user_id, is_seed)
    values (entry.domain,
            greatest(13, least(100, p_age)),
            least(5000, greatest(0, entry.score)),
            uid, false);

    result := result || jsonb_build_object(entry.domain, jsonb_build_object(
      'pct',  pct,
      'mean', case when avg_score is null then null else round(avg_score::numeric, 1) end,
      'sd',   case when sd_score  is null then null else round(sd_score::numeric, 1) end,
      'n',    total
    ));
  end loop;

  return result;
end;
$$;

revoke all on function public.stat_percentiles(int, jsonb) from public;
grant execute on function public.stat_percentiles(int, jsonb) to authenticated;

-- Seed (applied once in production, kept here for reference / fresh envs):
-- 40 samples per age per domain, ages 13-85. Scores peak in the mid-20s,
-- decline with age, approx-normal noise, clamped to a sane 200-4900 band.
-- insert into stat_norms (domain, age, score, is_seed)
-- select d.domain, a.age,
--        greatest(200, least(4900,
--          d.base
--          - d.slope * greatest(0, a.age - 27)
--          - 14 * greatest(0, 20 - a.age)
--          + (random() + random() + random() - 1.5) * d.sd * 2.0
--        ))::real, true
-- from (values
--   ('overall',      2600.0,  8.0, 550.0),
--   ('focus',        2700.0,  9.0, 600.0),
--   ('multitasking', 2400.0, 10.0, 650.0),
--   ('memory',       2550.0,  9.5, 620.0),
--   ('flexibility',  2500.0,  9.0, 580.0),
--   ('reasoning',    2650.0,  8.5, 640.0),
--   ('math',         2450.0,  8.0, 700.0),
--   ('language',     2750.0,  6.0, 560.0)
-- ) as d(domain, base, slope, sd)
-- cross join generate_series(13, 85) as a(age)
-- cross join generate_series(1, 40) as s(i);
