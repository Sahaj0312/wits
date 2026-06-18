//
//  OnboardingAccount.swift
//  wits
//
//  Section one: account creation. Sign-up method (Apple / Google / email OTP)
//  and date of birth — Lumosity's order, wits' voice, real Supabase auth.
//

import SwiftUI
import AuthenticationServices

// MARK: - Sign-up method

struct AuthScreen: View {
    var onAuthed: () -> Void

    @Environment(SupabaseManager.self) private var supa

    private enum Mode { case chooser, email, code }
    @State private var mode: Mode = .chooser
    @State private var email = ""
    @State private var code = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)

            switch mode {
            case .chooser: chooser
            case .email:   emailEntry
            case .code:    codeEntry
            }

            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .animation(.easeOut(duration: 0.22), value: mode)
        .onAppear {
            // Returning user with a restored session — skip straight past sign-up.
            if supa.isSignedIn { onAuthed() }
        }
    }

    // MARK: Chooser

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("create your account")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("so we can save your progress and pick up right where you left off.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .rise(0.08)

            VStack(spacing: 10) {
                ProviderButton(
                    label: "continue with apple",
                    systemImage: "apple.logo",
                    fg: .white, bg: Color.black
                ) { run { try await supa.signInWithApple() } }
                    .rise(0.16)

                ProviderButton(
                    label: "continue with google",
                    assetGlyph: "G",
                    fg: Color.witsInk, bg: Color.witsCard, bordered: true
                ) { run { try await supa.signInWithGoogle() } }
                    .rise(0.22)

                ProviderButton(
                    label: "continue with email",
                    systemImage: "envelope.fill",
                    fg: Color.witsInk, bg: Color.witsCard, bordered: true
                ) { withAnimation { mode = .email } }
                    .rise(0.28)
            }

            errorView

            Text("by continuing you agree to our terms of service & privacy policy.")
                .font(.witsBody(12))
                .foregroundStyle(Color.witsFaint)
                .padding(.top, 18)
                .rise(0.36)
        }
    }

    // MARK: Email entry

    private var emailEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackChip { withAnimation { mode = .chooser; error = nil } }
                .padding(.bottom, 18)
            Text("what's your email")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
            Text("we'll send a 6-digit code. no password to forget.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 24)

            FieldCard {
                TextField("you@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.witsBody(17, weight: .semibold))
            }

            errorView

            Cta(title: working ? "sending…" : "send the code", dimmed: !emailValid || working) {
                guard emailValid, !working else { return }
                run(advanceTo: .code) { try await supa.sendEmailOTP(email.trimmed) }
            }
            .padding(.top, 20)
        }
    }

    // MARK: Code entry

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackChip { withAnimation { mode = .email; code = ""; error = nil } }
                .padding(.bottom, 18)
            Text("enter the code")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
            Text("sent to \(email.trimmed). check your spam folder if you don't see it.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 24)

            FieldCard {
                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .kerning(6)
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(6))
                    }
            }

            errorView

            Cta(title: working ? "verifying…" : "verify", dimmed: code.count < 6 || working) {
                guard code.count >= 6, !working else { return }
                run(onSuccess: onAuthed) { try await supa.verifyEmailOTP(email: email.trimmed, token: code) }
            }
            .padding(.top, 20)

            QuietButton(title: "resend code") {
                run { try await supa.sendEmailOTP(email.trimmed) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
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

    private var emailValid: Bool {
        let e = email.trimmed
        return e.contains("@") && e.contains(".") && e.count >= 5
    }

    /// Runs an async auth action with loading + error handling.
    /// `advanceTo` switches mode on success; `onSuccess` fires a completion.
    private func run(
        advanceTo nextMode: Mode? = nil,
        onSuccess: (() -> Void)? = nil,
        _ action: @escaping () async throws -> Void
    ) {
        working = true
        error = nil
        Task {
            do {
                try await action()
                working = false
                if let nextMode { withAnimation { mode = nextMode } }
                onSuccess?()
                // Apple/Google land here already signed in → advance the flow.
                if nextMode == nil && onSuccess == nil && supa.isSignedIn {
                    onAuthed()
                }
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
            Text("this is the name your friends see on the activity board. it doesn't have to be unique.")
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

private struct BackChip: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                Text("back").font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.witsFaint)
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
