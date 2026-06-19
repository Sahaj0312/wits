//
//  ProgressMath.swift
//  wits
//
//  Turns raw per-day rollups into the smoothed series the progress screen shows.
//  Per-domain scores are exponentially-weighted (recency-biased) so the "your
//  brain is improving" line is steady, not jittery. This is a measurement of how
//  you do on the trained games over time — not a claim about real-world IQ.
//

import Foundation

struct SeriesPoint: Identifiable {
    let id = UUID()
    let day: Date
    let value: Double
}

enum ProgressMath {
    static let alpha = 0.35

    /// Running EWMA over a value series.
    static func ewma(_ xs: [Double], alpha: Double = alpha) -> [Double] {
        var out: [Double] = []
        var prev: Double?
        for x in xs {
            let v = prev.map { $0 + alpha * (x - $0) } ?? x
            out.append(v)
            prev = v
        }
        return out
    }

    private static func sortedDays(_ days: [DailyProgressRow]) -> [DailyProgressRow] {
        days.filter { $0.workout_done == true }
            .sorted { ($0.dayDate ?? .distantPast) < ($1.dayDate ?? .distantPast) }
    }

    /// Smoothed headline (overall) score per active day.
    static func headlineSeries(_ days: [DailyProgressRow]) -> [SeriesPoint] {
        let rows = sortedDays(days)
        let raw = rows.map { row -> Double in
            if let h = row.headline_index { return h }
            let ds = row.domain_scores ?? [:]
            return ds.isEmpty ? 0 : ds.values.reduce(0, +) / Double(ds.count)
        }
        let smooth = ewma(raw)
        return zip(rows, smooth).compactMap { row, v in
            row.dayDate.map { SeriesPoint(day: $0, value: (v * 10).rounded() / 10) }
        }
    }

    /// Smoothed score over time for a single domain (only days it was trained).
    static func domainSeries(_ days: [DailyProgressRow], _ domain: CognitiveDomain) -> [SeriesPoint] {
        let pairs: [(Date, Double)] = sortedDays(days).compactMap { row in
            guard let v = row.domain_scores?[domain.rawValue], let d = row.dayDate else { return nil }
            return (d, v)
        }
        let smooth = ewma(pairs.map { $0.1 })
        return zip(pairs, smooth).map { SeriesPoint(day: $0.0, value: $1.rounded()) }
    }

    /// Latest smoothed score per domain (for the per-domain bars).
    static func latestDomainScores(_ days: [DailyProgressRow]) -> [CognitiveDomain: Double] {
        let rows = sortedDays(days)
        var result: [CognitiveDomain: Double] = [:]
        for domain in CognitiveDomain.allCases {
            let raw = rows.compactMap { $0.domain_scores?[domain.rawValue] }
            if let last = ewma(raw).last {
                result[domain] = (last).rounded()
            }
        }
        return result
    }

    /// The single hero number — mean of the latest smoothed domain scores.
    static func headline(_ days: [DailyProgressRow]) -> Double? {
        let domains = latestDomainScores(days)
        guard !domains.isEmpty else { return nil }
        return (domains.values.reduce(0, +) / Double(domains.count)).rounded()
    }

    // MARK: - Adaptive workout targeting

    /// A domain never trained yet starts at this "needs training" weight — high
    /// enough to get picked up early (explore the unknown) without overriding a
    /// genuinely weak, measured domain.
    static let unknownWeakness = 55.0
    /// Each untrained day adds this much priority …
    static let stalenessPerDay = 8.0
    /// … capped here, so staleness nudges a strong domain back into rotation
    /// over a few days but never outweighs a real, persistent weakness.
    static let stalenessCap = 40.0

    /// Per-domain "needs training" priority used to bias the daily workout
    /// toward what's lagging. Higher = train sooner. Two signals combine:
    ///
    /// - **weakness** — `100 − smoothed score`, so the domains you score lowest
    ///   on rank highest (untrained domains get `unknownWeakness`);
    /// - **staleness** — a bonus that grows the longer a domain goes untrained,
    ///   capped at `stalenessCap`, so a strong domain can't be starved out of
    ///   the rotation forever (its score would otherwise freeze and never fall).
    ///
    /// Returns a value for every `CognitiveDomain`. Returns an empty map only
    /// when there's no history at all, which the workout builder reads as the
    /// signal to fall back to its plain rotating window.
    static func domainPriorities(_ days: [DailyProgressRow], asOf today: Date,
                                 calendar: Calendar = .current) -> [CognitiveDomain: Double] {
        let scored = sortedDays(days)
        guard !scored.isEmpty else { return [:] }

        let scores = latestDomainScores(days)        // smoothed 0…100, trained domains only
        let start = calendar.startOfDay(for: today)
        var result: [CognitiveDomain: Double] = [:]
        for domain in CognitiveDomain.allCases {
            let weakness = scores[domain].map { 100 - min(100, max(0, $0)) } ?? unknownWeakness

            let lastTrained = scored
                .filter { $0.domain_scores?[domain.rawValue] != nil }
                .compactMap { $0.dayDate }
                .max()
            let staleness: Double
            if let last = lastTrained {
                let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: start).day ?? 0
                staleness = min(stalenessCap, Double(max(0, d)) * stalenessPerDay)
            } else {
                staleness = stalenessCap              // never trained → fully stale
            }
            result[domain] = weakness + staleness
        }
        return result
    }
}
