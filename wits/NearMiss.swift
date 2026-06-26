//
//  NearMiss.swift
//  wits
//
//  Shared helpers for classifying close-but-wrong answers.
//

enum NearMiss {
    /// Two cell indices are neighbours in a `cols`-wide grid, including diagonals.
    static func adjacent(_ a: Int, _ b: Int, cols: Int) -> Bool {
        guard a != b, cols > 0 else { return false }
        let (ar, ac) = (a / cols, a % cols)
        let (br, bc) = (b / cols, b % cols)
        return abs(ar - br) <= 1 && abs(ac - bc) <= 1
    }

    /// A timed answer counts as a near-miss when it lands in the last `band`
    /// fraction of the response window.
    static func lateAnswer(windowFrac: Double, band: Double = 0.15) -> Bool {
        windowFrac > 0 && windowFrac <= band
    }
}
