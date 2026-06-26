-- Scoring v2 persistence columns.
-- Safe to re-run: every schema change is additive and idempotent.

alter table public.game_sessions
    add column if not exists base_score integer,
    add column if not exists bonus_multiplier integer default 1,
    add column if not exists display_score integer,
    add column if not exists performance_quality double precision,
    add column if not exists performance_confidence double precision,
    add column if not exists ability_signal double precision,
    add column if not exists challenge_level double precision,
    add column if not exists difficulty_before double precision,
    add column if not exists difficulty_after double precision,
    add column if not exists mastery_before double precision,
    add column if not exists mastery_after double precision,
    add column if not exists variance_after double precision,
    add column if not exists a_g double precision,
    add column if not exists wpi_delta double precision,
    add column if not exists scoring_version text;

alter table public.game_difficulty
    add column if not exists mastery double precision,
    add column if not exists confidence double precision,
    add column if not exists variance double precision,
    add column if not exists mu_g double precision,
    add column if not exists sigma_g double precision,
    add column if not exists last_played timestamptz,
    add column if not exists scoring_version text;

alter table public.daily_progress
    add column if not exists domain_confidence jsonb,
    add column if not exists domain_session_counts jsonb,
    add column if not exists headline_confidence double precision,
    add column if not exists coverage_count integer,
    add column if not exists migration_offset double precision,
    add column if not exists scoring_version text;

update public.game_difficulty
set mastery = coalesce(mastery, level),
    confidence = coalesce(confidence, least(1.0, coalesce(sessions_played, 0)::double precision / 8.0)),
    variance = coalesce(variance, greatest(0.05, 1.0 - least(1.0, coalesce(sessions_played, 0)::double precision / 8.0))),
    scoring_version = coalesce(scoring_version, 'v1_legacy')
where mastery is null
   or confidence is null
   or variance is null
   or scoring_version is null;

notify pgrst, 'reload schema';
