# Wits Scoring System Critique

## Executive read

The current scoring system is cleanly separated in intent, but weak in measurement.
The app has three different concepts that are all called or displayed as scores:

- **Raw points** inside a run, mostly for game feel and reward.
- **Mastery level** per game, a 1...10 adaptive difficulty state.
- **WPI/domain score**, currently `mastery level * 500`.

That separation is directionally right. The problem is that WPI is not really a
performance score. It is an exposed difficulty counter moved by a coarse,
one-size-fits-all accuracy ladder. Because every game defines accuracy
differently, the same WPI change means different things across games. The result
will feel arbitrary to users and will be hard to defend analytically.

## What the code currently does

Primary files:

- `wits/GameKit.swift`
  - `DifficultyState.level` is the official scoring signal.
  - WPI contribution is documented as `level * 500`.
  - `MasteryLadder.delta(for:)` maps accuracy bands to level changes.
- `wits/AppModel.swift`
  - `recordGameResult` advances difficulty from `result.accuracy`.
  - `domainScore(level:)` turns the current level into WPI.
  - `domainScores(from:)` collapses played games into domain scores.
- `wits/ProgressMath.swift`
  - EWMA-smooths domain/headline WPI over active days.
  - Builds workout priorities from weakness plus staleness.
- `wits/GameHost.swift`
  - Applies surprise score multipliers before persistence.
- `wits/OnboardingFlow.swift`
  - Seeds early domain scores from three fit-test games.

Current mastery ladder:

```text
accuracy >= 0.85       -> +0.5 level
0.70 <= accuracy < .85 -> +0.2 level
0.55 <= accuracy < .70 -> -0.1 level
accuracy < 0.55        -> -0.3 level
```

Visible WPI:

```text
WPI = clamp(level, 1...10) * 500
```

So a single run can move WPI by:

- `+250` for a strong run.
- `+100` for a decent run.
- `-50` for a weak-ish run.
- `-150` for a bad run.

That makes WPI easy to explain, but it also makes it extremely coarse.

## The good parts

The system has some good instincts:

- Raw points and WPI are intentionally separate. The help sheet explains this in
  `AppShell.swift`, which is good product hygiene.
- The app stores per-run sessions, difficulty, daily progress, and per-game
  stats separately. That gives enough data to redesign scoring without losing
  history.
- Progress smoothing exists, so users do not see every noisy run as a jagged
  headline change.
- The daily workout can use weak-domain targeting instead of a blind rotation.

Those are worth keeping. The critique is about the measurement layer underneath
them.

## Critical issues

### 1. WPI is difficulty, not performance

`AppModel.wpiScore(level:)` maps level directly to WPI. A user's actual score,
reaction time, threshold, number of trials, completion time, and game-specific
stat are not part of WPI except indirectly through the broad `accuracy` bucket
that changes the next level.

This means two users can both be level 4 and show about 2000 WPI even if one is
barely holding level 4 and another is crushing it but has not yet accumulated
enough sessions to climb. It also means the system mostly measures persistence
through the ladder, not current performance quality.

The code even says this directly in `GameKit.swift`: `DifficultyState.level` is
the official scoring signal. That is simple, but too thin.

### 2. The same accuracy ladder is applied to non-equivalent games

Every game emits `GameResult.accuracy`, but the meaning varies a lot:

- `ColorClash`, `NumberRush`, and many simple timed games use right / total.
- `MatchBack` counts correct rejections, so passive "do nothing" decisions can
  inflate accuracy.
- `SpotSpeed` requires both center and peripheral answers to be right, over only
  14 trials.
- `DotsConnect` uses board completion minus mistake and hint penalties.
- `TowerOfHanoi` uses a composite of move efficiency, time efficiency, and
  invalid move penalty.
- `WordConnect` uses correct guesses / attempts, where hints count as wrong
  attempts and bonus words count as correct attempts.

Feeding all of those into the same thresholds (`0.85`, `0.70`, `0.55`) is not
calibrated. An 85% in `MatchBack` does not mean the same thing as an 85% in
`TowerOfHanoi` or `DotsConnect`.

This is the core reason the scoring probably feels "not good": the app is using
one universal rubric over metrics that are not comparable.

### 3. The ladder has cliff effects

The difference between 84.9% and 85.0% is a 150 WPI swing in the next score
movement (`+100` vs `+250`). The difference between 69.9% and 70.0% is also a
meaningful swing (`-50` vs `+100`).

That is especially bad for games with few trials. `SpotSpeed` has 14 trials, so:

- 12/14 = 85.7%, level +0.5.
- 11/14 = 78.6%, level +0.2.

One trial changes the result by 150 WPI. That is too much noise for a long-term
score.

### 4. Level values are not calibrated across games

The app treats level 4 as 2000 WPI for every game. But each game interprets level
in completely different units:

- `ColorClash`: response window and incongruent-trial probability.
- `NumberRush`: operand range, operator mix, and time window.
- `MatchBack`: n-back depth and interval.
- `SpotSpeed`: presentation milliseconds.
- `DotsConnect`: floored puzzle difficulty.
- `TowerOfHanoi`: disk count/campaign mechanics.

There is no evidence that level 4 in one game equals level 4 in another. Averaging
these levels into a domain score gives a clean number, but not a valid
cross-game scale.

### 5. Same-day domain aggregation overwrites prior games

In `AppModel.recordDayActivity`, the app loads existing `domain_scores`, computes
scores from the just-finished result, and assigns:

```swift
for (k, v) in domainScores(from: results) { domains[k] = v }
```

Since `recordWorkoutGame` calls `recordDayActivity([result], ...)` one game at a
time, a second game in the same domain overwrites the earlier domain score
instead of averaging or weighting both. This is a concrete bug, not just a model
preference.

Example: if a workout has two memory games, the later memory game's level decides
the day's memory score. The earlier memory game disappears from WPI rollup.

### 6. Some game-specific progression conflicts with persisted mastery

`WordConnect` has its own level-unlock logic:

```swift
let unlocksNextLevel = boardsSolved >= Self.boardsPerRun && accuracy >= 0.85
let nextLevel = unlocksNextLevel ? min(10, currentLevel + 1) : currentLevel
```

The UI can then say the next level was unlocked. But persistence still goes
through the generic `MasteryLadder.adjust`, so a level 1 run with high accuracy
persists as level 1.5, not level 2. `WordConnect` floors the saved difficulty to
get `currentLevel`, so the next run can still start at level 1 even after the UI
said level 2 was unlocked.

That is a serious trust issue.

`TowerOfHanoi` also has campaign progress stored separately from WPI mastery.
That can be okay, but it means the user's visible campaign achievement and WPI
are not the same progression system.

### 7. Raw points are not comparable and sometimes random

Raw points vary by game formula:

- Some games use `100 * combo multiplier`.
- `RuleFinder` includes speed and tier.
- `TowerOfHanoi` includes disk count, move efficiency, and time efficiency.
- `DotsConnect` awards board points plus clear bonus.
- Arcade games use base resolution points times combo multiplier.

That is acceptable if points are purely arcade feedback. But `GameHost` applies
surprise multipliers before persistence, and `AppModel` stores the multiplied
score as `bestScore`. A lucky x2 or x3 run can become a permanent "best score"
even if the underlying performance was not a best.

This weakens the credibility of best-score stats.

### 8. Free play and challenge runs affect progress inconsistently

`recordGameResult` updates difficulty for workout, free-play, and challenge
sources. But only free play explicitly calls `recordDayActivity` outside workout.
Daily challenge calls `recordGameResult(result, source: "challenge")` and does
not fold into the daily progress rollup.

So challenges can change future difficulty/WPI inputs without appearing in the
day's progress in the same way free play does. That is hard to reason about.

The product should decide one policy:

- Only prescribed workouts affect WPI.
- Or all scored runs affect WPI.
- Or non-workout runs affect game mastery but not the daily headline.

Right now it is mixed.

### 9. The onboarding "percentile" and "brain age" language is not supported

`computeResult` builds a result from age, self-assessment, screen time, and three
fit-test accuracies using hand-tuned constants. The test percentiles are basically
clamped accuracy percentages, not population percentiles.

That may work as onboarding theater, but it should not be presented as normative
measurement. If the app says "you scored higher than X% of people," it needs a
real comparison distribution. Otherwise, call it a starting estimate or fit-test
score.

### 10. EWMA smoothing hides noise but does not solve validity

`ProgressMath` smooths daily headline/domain scores with an EWMA. That makes the
chart look calmer, but the underlying data is still the difficulty counter.

Additional concerns:

- EWMA is sample-based, not time-based. A three-day gap and a one-day gap are
  treated the same if both are adjacent records.
- Domain series only include days the domain was trained, so stale abilities do
  not decay in the visible score.
- Untrained domains are excluded from the headline, which can make early WPI look
  better or more complete than it is.

## Recommended redesign

### Principle 1: Separate four numbers clearly

Use these as separate concepts:

1. **Run points**: arcade reward only. Can have combos, speed bonuses, and
   surprise multipliers. Do not use for WPI or best-performance truth unless
   stored separately as "bonus points".
2. **Run performance**: normalized 0...1 quality for the specific game, using
   game-specific metrics.
3. **Game mastery**: latent skill estimate for that game, with confidence.
4. **Domain/WPI**: aggregate of calibrated game mastery values, not raw levels.

### Principle 2: Give each game a scorer

Add a scoring policy per game:

```swift
struct ScoredRun {
    var performance: Double       // 0...1 normalized quality
    var confidence: Double        // based on trials/time/completion
    var difficultySignal: Double  // game-specific challenge level
    var displayStats: [String: Double]
}

protocol GameScoringPolicy {
    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun
    func nextDifficulty(_ result: GameResult, prior: DifficultyState) -> DifficultyState
}
```

Do not let every game dump an arbitrary `accuracy` into a global ladder. Keep the
global interface, but make calibration game-owned.

### Principle 3: Replace threshold jumps with a continuous update

Instead of four buckets, use a continuous target-accuracy update:

```text
target = 0.80
error = performance - target
step = gameStepSize * confidence * error
nextLevel = priorLevel + step
```

Then cap the step, for example:

```text
max positive move per run: +0.35 level
max negative move per run: -0.25 level
```

This avoids 84.9% vs 85.0% cliffs and lets trial count matter.

### Principle 4: Store score components, not just final numbers

For each session, persist:

- `raw_points`
- `bonus_multiplier`
- `bonus_points`
- `performance`
- `confidence`
- `difficulty_before`
- `difficulty_after`
- `wpi_delta`
- game-specific metrics already in `details`

This makes future analysis possible and avoids mixing fun points with measurement.

### Principle 5: Aggregate daily/domain scores from sessions

Stop overwriting same-domain scores. A day/domain score should be computed from
all relevant sessions:

```text
domain_day_score =
  weighted average of post-run game mastery scores
  where weight = confidence * game_domain_weight
```

For a daily workout, decide whether to include:

- prescribed workout only,
- workout plus challenge,
- all scored sessions.

Then implement that policy consistently.

### Principle 6: Add confidence and coverage to WPI

A WPI headline should know how much evidence backs it.

Recommended display logic:

- Show WPI only after at least 3 distinct domains or N total scored runs.
- Show "baseline" or "calibrating" during early sessions.
- Keep untrained domains visible as untrained instead of silently excluding them.
- Optionally show a coverage indicator: "4/7 skills calibrated".

### Principle 7: Make onboarding honest

If there is no population data, avoid percentile claims. Use copy like:

- "fit test estimate"
- "starting profile"
- "strongest area today"
- "your baseline for future comparison"

If you want real percentiles, collect anonymized distributions per age band,
game, version, and difficulty regime, then compute percentile from those.

## Suggested implementation order

1. **Fix the same-day overwrite bug.**
   Track per-session or per-game contributions and aggregate domains from all
   relevant results instead of replacing the domain value.

2. **Stop persisting surprise-multiplied scores as best performance.**
   Store `baseScore` and `bonusMultiplier` separately. Use base score for bests;
   use multiplied score only for the fun workout summary.

3. **Resolve game-specific progression conflicts.**
   `WordConnect` should either persist its integer unlock level or stop claiming
   an integer unlock. The saved difficulty and UI must agree.

4. **Introduce `performance` and `confidence` fields.**
   Keep `accuracy` for backwards compatibility, but stop treating it as the whole
   scoring contract.

5. **Move mastery updates behind per-game scoring policies.**
   Start with the most different games: `SpotSpeed`, `MatchBack`,
   `WordConnect`, `DotsConnect`, and `TowerOfHanoi`.

6. **Recompute WPI from calibrated mastery plus confidence.**
   Keep the 0...5000 scale if desired, but make the value mean something more
   than "current difficulty times 500".

7. **Add tests.**
   At the time of this review there were no test targets visible in the repo.
   Scoring should have pure tests for:
   - ladder/update monotonicity,
   - threshold edge cases,
   - same-day aggregation,
   - source policy behavior,
   - WordConnect/Tower progression persistence,
   - WPI headline coverage rules.

## Bottom line

The current WPI system is explainable but not credible enough. It is mostly a
game difficulty meter dressed as a cognitive score. The highest-value change is
not tweaking constants; it is changing the contract so every game emits a
normalized performance signal with confidence, then using calibrated game/domain
aggregation for WPI.

Keep raw points for fun. Keep adaptive difficulty. But stop letting a coarse,
global accuracy ladder be the whole truth behind the user's long-term score.
