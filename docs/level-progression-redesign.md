# Level progression redesign: star maps, fixed exams, and age-normed percentiles

*Pinned 2026-07-02. Status: agreed design, pre-implementation.*

This doc consolidates a design conversation that moved through several pivots.
Recording the path matters because each rejected idea constrains the final one:

1. **Problem**: adaptive per-user difficulty made levels/scores illegible
   (e.g. Tower of Hanoi showing "level 4" on the card and "level 14/36"
   in-game), raw scores are uninterpretable ("is 3200 good?"), and score
   formulas confound skill with progression depth.
2. **Rejected: Tetris-style endless runs + per-game global leaderboards.**
   Standardized ramp-until-fail runs make scores comparable, but per-game
   leaderboards pull toward high-score-arcade identity, have content-bank
   integrity problems, and demand per-game anti-cheat.
3. **Kept from that phase**: comparison belongs at the *domain* level
   (the WPI radar), age-normed, as percentiles — not named rank lists.
4. **Final shape (this doc)**: per-game **star maps** — a paginated ladder of
   fixed, identical-for-everyone levels with 1–3 star grades and star-gated
   pages — plus an always-unlocked **marathon mode** per game, with all social comparison
   living on the activity page as age-group percentiles.

## 1. Core model

### Levels are fixed exams

A level is a bounded, self-contained challenge with a determinate end.
Level *n* of a game is **identical for every player and every attempt**:

- No in-level adaptation. The self-adjusting response windows in
  arrowStorm/colorClash/tileShift/numberRush/estimator are stripped inside
  levels (they belonged to the old adaptive-train mode).
- Retries are free and expected. Stars persist as max over attempts.
- Fixed exams are what make age-normed percentiles honest: everyone's
  ability is measured against the same ladder.

Three end-condition shapes cover all 20 games:

| Shape | Ends when | Used by |
|---|---|---|
| **Quota** | fixed trial count elapses | reflex/trial games |
| **Script** | fixed set of sequences/rounds completes | memory games |
| **Solve-or-bust** | puzzle solved, or fail-fast when a par-derived budget is blown | puzzle games |

**Fail-fast rule**: when passing is already arithmetically impossible
(too many misses, move budget blown), end the level immediately with a
retry affordance. Never make the player finish a doomed exam.

**Level length target**: 20–45s for quota/script games, one puzzle for
solve-or-bust. Short levels = cheap retries = the compulsion loop.

### Stars

One spine, all games: map the level result onto the existing scoring-policy
`performance` quality (0–1).

| Grade | Quality | Meaning |
|---|---|---|
| pass / 1★ | ≥ ~0.60 | level cleared, next level unlocks |
| 2★ | ≥ ~0.75 | good |
| 3★ | ≥ ~0.90 | excellent (tight par / near-perfect accuracy) |

Each game expresses these thresholds in its native vocabulary on the level
card ("3★: solve in 9 moves"), but the underlying rule is uniform.
Difficulty normalization is inherited from the policies' quality metrics.

### Map, pagination, gating

- Paginated map per game: **pages ("worlds") of 10 levels**.
- Within a page: passing level *n* unlocks *n+1*.
- At page boundaries: star-total gate (18★ from the previous page's 30).
  Gates are the only place stars can wall progress — gate gently; stars are
  mostly pull (completionism/replay), rarely wall. Nobody should be
  hard-stuck on a single level.
- Gates bar **first entry only**: a page that already holds a passed level,
  or that sits inside migration-seeded territory, is always open. (Found in
  implementation: seeded users hold 1★ per level, which can never satisfy an
  18★ gate — without this rule the migration would shove them backwards.)
- Ladder depth: set per game by how many *perceptibly distinct* difficulty
  steps exist between floor and ceiling — adjacent levels may differ subtly,
  but adjacent pages must feel obviously different. Level specs are
  evaluated from continuous difficulty curves (§3), so the internal ladder
  has arbitrary resolution; the map count is a UX choice, not a content
  ceiling. (The Elevate "44/400" pattern is a quantized difficulty meter,
  not 400 authored levels — we can render fine-grained positions later
  without new content, except for word games, see §5.)

**Level counts** (page-of-10 multiples; ~820 total, ~90% procedural):

| Levels | Games | Length driver |
|---|---|---|
| 50 (5 pages) | arrowStorm, colorClash, tileShift, oddOneOut, spotSpeed, numberRush, estimator | continuous knobs: windows ×0.96–0.97/level, flash duration, conflict share, ops tiers |
| 40 (4 pages) | matchBack, crowdControl, echoGrid, pathKeeper, lastSeen, towerOfHanoi, slidePuzzle, oneLine, dotsConnect, ruleFinder | coarse increments (spans, n-back bands, targets, par steps, board sizes, matrix tiers) padded with pacing |
| 30 (3 pages) | split | uncapped k-curve sliced into survive-T exams |
| 20 at launch (2 pages) | wordConnect, memoryLock | content-bound (§5); grow with the word pipeline |

### Marathon mode

Every game's map has a **marathon card pinned at the top, always unlocked**
(not gated behind map completion): the ramp-until-fail design from the
rejected phase, preserved as the casual/endless mode. Play as long as you
survive; difficulty **progresses along the same curves** past the map
ceiling — never randomized (random difficulty has no tension arc and makes
the result meaningless as a beatable number).

- **Start-level select** (the Tetris solution to early-game boredom):
  begin at any map level already passed; default a few below the frontier.
  Death point is ability-determined regardless of start, so best-depth
  stays comparable across players.
- Result is score + depth, not stars; personal best shown; near-miss /
  new-best framing per §4.
- Marathon doubles as the data engine: high trial volume accelerates norm
  seeding and ramp-calibration telemetry (§6), and extends measurement
  resolution above the map ceiling.

### Replacing per-user adaptive difficulty

The 1–10 adaptive `DifficultyState` no longer drives what a run serves.
Progression state per game = highest level unlocked + stars per level.
Adaptivity survives in exactly two places:

1. **Daily workout selection** (which games you play) still biases toward
   weak/neglected domains — unchanged.
2. **Within the workout**, the served level is chosen automatically:
   normally your frontier (lowest unpassed) level; occasionally a 1★
   level behind you for consolidation. The workout never shows a level
   picker ("trust me" mode); the library map is where you browse.

## 2. Per-game level definitions

Columns: what one level is, how it ends, pass (1★), 3★ criterion, and the
ramp knobs that define level *n*'s spec. Ramp constants are educated
guesses pending calibration (§6).

### Reflex / conflict (quota)

| Game | Level unit | Pass | 3★ | Ramp knobs by level |
|---|---|---|---|---|
| arrowStorm | 20 flanker trials | ≥16 correct | ≥19 + fast avg RT | window 1.4s shrinking ~×0.94 per map level; congruent share 65%→15% |
| colorClash | 20 Stroop trials | ≥16 | ≥19 + speed | window 1.6s ×0.93; incongruent 40%→90%; reverse-rule trials late |
| tileShift | 20 switch trials | ≥16 | ≥19 + speed | window 2.2s ×0.93; switch probability 0.30 + 0.05/level cap 0.85 |
| oddOneOut | 12 searches | ≥9 in window | 12/12 | grid 4×4→6×6; color delta ×0.94 (floor 0.10); window 4.2s ×0.92 |
| spotSpeed | 10 UFOV flashes | ≥7 both-right | ≥9 | flash 380ms ×0.88 (floor ~60ms); clutter +6/level; ring slots 8→14 |
| numberRush | 6 chains | ≥4 correct | 6/6 + margin | ops/chain 2 + level/2; reveal & answer windows ×0.95; ÷ unlocks mid-map |
| estimator | 6 targets | ≥4 exact/close | ≥5 exact | round window 13s ×0.94 (floor 4s); tiles 5→7; × then ÷ unlock; target range grows |
| matchBack | 20 n-back beats | ≥16 decisions | ≥19 | n = 1 → 2 → 3 across map; interval 1.8s→0.8s; lure rate →0.70 |

### Memory (script)

| Game | Level unit | Pass | 3★ | Ramp knobs |
|---|---|---|---|---|
| echoGrid | 3 backward sequences at fixed span | ≥2 perfect | 3/3 | span 2→8 across map; playback speed ×0.97/level; span steps padded with speed/grid between increments |
| pathKeeper | 3 forward paths | ≥2 perfect | 3/3 | length 3→9; grid 4×4→5×5 mid-map; playback speed ramps |
| lastSeen | clear one set of size k (fail-fast at 3 repeat-taps) | cleared | 0 errors + pace | set size 3→12; soft per-pick timer on later levels |
| crowdControl | 3 MOT rounds | ≥10 of 12 targets | 3 perfect rounds | targets 3→6 (of 9–10 dots); dot speed ×1.08/level. Note: currently ignores difficulty entirely (static 4-round ladder) — needs the retune regardless |

### Puzzle (solve-or-bust)

| Game | Level unit | Pass | 3★ | Ramp knobs |
|---|---|---|---|---|
| towerOfHanoi | 1 random-state puzzle; fail-fast at moves > par×1.4 or clock par×4s | solved in budget | ≤ par moves | par 3 + 2(n−1); disks 3 + n/4 cap 6. Generator/BFS from the 2026-07 random-state rewrite reused as-is; 36-level campaign + UserDefaults key retire |
| slidePuzzle | 1 board; fail-fast at par×1.6 | in budget | ≤ par×1.15 + time | 3×3 → 4×4 → 5×5; existing scramble-depth curves become intra-band ramp |
| oneLine | 1 Euler-trail graph; clock 10s + 2s/edge | solved (resets allowed, eat clock) | no resets/hints | existing node/edge specs as map spine; procedural generation extends past bank (easy — Euler graphs generate) |
| dotsConnect | 1 flow board; clock ≈30s + 6s/pair | solved | 0 crossings, no hints | existing grid/pair recipe ladder 5×5/4 → 7×7/8, then clock tightens |
| wordConnect | 1 board; board clock by tier | finished | no hints + time margin | tier 1→4 word length/grid; **content bottleneck, see §5** |
| memoryLock | 1 word; ends solved or guesses exhausted | solved | ≥3 guesses left | length 5→6→7; clue fade 1.45s ×0.95; guess budget 6→5→4; 7-letter pool needed |

### Survival

| Game | Level unit | Pass | 3★ | Ramp knobs |
|---|---|---|---|---|
| split | survive T seconds at fixed spec (T reached or death) | survived | survived + clean picks | existing k-curve becomes per-level spec; **uncap the ramp** for marathon mode (today saturates at level 13, turning elite runs into endurance) |

Every game additionally gets **marathon mode** (§1), whose result is
score/depth on the same curves extended past the map ceiling.

## 3. Level specs are curves, not content

For all non-word games, level *n*'s spec is a pure function of *n*
(window sizes, spans, pars, grid sizes, clutter counts). This is the same
code shape as today's `f(cfg.difficulty.level)` tuning — redirected to
`f(mapLevel)` and frozen per level. No per-level authoring except:

- **Pass/star threshold calibration** per game (one playtest pass).
- **Word games** (wordConnect, memoryLock): content is chosen, not computed
  — see §5.

## 4. Surfaces

Each surface answers exactly one comparison question:

| Surface | Question | Content |
|---|---|---|
| **Pregame / map** | me vs the ladder | paginated star map; tap tile → small card (level spec in native vocabulary, your stars, star criteria) → play. This *replaces* the old GameCard detail sheet. No "level progress %" block, no best-score tile, no mode tile |
| **Post-game** | me vs me | stage/level result + stars earned; score vs best only in marathon mode; near-miss framing ("2 stages short of your best") and new-best celebration (Celebration toolkit exists). **No percentiles here** — self-comparison only |
| **Activity page** | me vs the world | WPI radar where each domain shows an age-group **percentile with a distribution curve and your marker** — never named rank lists. Tap a spoke → per-domain view (distribution, trend) |

Decisions locked during the conversation:

- **Raw score is not a headline stat anywhere.** It's uninterpretable
  (per-game currencies) and confounded (scales with depth). It survives
  only inside endless-mode runs where beat-your-best is meaningful.
- **"Best score" / "best stat" / "plays" / "mode" tile grid is gone.**
- Percentiles are seeded from published cognitive-aging norms and blended
  with real user data as N grows (same trick as the existing `is_bot`
  leaderboard seeding; `fit_norms` + `fit_percentiles` RPC are prior art).

## 5. Content and integrity flags

- **wordConnect / memoryLock**: deep ladders require curated language
  content — an editorial pipeline (possibly LLM-generated candidates ranked
  by word frequency, filtered by `EnglishWordValidator`, human-reviewed),
  not a formula. Ship shorter maps for these two initially.
- **oneLine / dotsConnect**: finite authored banks today; oneLine is easily
  procedural, dots is medium effort.
- **Anti-cheat**: with named leaderboards dropped, pressure is low, but the
  `game_sessions` insert should still get a server-side sanity bound
  (plausible quality vs duration/trials) so norms aren't polluted.

## 6. Measurement (WPI) integration

- **Ability signal** per game = frontier level (highest passed), a graded
  staircase measure; endless-tile depth extends resolution at the ceiling.
  Policies map frontier level → 1–10 ability signal (per-game calibration
  table replacing today's assorted signals).
- **Performance quality** = the same policy quality metrics, now computed
  over a fixed exam (cleaner: no adaptive confound).
- `DifficultyState` stops steering runs; mastery/WPI bookkeeping continues,
  fed by the new signals. Domain rollup and workout selection unchanged.
- Ramp/threshold constants in §2 are paper-tuned. Instrument from day one:
  per-level pass/star rates, retry counts, death stages in endless. Expect
  one retune pass. Target: mid-map ≈ median adult frontier; last page
  reachable by top ~5%.

## 7. Backend changes

- New table `game_levels` (user_id, game, level, stars, best_quality,
  updated_at) — PK (user_id, game, level); local cache mirrors it.
- `game_sessions` gains `level` (map level or `endless`) — everything else
  in the upload path unchanged.
- `leaderboard_entries` + `game_leaderboard` RPC go dormant (or become the
  aggregation source for norms). No per-game boards shipped.
- Norms: per (game | domain, age_band) distribution tables for percentile
  lookup; seeded (§4), refreshed periodically server-side.

## 8. Migration notes

- Existing users: convert per-game adaptive level → starting frontier
  (unlock map levels up to the equivalent spec with 1★ so nobody replays
  trivial content; no stars gifted above 1★).
- Hanoi: campaign UserDefaults key and `hanoiLevel*` raw plumbing retire;
  `TowerPolicy` rewrites to frontier-level signal.
- Split: score semantics change from "level reached" to universal
  score/stars; standalone bypass (`GameID.split` returning EmptyView in
  Games.swift) gets folded into the normal host.
- Dead code to delete with the old model: every `cfg.isSurvival` branch
  (hardcoded false today; only Split ever shipped survival), legacy
  `MasteryLadder.advance` path.

## 9. Rollout

1. **Phase 1 — pilot, 3 games, one per end-condition shape**: colorClash
   (quota), echoGrid (script), towerOfHanoi (solve-or-bust). Build shared
   pieces once: level-spec plumbing, exam wrapper (quota/script/budget +
   fail-fast), star grader, map UI with pagination + gates, level card,
   post-game star screen, `game_levels` persistence.
2. **Phase 2 — sweep the remaining 17**: mostly redirecting existing
   `f(level)` tuning to `f(mapLevel)` + pass thresholds; retire GameCard
   detail sheet as maps land per game.
3. **Phase 3 — marathon mode + activity-page percentiles**: marathon on
   the shared ramp curves; norms tables + radar percentile UI; rewire WPI
   policies to frontier-level signals; delete dead adaptive/survival code.

## 10. Open questions

- Exact gate totals per page (needs the star-rate telemetry from Phase 1).
- Whether workout "consolidation" replays (serving a 1★ level) should be
  a fixed ratio or driven by domain staleness.
- Word-game content pipeline ownership (build vs license vs LLM-assisted).
- Whether to surface a fine-grained "difficulty position" number for
  marathon mode (Elevate-style meter) or keep it stage-based.
