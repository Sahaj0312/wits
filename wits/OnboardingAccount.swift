//
//  OnboardingAccount.swift
//  wits
//
//  Section one: account creation. Sign-up method (Apple / Google)
//  and date of birth — Lumosity's order, wits' voice, real Supabase auth.
//

import SwiftUI
import AuthenticationServices

// MARK: - Sign-up method (bottom sheet)

struct AuthSheet: View {
    var onAuthed: () -> Void

    @Environment(SupabaseManager.self) private var supa

    @State private var working = false
    @State private var error: String?
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("create your account")
                .font(.witsDisplay(28))
                .foregroundStyle(Color.witsInk)
            Text("so we can save your progress and pick up right where you left off.")
                .font(.witsBody(15))
                .foregroundStyle(Color.witsMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                ProviderButton(
                    label: "continue with apple",
                    systemImage: "apple.logo",
                    fg: .white, bg: Color.black
                ) { run { try await supa.signInWithApple() } }

                ProviderButton(
                    label: "continue with google",
                    assetGlyph: "G",
                    fg: Color.witsInk, bg: Color.witsCard, bordered: true
                ) { run { try await supa.signInWithGoogle() } }
            }

            errorView

            Text("by continuing you agree to our terms of service & privacy policy.")
                .font(.witsBody(12))
                .foregroundStyle(Color.witsFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(SheetHeightKey.self) { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.witsBg)
    }

    // MARK: Bits

    @ViewBuilder private var errorView: some View {
        if let error {
            Text(error)
                .font(.witsBody(13, weight: .semibold))
                .foregroundStyle(Color.witsWarm)
                .padding(.top, 14)
                .transition(.opacity)
        }
    }

    /// Runs an async auth action with loading + error handling.
    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            do {
                try await action()
                working = false
                // Apple/Google land here already signed in → advance the flow.
                if supa.isSignedIn { onAuthed() }
            } catch SupabaseError.cancelled {
                working = false
            } catch {
                working = false
                withAnimation { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
        }
    }
}

// MARK: - Username

struct UsernameScreen: View {
    var suggested: String?
    var onNext: (String) -> Void

    @State private var username = ""

    private var trimmed: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { trimmed.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("pick a username")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("this is the name shown on your profile. it doesn't have to be unique.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .rise(0.08)

            FieldCard {
                TextField("your username", text: $username)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(.witsBody(17, weight: .semibold))
                    .onChange(of: username) { _, new in
                        username = String(new.prefix(24))
                    }
            }
            .rise(0.16)

            Spacer()
            Cta(title: "continue", dimmed: !valid) {
                guard valid else { return }
                onNext(trimmed)
            }
            .rise(0.28)
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .onAppear {
            if username.isEmpty, let suggested, !suggested.isEmpty { username = suggested }
        }
    }
}

// MARK: - Date of birth

struct BirthdateScreen: View {
    var onNext: (Date) -> Void

    @State private var date: Date = {
        var c = DateComponents(); c.year = 2000; c.month = 1; c.day = 1
        return Calendar.current.date(from: c) ?? .now
    }()

    private var range: ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date()
        let oldest = cal.date(byAdding: .year, value: -100, to: now) ?? now
        let youngest = cal.date(byAdding: .year, value: -13, to: now) ?? now
        return oldest...youngest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("what's your date of birth?")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("we use this to set the right baseline for your age.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .rise(0.08)

            DatePicker("", selection: $date, in: range, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .cardSurface()
                .rise(0.16)

            Spacer()
            Cta(title: "continue") { onNext(date) }
                .rise(0.28)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Shared bits

private struct ProviderButton: View {
    var label: String
    var systemImage: String? = nil
    var assetGlyph: String? = nil
    var fg: Color
    var bg: Color
    var bordered = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                } else if let assetGlyph {
                    Text(assetGlyph).font(.system(size: 17, weight: .heavy, design: .rounded))
                }
                Text(label).font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(bg, in: Capsule())
            .overlay(Capsule().strokeBorder(bordered ? Color.witsLine : .clear, lineWidth: 1.5))
            .shadow(color: .witsShadow, radius: 8, y: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct SheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 300
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FieldCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.witsCard, in: RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous).strokeBorder(Color.witsLine, lineWidth: 1.5))
            .shadow(color: .witsShadow, radius: 10, y: 6)
    }
}
