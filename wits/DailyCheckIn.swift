//
//  DailyCheckIn.swift
//  wits
//
//  A quick mood + sleep check-in shown before the daily workout. Two taps, fully
//  skippable, and dismissable for good. Feeds the lifestyle charts on Activity.
//

import SwiftUI

struct DailyCheckInView: View {
    /// Called when the flow ends. nil values mean that question was skipped.
    var onFinish: (_ mood: Int?, _ sleep: Int?) -> Void
    /// "stop these check-ins" — disable future prompts.
    var onStop: () -> Void

    @State private var step = 0
    @State private var mood: Int?
    @State private var sleep: Int?

    private let moods = ["😣", "🙁", "😐", "🙂", "😄"]
    private let sleepRows = ["5 hours or less", "6 hours", "7 hours", "8 hours", "9 or more"]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            WitsBrandMark().padding(.bottom, 20)
            if step == 0 { moodStep } else { sleepStep }
            Spacer()
            bottomBar
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.witsBg.ignoresSafeArea())
        .animation(.easeOut(duration: 0.22), value: step)
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Color.witsAccent : Color.witsLine)
                    .frame(width: i == step ? 20 : 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button { onFinish(mood, sleep) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.witsMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private var moodStep: some View {
        VStack(spacing: 26) {
            Text("how do you feel today?")
                .font(.witsDisplay(27))
                .foregroundStyle(Color.witsInk)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                ForEach(0..<moods.count, id: \.self) { i in
                    let selected = mood == i + 1
                    Button { selectMood(i) } label: {
                        Text(moods[i])
                            .font(.system(size: 28))
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(selected ? Color.witsAccent.opacity(0.22) : Color.witsCard))
                            .overlay(Circle().strokeBorder(selected ? Color.witsAccent : Color.witsLine,
                                                           lineWidth: selected ? 2 : 1))
                            .scaleEffect(selected ? 1.08 : 1)
                            .shadow(color: .witsShadow, radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sleepStep: some View {
        VStack(spacing: 22) {
            Text("how many hours did you sleep last night?")
                .font(.witsDisplay(27))
                .foregroundStyle(Color.witsInk)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                ForEach(0..<sleepRows.count, id: \.self) { i in
                    let selected = sleep == i
                    Button { selectSleep(i) } label: {
                        Text(sleepRows[i])
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? .white : Color.witsInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(selected ? Color.witsAccent : Color.witsCard, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.witsLine, lineWidth: selected ? 0 : 1))
                            .shadow(color: .witsShadow, radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button(action: onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "nosign").font(.system(size: 13, weight: .bold))
                    Text("stop these check-ins").font(.system(size: 13.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.witsFaint)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { skip() } label: {
                HStack(spacing: 4) {
                    Text("skip").font(.system(size: 14, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(Color.witsMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private func selectMood(_ i: Int) {
        mood = i + 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { withAnimation { step = 1 } }
    }

    private func selectSleep(_ i: Int) {
        sleep = i
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onFinish(mood, sleep) }
    }

    private func skip() {
        if step == 0 { withAnimation { step = 1 } } else { onFinish(mood, sleep) }
    }
}
