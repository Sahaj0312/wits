//
//  TodayView.swift
//  wits
//
//  The retention surface. One job: get a returning user into today's workout in
//  one tap. Shows the streak (loss aversion), the day's games, and a single big
//  start button — or, once done, a finite "come back tomorrow" stop point.
//

import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var app
    @State private var playing = false
    @State private var showPrimer = false
    @State private var showPaywall = false
    @State private var challengeGame: GameID?
    @State private var showWeekTraining = false
    @State private var selectedDayOffset = 0
    @AppStorage("notifPrimerAsked") private var notifPrimerAsked = false
    private let futurePreviewDays = 14

    private var selectedDate: Date {
        date(for: selectedDayOffset)
    }

    private var selectedDay: TodayWorkoutDay {
        workoutDay(for: selectedDate)
    }

    private var firstSelectableDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let activeDates = app.progressDays
            .compactMap { $0.dayDate.map { cal.startOfDay(for: $0) } }
        return min(activeDates.min() ?? today, today)
    }

    private var firstSelectableOffset: Int {
        dayOffset(for: firstSelectableDate)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 22) {
                header
                    .padding(.horizontal, WitsMetrics.screenPadding)
                    .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        selectedWorkoutView(selectedDay)

                        if case .trial = app.entitlement {
                            Text("\(app.entitlement.trialDaysLeft) days left in your free trial")
                                .font(.witsBody(12.5))
                                .foregroundStyle(Color.witsFaint)
                                .frame(maxWidth: .infinity)
                        }

                        if Calendar.current.isDateInToday(selectedDate),
                           let g = app.dailyChallengeGame, !app.dailyChallengeDone {
                            challengeCard(g)
                        }
                    }
                    .padding(.horizontal, WitsMetrics.screenPadding)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }

            if showWeekTraining {
                weekTrainingOverlay
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(2)
            }
        }
        .background(Color.witsBg.ignoresSafeArea())
        .animation(.snappy(duration: 0.24), value: showWeekTraining)
        .sensoryFeedback(.selection, trigger: showWeekTraining)
        .sensoryFeedback(.selection, trigger: selectedDayOffset)
        .fullScreenCover(isPresented: $playing) {
            GameHost(
                workout: app.today,
                difficultyFor: app.difficultyFor,
                onGameResult: { app.recordWorkoutGame($0) },
                onWorkoutDone: { _ in
                    // rollup already happened as the final game completed; just close.
                    playing = false
                    // first value moment → offer reminders (once)
                    if !notifPrimerAsked && !app.profile.notificationsEnabled {
                        notifPrimerAsked = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showPrimer = true }
                    }
                },
                onQuit: { playing = false }
            )
        }
        .sheet(isPresented: $showPrimer) {
            NotificationPrimer()
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
        .fullScreenCover(item: $challengeGame) { g in
            GameHost(
                workout: DailyWorkout(day: app.today.day, games: [g]),
                difficultyFor: app.difficultyFor,
                onGameResult: { _ in },
                onWorkoutDone: { results in
                    if let r = results.first { app.completeDailyChallenge(r) }
                    challengeGame = nil
                },
                onQuit: { challengeGame = nil }
            )
        }
    }

    private var weekTrainingOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.2)) {
                        showWeekTraining = false
                    }
                }

            WeekTrainingPanel(
                offsets: centeredWeekOffsets,
                selectedOffset: selectedDayOffset,
                currentStreak: app.streak.current,
                dayProvider: { workoutDay(for: date(for: $0)) },
                isEnabled: isWeekDayEnabled,
                select: selectWeekDay,
                close: { showWeekTraining = false }
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 16)
            .padding(.top, 102)
            .padding(.horizontal, 16)
        }
    }

    private var centeredWeekOffsets: [Int] {
        Array(-3...3)
    }

    private func clampedDayOffset(_ offset: Int) -> Int {
        min(futurePreviewDays, max(firstSelectableOffset, offset))
    }

    private func isWeekDayEnabled(_ date: Date) -> Bool {
        isSelectable(date)
    }

    private func selectWeekDay(_ offset: Int) {
        let date = date(for: offset)
        guard isWeekDayEnabled(date) else { return }
        withAnimation(.snappy(duration: 0.24)) {
            selectedDayOffset = clampedDayOffset(offset)
            showWeekTraining = false
        }
    }

    private func selectedWorkoutView(_ day: TodayWorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            workoutHeroCard(day)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Calendar.current.isDateInToday(day.date) ? "today's games" : "workout games")
                        .font(.witsDisplay(18))
                        .foregroundStyle(Color.witsMuted)
                    Spacer()
                    statusBadge(day)
                }

                VStack(spacing: 10) {
                    ForEach(day.rows) { row in
                        workoutGameRow(row, locked: day.state == .locked)
                    }
                }
            }
        }
    }

    private func workoutHeroCard(_ day: TodayWorkoutDay) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.witsCard)

            FocusCardArtwork()
                .padding(.trailing, -24)
                .padding(.bottom, -30)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: heroIcon(for: day))
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.witsAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Calendar.current.isDateInToday(day.date) ? "daily workout" : Self.shortDateFormatter.string(from: day.date))
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsMuted)
                        Text(day.statusText)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(day.statusColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(day.statusColor.opacity(0.14), in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(heroTitle(for: day))
                        .font(.witsDisplay(30))
                        .foregroundStyle(Color.witsInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text(heroSubtitle(for: day))
                        .font(.witsBody(16.5, weight: .medium))
                        .foregroundStyle(Color.witsMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 9) {
                    heroStat("\(day.rows.count)", "games")
                    heroStat("3-4", "min")
                    if day.completedCount > 0 {
                        heroStat("\(day.completedCount)/\(day.rows.count)", "done")
                    }
                }

                Spacer(minLength: 20)

                heroAction(for: day)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 318)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.witsLine, lineWidth: 1)
        }
        .shadow(color: .witsShadow, radius: 16, y: 8)
    }

    @ViewBuilder
    private func heroAction(for day: TodayWorkoutDay) -> some View {
        switch day.state {
        case .today, .inProgress:
            Button(action: beginWorkout) {
                HStack(spacing: 10) {
                    Text(day.state == .inProgress ? "Resume Workout" : "Start Workout")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .heavy))
                }
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.witsAccent, in: Capsule())
            }
            .buttonStyle(.plain)
        case .done, .doneToday:
            heroStatePill("Workout Complete", icon: "checkmark.circle.fill")
        case .partial:
            heroStatePill("\(day.completedCount)/\(day.rows.count) Games Done", icon: "clock.fill")
        case .missed:
            heroStatePill("No Workout Recorded", icon: "calendar.badge.exclamationmark")
        case .locked:
            heroStatePill("Unlocks \(Self.shortDateFormatter.string(from: day.date))", icon: "lock.fill")
        }
    }

    private func heroStatePill(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .heavy))
            Text(text)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.witsAccent.opacity(0.9), in: Capsule())
    }

    private func heroTitle(for day: TodayWorkoutDay) -> String {
        switch day.state {
        case .done, .doneToday:
            return Calendar.current.isDateInToday(day.date) ? "Nice work today" : "\(day.title) complete"
        case .locked:
            return "Queued for later"
        default:
            return Calendar.current.isDateInToday(day.date) ? "Your focus set is ready" : "\(day.title) is ready"
        }
    }

    private func heroSubtitle(for day: TodayWorkoutDay) -> String {
        switch day.state {
        case .today:
            return "A short set built from the skills that need the most attention right now."
        case .inProgress:
            return "Pick up where you left off and keep your streak moving."
        case .doneToday:
            return "You finished the set. Tomorrow brings a fresh mix."
        case .done:
            return "You completed all \(day.rows.count) games for this day."
        case .partial:
            return "You started this workout. Finish the remaining games when you're ready."
        case .missed:
            return "No workout was recorded for this day."
        case .locked:
            return "This workout opens on \(Self.detailDateFormatter.string(from: day.date))."
        }
    }

    private func heroIcon(for day: TodayWorkoutDay) -> String {
        switch day.state {
        case .done, .doneToday: "checkmark.seal.fill"
        case .partial, .inProgress: "play.circle.fill"
        case .locked: "lock.fill"
        case .missed: "calendar.badge.exclamationmark"
        case .today: "sparkles"
        }
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusBadge(_ day: TodayWorkoutDay) -> some View {
        Text(day.statusText)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(day.statusColor)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(day.statusColor.opacity(0.14), in: Capsule())
    }

    private func workoutGameRow(_ row: TodayWorkoutRow, locked: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: row.game.symbol)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(locked ? Color.witsFaint : row.tint)
                .frame(width: 42, height: 42)
                .background((locked ? Color.witsFaint : row.tint).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(row.game.displayName)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Text(row.detailText)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let level = row.level {
                Text(String(format: "lvl %.1f", level))
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.witsAccent.opacity(0.14), in: Capsule())
            }

            Image(systemName: row.trailingSymbol(locked: locked))
                .font(.system(size: row.done ? 19 : 14, weight: .heavy))
                .foregroundStyle(row.trailingColor(locked: locked))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .opacity(locked ? 0.72 : 1)
    }

    private func challengeCard(_ g: GameID) -> some View {
        Button { challengeGame = g } label: {
            HStack(spacing: 14) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.witsWarm)
                    .frame(width: 44, height: 44)
                    .background(Color.witsWarm.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("surprise challenge")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                    Text("one round of \(g.displayName) · a quick bonus")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.witsFaint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .rise(0.1)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                WitsBrandMark()
                Text(Self.largeDateFormatter.string(from: Date()))
                    .font(.witsDisplay(34))
                    .foregroundStyle(Color.witsInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(Self.weekdayHeaderFormatter.string(from: Date()))
                    .font(.witsBody(15, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
            }
            Spacer()
            streakPill
        }
    }

    private var streakPill: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                showWeekTraining.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(app.streak.current > 0 ? Color.witsWarm : Color.witsFaint)
                Text("\(app.streak.current)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Color.witsCard, in: Capsule())
            .shadow(color: .witsShadow, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("training week history")
    }

    /// Starts or resumes today's workout from the selected-day detail.
    private func beginWorkout() {
        if app.entitlement.isExpired { showPaywall = true }
        else { playing = true }
    }

    private func date(for offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private func dayOffset(for date: Date) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: today, to: target).day ?? 0
    }

    private func isSelectable(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) >= firstSelectableDate
    }

    private func workoutDay(for date: Date) -> TodayWorkoutDay {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let today = cal.startOfDay(for: Date())
        let offset = cal.dateComponents([.day], from: today, to: start).day ?? 0
        let row = app.progressDays.first { $0.day == SupabaseManager.dayString(start) }

        let state: TodayWorkoutDay.State
        if cal.isDate(start, inSameDayAs: today) {
            state = app.isWorkoutDoneToday ? .doneToday
                : (app.today.results.isEmpty ? .today : .inProgress)
        } else if start > today {
            state = .locked
        } else {
            switch app.workoutStatus(on: start) {
            case .completed: state = .done
            case .partial: state = .partial
            case .none: state = .missed
            }
        }

        return TodayWorkoutDay(
            date: start,
            offset: offset,
            state: state,
            rows: workoutRows(for: start, state: state, progress: row)
        )
    }

    private func workoutRows(for date: Date,
                             state: TodayWorkoutDay.State,
                             progress: DailyProgressRow?) -> [TodayWorkoutRow] {
        switch state {
        case .today, .inProgress, .doneToday:
            let results = app.today.results
            return app.today.games.map { game in
                let result = results.first { $0.game == game }
                return TodayWorkoutRow(game: game,
                                       level: result?.newDifficulty?.level,
                                       done: result != nil)
            }
        case .done, .partial, .missed:
            let played = app.playedGames(on: date)
            let byGame = Dictionary(played.map { ($0.game, $0) }, uniquingKeysWith: { a, _ in a })
            let prescribed = progress?.workout_games?.compactMap { GameID(rawValue: $0) } ?? []

            if !prescribed.isEmpty {
                return prescribed.map { game in
                    let run = byGame[game]
                    return TodayWorkoutRow(game: game, level: run?.level, done: run != nil)
                }
            }
            if !played.isEmpty {
                return played.map { TodayWorkoutRow(game: $0.game, level: $0.level, done: true) }
            }
            return WorkoutBuilder.build(for: date).games.map {
                TodayWorkoutRow(game: $0, level: nil, done: false)
            }
        case .locked:
            return WorkoutBuilder.build(for: date).games.map {
                TodayWorkoutRow(game: $0, level: nil, done: false)
            }
        }
    }

    private static let detailDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let largeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    private static let weekdayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}

private struct TodayWorkoutDay {
    enum State { case done, doneToday, today, inProgress, partial, missed, locked }
    let date: Date
    let offset: Int
    let state: State
    let rows: [TodayWorkoutRow]

    var completedCount: Int { rows.filter(\.done).count }

    var title: String {
        if Calendar.current.isDateInToday(date) { return "today's workout" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow's workout" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        return Self.titleDateFormatter.string(from: date)
    }

    var subtitle: String {
        switch state {
        case .today: "ready when you are"
        case .inProgress: "\(completedCount)/\(rows.count) games finished"
        case .doneToday: "completed today"
        case .done: "completed"
        case .partial: "\(completedCount)/\(rows.count) games finished"
        case .missed: "missed workout"
        case .locked: Self.detailDateFormatter.string(from: date)
        }
    }

    var statusText: String {
        switch state {
        case .today: "ready"
        case .inProgress: "in progress"
        case .doneToday: "done"
        case .done: "done"
        case .partial: "partial"
        case .missed: "missed"
        case .locked: "locked"
        }
    }

    var statusColor: Color {
        switch state {
        case .today, .inProgress, .doneToday, .done: Color.witsAccent
        case .partial: Color.witsWarm
        case .missed, .locked: Color.witsMuted
        }
    }

    private static let titleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let detailDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
}

private struct TodayWorkoutRow: Identifiable {
    let game: GameID
    let level: Double?
    let done: Bool

    var id: String { game.rawValue }

    var tint: Color {
        done ? Color.witsAccent : Color.witsMuted
    }

    var detailText: String {
        "\(game.domain.label) · \(game.subskill)"
    }

    func trailingSymbol(locked: Bool) -> String {
        if done { return "checkmark.circle.fill" }
        return locked ? "lock.fill" : "circle"
    }

    func trailingColor(locked: Bool) -> Color {
        if done { return Color.witsAccent }
        return locked ? Color.witsFaint : Color.witsLine
    }
}

private struct WeekTrainingPanel: View {
    let offsets: [Int]
    let selectedOffset: Int
    let currentStreak: Int
    let dayProvider: (Int) -> TodayWorkoutDay
    let isEnabled: (Date) -> Bool
    let select: (Int) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("training rhythm")
                        .font(.witsDisplay(22))
                        .foregroundStyle(Color.witsInk)
                    Text("Pick a day to review its workout.")
                        .font(.witsBody(13, weight: .semibold))
                        .foregroundStyle(Color.witsMuted)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color.witsMuted)
                        .frame(width: 32, height: 32)
                        .background(Color.witsTint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("close training week")
            }
            .padding(.top, 18)
            .padding(.horizontal, 18)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(offsets, id: \.self) { offset in
                    let day = dayProvider(offset)
                    let enabled = isEnabled(day.date)
                    TrainingWeekDay(
                        day: day,
                        selected: selectedOffset == offset,
                        enabled: enabled,
                        action: { select(offset) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.witsWarm)
                    .frame(width: 30, height: 30)
                    .background(Color.witsWarm.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(streakPrompt)
                    .font(.witsBody(14.5, weight: .semibold))
                    .foregroundStyle(Color.witsInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(Color.witsCard)
    }

    private var streakPrompt: String {
        currentStreak > 0
            ? "Keep your \(currentStreak)-day streak going!"
            : "Train every day to build your streak!"
    }
}

private struct TrainingWeekDay: View {
    let day: TodayWorkoutDay
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    private var progress: Double {
        guard !day.rows.isEmpty else { return 0 }
        return Double(day.completedCount) / Double(day.rows.count)
    }

    private var weekday: String {
        Self.weekdayFormatter.string(from: day.date)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Text(dayLabel)
                    .font(.system(size: selected ? 12 : 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? Color.witsAccent : Color.witsFaint)
                    .frame(height: 14)

                TrainingProgressRing(progress: progress,
                                     state: day.state,
                                     selected: selected,
                                     enabled: enabled)

                Text(weekday)
                    .font(.system(size: 15.5, weight: selected ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.witsAccent.opacity(0.1))
                        .frame(width: 42, height: 96)
                }
            }
            .opacity(enabled ? 1 : 0.38)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("\(Self.accessibilityFormatter.string(from: day.date)), \(enabled ? day.statusText : "unavailable")")
    }

    private var labelColor: Color {
        if selected { return Color.witsInk }
        return enabled ? Color.witsMuted : Color.witsFaint
    }

    private var dayLabel: String {
        if Calendar.current.isDateInToday(day.date) { return "now" }
        return Self.dayFormatter.string(from: day.date)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let accessibilityFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}

private struct TrainingProgressRing: View {
    let progress: Double
    let state: TodayWorkoutDay.State
    let selected: Bool
    let enabled: Bool

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(baseColor, style: StrokeStyle(lineWidth: 3.8, lineCap: .round, dash: [12, 8]))
                .rotationEffect(.degrees(-90))

            if progress > 0 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else if state == .today || state == .inProgress {
                Circle()
                    .trim(from: 0, to: 0.18)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            if state == .done || state == .doneToday {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(accentColor)
            }
        }
        .frame(width: 36, height: 36)
    }

    private var baseColor: Color {
        enabled ? Color.witsLine.opacity(selected ? 0.8 : 1) : Color.witsLine
    }

    private var accentColor: Color {
        state == .partial || state == .inProgress ? Color(light: 0x7C3DFF, dark: 0xA589FF) : Color.witsAccent
    }
}

private struct FocusCardArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.witsAccent.opacity(0.12))
                .frame(width: 134, height: 134)
                .rotationEffect(.degrees(16))

            Circle()
                .stroke(Color.witsWarm.opacity(0.22), lineWidth: 16)
                .frame(width: 94, height: 94)
                .offset(x: 20, y: -18)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(Color.witsAccent.opacity(0.2))
                .offset(x: 7, y: 3)
        }
        .frame(width: 154, height: 154)
    }
}
