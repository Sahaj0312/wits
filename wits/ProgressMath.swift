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
}
