# Wits Scoring — Unified Solution

---

## 0. The one-line goal

WPI should mean *"calibrated estimate of your current skill, comparable across games,
robust to one bad day"* — not *"your difficulty knob × 500."* Keep the 0–5000 scale
and keep points fun. Replace the meaning behind the number.

The pipeline, end to end:

```
game-specific performance → confidence-weighted mastery → z-scored ability
                          → confidence-weighted domain → one headline
```

---

## 1. The four numbers (keep them separate)

| Number | Scope | Purpose | Feeds WPI? |
|--------|-------|---------|------------|
| **Run points** | one run | arcade reward — combos, streaks, surprise multipliers | ❌ never |
| **Performance** `P ∈ [0,1]` | one run | normalized quality of this run for this game | ✅ via mastery |
| **Mastery** `θ_g` (+ confidence) | per game | latent ability estimate | ✅ |
| **WPI / domain / headline** | aggregate | calibrated, confidence-weighted index | — |

Two hard rules the current system breaks: **run points never touch measurement**, and
**the headline is never a raw difficulty level.**

Store run points decomposed so a lucky multiplier can't become a permanent "best":

```
base_points          # used for best-score truth
bonus_multiplier     # surprise ×2/×3 etc.
display_points        # base × multiplier, for the celebration only
```

---

## 2. Layer 1 — Per-game performance

Each game emits a `ScoredRun`. The shape merges both docs:

```swift
struct ScoredRun: Codable, Equatable {
    var performance: Double      // 0...1, 0.5 ≈ "right at your level"
    var confidence: Double       // 0...1, evidence weight (trials / time / completion)
    var abilitySignal: Double    // game-native difficulty actually sustained (1...10)
    var metrics: [String: Double] = [:]   // for display + audit
}

protocol GameScoringPolicy {
    var targetQuality: Double { get }     // usually 0.78...0.82
    var stepSize: Double { get }
    var maxUp: Double { get }
    var maxDown: Double { get }
    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun
}
```

**[decision] Organize by archetype, but ship concrete per-game formulas inside each.**
The redesign's three archetypes are the right *mental model* (the speed–accuracy
tradeoff lives in a different place in each), but the proposal's per-game formulas are
what you actually type. So: archetype defines the *shape*; the per-game policy fills in
the coefficients. New games slot into an archetype and get a sane default for free.

### Archetype A — Staircase / threshold games
*SpotSpeed (flash ms), MatchBack (n-back depth), EchoGrid / span games.*
The in-session staircase converges on a **threshold** — that threshold *is* the
ability measure, and it's currently computed and thrown away. Accuracy here is only
sub-level resolution.

```
abilitySignal = converged threshold          // SpotSpeed: ms (lower better); span: items
P             = logistic((accuracy − a*) / s) // a* = staircase target ≈ 0.80
confidence    = min(1, trials / k_trials)
```

**SpotSpeed** maps threshold straight to ability — halving flash duration ≈ +1 level:
`θ ≈ θ_ref − log2(ms / ms_ref)`. It runs 18 trials, and its play curve now uses
an explicit 1...10 starting-duration table so early levels separate visibly.

### Archetype B — Timed-throughput games
*NumberRush, Estimator, ColorClash, ArrowStorm, TileShift, OddOneOut.* Fixed duration,
"answer as many as you can."

**[decision] Use Rate-Correct Score, not the proposal's hand-weighted `0.75·acc +
0.25·speed`.** RCS prices speed and accuracy together with *no magic weight*, and it
structurally kills the "slow down to farm accuracy" exploit (the critique's 🔴 #2):
slowing down lowers throughput, so `P` falls.

```
RCS = correct / timeOnTask_sec
P   = logistic(β · ln(RCS / RCS_ref(level)))     // β ≈ 1.0
confidence = min(1, timeOnTask_sec / T_ref)
```

The cost RCS carries — and you should accept it knowingly — is that it removes a knob:
you can no longer *dial* how much speed matters per game, and you need a `RCS_ref(level)`
curve per game. That's fine for a trainer whose whole premise is speed; if one specific
game ever needs speed de-emphasized, override that single policy back to a weighted
blend. *Instrumentation: these games run a fixed timer; add `timeOnTaskMs` to `raw`.*

### Archetype C — Self-paced efficiency / puzzle games
*TowerOfHanoi (%optimal), DotsConnect (completion − penalties), WordConnect, RuleFinder,
MemoryLock.* The game's own efficiency `e ∈ [0,1]` already encodes solution quality.

```
P = clamp(e + speedTerm, 0, 1)        // speedTerm only where solve-time is recorded
confidence = completionFraction        // partial solves count for less
```

Concrete fills (from the proposal, kept verbatim where solid):

- **TowerOfHanoi:** `e = 0.75·move_efficiency + 0.25·time_efficiency − invalid_penalty`,
  where `move_efficiency = min(1, optimal/moves)`, `time_efficiency = min(1, target_s/s)`,
  `invalid_penalty = min(0.35, invalid·0.10)`. `confidence = 1.0`.
- **DotsConnect:** `e = completion − min(0.25, mistakes·0.03) − min(0.25, hints·0.10)`;
  `confidence = boards>0 ? 0.75 + 0.25·completion : 0.35`.
- **WordConnect:** `e = clamp(0.65·completion + 0.35·(correct/attempts) − min(0.25,
  hints·0.08), 0, 1)`; `confidence = solved==perRun ? 1.0 : 0.55`. **WordConnect owns
  its integer unlock** — see §6.
- **RuleFinder:** `e = clamp(0.80·accuracy + 0.20·norm(speed), 0, 1)` where
  `speed = clamp(par_median / median_rt, 0.5, 1.25)`; `confidence = min(1, total/10)`.

### Anti-gaming overlay — signal detection for go/no-go games
*MatchBack, ColorClash, ArrowStorm, LastSeen.* Wherever a game has a "respond / withhold"
structure, the accuracy term **must not** be `(hits + correctRejections)/decisions` —
that lets never-responding farm correct rejections (critique 🔴 #3).

**[decision] Use true d′, not the proposal's `hitRate − falseAlarmRate` shortcut.** Both
collapse never-responding to ~0, so both *work*; d′ is the psychometrically standard
measure and is more defensible if anyone audits the math. The extra cost is one
inverse-normal and rate clamping — cheap.

```
d' = z(hitRate) − z(falseAlarmRate)      // rates clamped to [1/2N, 1 − 1/2N]
P_acc = logistic(d' / d'_ref)
```

For go/no-go games that are *also* timed-throughput (ColorClash, ArrowStorm), blend the
d′ accuracy term with the RCS rate term rather than using raw correct in RCS. Pure
arithmetic throughput (NumberRush) has no withhold option, so RCS alone is fine.
*Instrumentation: emit `hits, misses, falseAlarms, correctRejections`; until present,
fall back to stored `accuracy`.*

---

## 3. Layer 2 — Mastery update

`DifficultyState` carries both the play difficulty and the measurement estimate, and
they're allowed to diverge — `level` chases the right *challenge* for next session;
`mastery` is the *score*.

```swift
struct DifficultyState: Codable, Equatable {
    var level: Double            // play difficulty (controls next-session hardness)
    var mastery: Double          // 1...10 ability estimate
    var confidence: Double       // 0...1
    var variance: Double         // for the v2 filter; ignored by v1
    var sessionsPlayed: Int
    var reversals: Int
    var lastPlayed: Date?
}
```

### v1 — continuous update (ship this first)

Replaces the four-bucket cliff. No discontinuity at 85%; trial count matters via
`confidence`:

```
error      = run.performance − targetQuality        // target ≈ 0.80
raw_delta  = stepSize · run.confidence · error / 0.20
delta      = clamp(raw_delta, −maxDown, +maxUp)     // step 0.30, maxUp 0.35, maxDown 0.25
next.mastery = clamp(prior.mastery + delta, 1, 10)
```

Worked: `quality 0.95, conf 1.0 → +0.225`; `quality 0.65, conf 0.8 → −0.18`. Compare the
old `+0.5 / −0.1` jumps — smoother and more believable.

### v2 — Kalman filter (drop-in upgrade, same interface)

**[decision] Defer the Kalman filter; ship the scalar update first.** The redesign
itself offers the scalar update as the fallback and says the filter swaps in later
behind the same interface — so there's no reason to block v1 on it. Upgrade only if
real-world jitter becomes a complaint. When you do, it buys principled robustness: an
established skill barely moves on one odd run, a new game converges fast, and a *stale*
skill becomes *uncertain* (not frozen).

```
predict:  Pσ⁻ = variance + q · Δt_days              // long gap widens uncertainty
measure:  R_var = σ² · (k / (k + trials))            // short/lucky runs noisier
update:   K = Pσ⁻ / (Pσ⁻ + R_var)
          mastery ← mastery + K · (sessionAbility − mastery)
          variance ← (1 − K) · Pσ⁻
          confidence = 1 / (1 + variance)
```

The existing-but-unused `reversals` field is a ready-made stability signal to fold into
`R_var`. Keep `MasteryLadder` as the **difficulty controller** for next-session hardness
— it's just no longer the score.

---

## 4. Layer 3 — Cross-game calibration

**This is the proposal's biggest missing seam.** The proposal defines
`game_wpi = mastery × 500` for *every* game, then averages — so a "mastery 7" in
SpotSpeed and a "mastery 7" in WordConnect both become 3500 and get averaged, even
though they're different human ability levels. That's critique 🔴 #4, unsolved by the
proposal. Normalize each game to a shared distribution *before* aggregating:

```
z_g  = (mastery_g − μ_g) / σ_g
A_g  = clamp(2500 + 500·z_g, 0, 5000)     // 2500 = pop mean, 500 = 1 SD; keeps 0–5000
```

Now `A_g = 3000` means the same thing — half an SD above the mean *for that game* —
everywhere, so averaging is finally valid.

**Cold-start without a population dataset** — use a shared launch prior first, then
replace it with empirical-Bayes game norms once real data lands. Do **not** set the
launch prior from `seedLevel`; that creates different ceilings and compresses the
visible 0–5000 range.

```
launch: μ_g⁰ = 5.0, σ_g⁰ = 1.0        // mastery 5 = 2500; mastery 10 = 5000
future: μ_g⁰ = game-specific design prior, σ_g⁰ = observed spread
μ_g  = (n·μ̂_g + k·μ_g⁰) / (n + k)                  // k ≈ 50 pseudo-count
σ_g  = blend(σ̂_g, σ_g⁰, n, k)
```

**Be clear-eyed about what this buys at launch:** with priors instead of real norms,
z-scoring gives you *fairness* (consistent units, so averaging isn't nonsense) — **not
accuracy** (real percentiles). Ship internally-consistent defaults so cross-game
averaging is fair; do **not** advertise population percentiles or "brain age" until
`(μ_g, σ_g)` are backed by real N. The percentile machinery is the *same* machinery —
it just unlocks later (§9).

---

## 5. Layer 4 — Aggregation (one formula, everywhere)

### Game → Domain
Confidence- and recency-weighted mean over **all** games in the domain. This fixes both
the same-day overwrite bug *and* the unequal-game-count problem (memory's 4 games carry
more evidence than multitasking's 1, and are correctly weighted as such):

```
w_g = exp(−Δt_g / τ) · confidence_g          // recency × certainty, τ ≈ 21 days
D_d = Σ_{g∈d} w_g · A_g / Σ_{g∈d} w_g
C_d = Σ_{g∈d} w_g                            // domain confidence
```

### Domain → Headline
Equal domain weighting over measured domains (the "balanced brain" framing), each
measured domain **shrunk toward the population mean by its confidence**. Untrained
domains stay visible as "not trained yet" but do not mathematically pin the headline
to 2500; coverage/confidence labels carry that uncertainty.

```
D_d* = (C_d · D_d + k_d · 2500) / (C_d + k_d)
Headline = mean_{measured d} D_d*
```

**[decision] One headline definition, deleting the proposal's two-formula split.** The
live post-workout path updates the games just played, then calls *this exact function*;
the progress screen reads the same state. The current `AppModel.headline` vs
`ProgressMath.headline` divergence (critique 🟠 #6) is deleted, not smoothed over.

### Decay
**Never decay a user's ability `mastery_g`.** Decay only *certainty*: `variance` grows
with elapsed days, and `exp(−Δt/τ)` fades stale skills out of the headline, where they
show as "needs refresh" — not as a frozen high score (fixes critique 🟠 #7). This is
cleaner than the proposal's "keep last estimate + stale label," and it's a small change.

---

## 6. Source policy & per-game progression

**[decision] One consistent rule:** *all scored runs update game mastery; only
prescribed-workout + daily-challenge runs roll into the daily headline.* Free play tunes
difficulty over time but doesn't distort the day's prescribed-training score. The worst
option is the current mixed behavior — pick one and enforce it.

**WordConnect** must stop lying to the user (critique 🟠 / proposal #6): if the UI says
"level N+1 unlocked," persist N+1. `level` stays an integer for puzzle selection;
`mastery` still moves smoothly for WPI. Do not route WordConnect through the generic
half-level ladder for the *displayed unlock*.

**TowerOfHanoi** campaign progress can stay a separate progression, but WPI uses the
Archetype-C policy above.

---

## 7. Persistence & schema

### `game_sessions` — add
```
base_score            integer
bonus_multiplier      integer default 1
display_score         integer
performance_quality   double precision
performance_confidence double precision
ability_signal        double precision
challenge_level       double precision
difficulty_before     double precision
difficulty_after      double precision
mastery_before        double precision
mastery_after         double precision
variance_after        double precision
a_g                   double precision    -- calibrated game ability 0...5000
wpi_delta             double precision
scoring_version       text
```
Keep existing `score` during migration; eventually treat as `display_score` or deprecate.
**Store components, not just final numbers** — so scoring is auditable and re-computable.

### `game_difficulty` — add
```
mastery         double precision
confidence      double precision
variance        double precision
mu_g            double precision     -- or a shared norm cache keyed by (game, version)
sigma_g         double precision
last_played     timestamptz
scoring_version text
```
Backfill: `mastery = level`, `confidence = min(1, sessions_played/8)`,
`scoring_version = "v1_legacy"`.

### `daily_progress` — add / restructure
```
domain_scores         jsonb     -- final domain WPI (D_d*)
domain_confidence     jsonb
domain_session_counts jsonb
headline_confidence   double precision
coverage_count        integer
migration_offset      double precision    -- per-user anchor, §8
scoring_version       text
```

---

## 8. Migration — no visible jump

**[decision] Adopt the redesign's affine anchoring.** The proposal's phased plan
backfills "approximate" legacy values but never addresses the *discontinuity* at
cutover — users could see their number jump. The anchor closes that:

1. **Seed each game from current difficulty:** `mastery_g(0)` from stored `level`,
   `variance(0)` moderate, `last_played` = that game's last `started_at`.
2. **Replay history through the new estimator:** chronologically re-run `game_sessions`
   (`accuracy, difficulty, threshold, trials, score, details`) → calibrated `mastery_g`
   + a real per-game series. `d′` can't be recomputed for legacy rows → fall back to
   stored `accuracy`; d′ applies to new sessions only.
3. **Anchor the headline:** store a per-user affine `migration_offset` so at switch-over
   `Headline_new ≈ last shown headline`, decaying to 0 over ~14 days as v2 data accrues.
   **No score cliff.**
4. **Norms** ship as defaults (§4); recompute lazily as population N grows.

> ⚠️ The replay in step 2 is load-bearing for the no-jump promise. Confirm legacy
> `game_sessions` rows actually carry `threshold` / `trials` / `details` before
> committing to it — if history is too thin to replay, fall back to seed-only (step 1)
> and let v2 data accumulate forward, accepting a softer anchor.

---

## 9. Onboarding — honest *and* connected

Today's `computeResult` invents an "attention age" and "higher than X% of people" from
hand-tuned constants with no population behind them, and the number never reappears
in-app (critique 🟠 #12). Fix both halves:

- **Seed, don't fabricate:** run the fit-test games through the same Layer 1–3 pipeline
  and use them to seed each game's estimate. The onboarding result and the in-app WPI
  become the **same quantity** — they can no longer contradict, and the motivating
  number doesn't evaporate after signup. *(This is the part the proposal's copy-change
  alone doesn't fix.)*
- **Honest copy** until norms exist: "fit-test estimate," "your starting profile,"
  "strongest area today," "baseline for future comparison."
- **Earn percentiles later:** the same `(μ_g, σ_g)` machinery powers real percentiles
  once anonymized distributions per age band / game / version exist.

---

## 10. User-facing surface

- **Hero:** keep 0–5000, redefined as norm-referenced (2500 = mean, 500 = 1 SD) — an
  achievement, not a settings readout.
- **Coverage states** (gate early-WPI honesty):
  ```
  0–2 scored domains : "calibrating"
  3–4 scored domains : show WPI + "early estimate"
  5+ domains & 8+ runs: show normal WPI
  ```
- **Domain bars:** unplayed → "not trained yet"; low confidence → "calibrating";
  sufficient → score; stale → score + "needs refresh." Keep untrained domains *visible
  as untrained*, not silently excluded.
- **Confidence ribbon (optional):** ± band from `√(Σ W_d²·variance_d)`; never imply
  precision you don't have.

### Help-sheet copy (ship)
```
WPI is your Wits Performance Index. It estimates your current skill from recent
performance, measured against each game's own difficulty.

Points are the score for one round — they reward speed, streaks, and clean play.
WPI is separate and moves more slowly, based on how well you perform.

Each skill area has its own score out of 5000. Your overall WPI is built from the
areas you've trained enough to measure. New areas show as "calibrating" until
there's enough evidence.
```
Avoid, unless backed by real norm data: *"WPI is your IQ," "higher than X% of people,"
"your brain age is Y."*

---

## 11. Swift implementation shape

Add `wits/Scoring.swift`:

```swift
enum ScoringVersion { static let current = "v2_policy_calibrated" }

struct ScoredSession: Codable, Equatable {
    var result: GameResult
    var baseScore: Int
    var bonusMultiplier: Int
    var displayScore: Int
    var run: ScoredRun
    var previous: DifficultyState
    var next: DifficultyState
    var aG: Double          // calibrated 0...5000
}

enum ScoringPolicies {
    static func policy(for game: GameID) -> any GameScoringPolicy {
        switch game {
        case .spotSpeed:    SpotSpeedPolicy()      // archetype A
        case .matchBack:    MatchBackPolicy()      // A + d′
        case .numberRush, .estimator, .arrowStorm,
             .tileShift, .oddOneOut, .colorClash:  ThroughputPolicy(game)  // archetype B
        case .towerOfHanoi: TowerPolicy()          // archetype C
        case .dotsConnect:  DotsPolicy()           // C
        case .wordConnect:  WordConnectPolicy()    // C, owns integer unlock
        case .ruleFinder:   RuleFinderPolicy()     // C
        default:            AccuracyPolicy()       // safe fallback
        }
    }
}
```

App flow:
```
Game emits GameResult
GameHost applies optional display bonus      // AFTER base scoring is captured
AppModel builds ScoredSession via policy
AppModel persists session with all components
AppModel updates game mastery (+ variance in v2)
AppModel recomputes daily progress from counted sessions (Layer 4)
ProgressMath reads the same state — one headline
```

---

## 12. Tests

Pure, fast tests on the scoring core. The first implementation adds `witsTests`
with XCTest coverage for the scoring engine invariants:

- Continuous update has **no cliff at 85%**.
- Higher quality → higher-or-equal mastery delta (monotonicity).
- Lower confidence → smaller absolute delta.
- Mastery never leaves `[1, 10]`.
- d′ anti-gaming: never-responding → `P → 0`.
- RCS: slowing down (fewer correct/sec) → lower `P`.
- Same-day domain aggregation uses **all** counted sessions (no overwrite).
- Bonus multipliers don't change base score or best-performance.
- WordConnect persists the level its UI reports.
- Launch calibration uses the full 0–5000 scale and does not create seed-specific ceilings.
- Headline is not diluted by untrained domains; coverage is exposed separately.

Still worth adding as the UI and migration paths mature:

- Source policy: free-play updates mastery but not the daily headline.
- Coverage state is "calibrating" until minimum evidence.
- (v2) Migration anchoring: headline at cutover ≈ last shown, → 0 offset by ~day 14.
- (v2) Time-aware certainty: variance grows more after a long gap than a one-day gap.

---

## 13. Implementation order

Both source docs agree on the first four steps; the back half is where the redesign's
correctness layers come in.

**Phase 1 — Trust bugs (ship before the redesign):**
1. Fix same-day domain overwrite → aggregate via Layer 4 (not `domains[k] = v`).
2. Split `base_score` / `bonus_multiplier`; bests use base only.
3. WordConnect saved level matches its unlock UI.
4. Lock one source policy (§6).

**Phase 2 — Measurement contract (no UI change):**
5. Add `ScoredRun` (`performance`, `confidence`, `abilitySignal`); keep `accuracy` for
   back-compat.
6. Per-game `GameScoringPolicy` — start with the divergent games: SpotSpeed (threshold),
   MatchBack (d′), the throughput set (RCS), TowerOfHanoi / DotsConnect (efficiency).
7. Mastery v1 continuous update; persist `performance_quality`, `mastery_after`, etc.

**Phase 3 — Validity (switch WPI source):**
8. Layer 3 calibration (`z_g → A_g`) + Layer 4 aggregation; **delete the duplicate
   headline.**
9. Migration anchoring + replay; onboarding pipeline-seeding.
10. Coverage / calibration labels.

**Phase 4 — Honesty & polish:**
11. Update help sheet; strip percentile / brain-age claims until norms exist.

**Phase 5 — Data-driven calibration (once real usage exists):**
12. Recompute `(μ_g, σ_g)` from real distributions; tune `target`, `stepSize`, `β`, `τ`.
13. Swap Kalman filter in behind the v1 interface if jitter warrants.
14. Add cohort percentiles *only* if the dataset supports them; version policy changes.

---

## 14. Ships on defaults vs. needs real data

| Component | Status |
|-----------|--------|
| Continuous ladder, per-game policies, RCS, d′, aggregation, one headline | **ships now** |
| Same-day fix, base/bonus split, WordConnect unlock, source policy | **ships now (Phase 1)** |
| `μ_g, σ_g` norms; any percentile / "brain age" claim | **needs real N — gate the UI** |
| `d′` inputs, `timeOnTaskMs` | **cheap instrumentation — falls back to `accuracy`/`trials`** |
| Kalman `q, k, σ²`; `τ`; target `a*`; shrinkage `k_d`; RCS `β` | **ships on defaults, tune later** |
| RT speed term | **opt-in — only RuleFinder & SpotSpeed emit RT today; never fabricate** |
| Migration replay | **needs legacy rows to carry `threshold`/`trials`/`details` — verify, else seed-only** |

---

## Bottom line

The proposal made the score *buildable*; the redesign made it *correct*. Merged:

- Each game emits a normalized **performance** (no universal accuracy rubric).
- Mastery is a continuous, confidence-weighted estimate (Kalman-ready, but ships scalar).
- Every game's ability is **z-scored to a common scale before averaging** — the seam the
  proposal left open.
- Decay touches **certainty, never ability**; stale skills go uncertain, not frozen.
- **One headline**, identical on every screen.
- Migration **anchors** so no one sees a jump; onboarding **seeds** the same pipeline so
  the number stops evaporating.

Keep points fun. Keep adaptive difficulty for challenge. But make the score comparable,
robust, and honest — using signals the app already records and currently throws away.
