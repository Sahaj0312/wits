//
//  FriendsView.swift
//  wits
//
//  Add a friend by code, see their streak + your shared friend-streak. A single
//  friend in the app is one of the strongest anti-churn signals there is.
//

import SwiftUI

struct FriendsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var codeInput = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("friends")
                    .font(.witsDisplay(28))
                    .foregroundStyle(Color.witsInk)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("your code")
                        .font(.witsBody(13, weight: .bold))
                        .foregroundStyle(Color.witsMuted)
                    HStack {
                        Text(app.friendCode ?? "…")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .kerning(3)
                            .foregroundStyle(Color.witsAccent)
                        Spacer()
                        if let code = app.friendCode {
                            ShareLink(item: "add me on wits — my code is \(code)") {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(Color.witsInk)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .cardSurface()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("add a friend")
                        .font(.witsBody(13, weight: .bold))
                        .foregroundStyle(Color.witsMuted)
                    HStack(spacing: 10) {
                        TextField("their code", text: $codeInput)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 13)
                            .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button {
                            Task { await add() }
                        } label: {
                            Text(working ? "…" : "add")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20).padding(.vertical, 14)
                                .background(Color.witsAccent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(codeInput.count < 4)
                    }
                    if let error {
                        Text(error).font(.witsBody(13)).foregroundStyle(Color.witsWarm)
                    }
                }

                if !app.friends.isEmpty {
                    Text("your friends")
                        .font(.witsBody(13, weight: .bold))
                        .foregroundStyle(Color.witsMuted)
                        .padding(.top, 4)
                    ForEach(Array(app.friends.enumerated()), id: \.offset) { _, f in
                        friendRow(f)
                    }
                }
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .task {
            await app.loadFriendCode()
            await app.refreshFriends()
        }
    }

    private func friendRow(_ f: FriendInfo) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.fill")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 38, height: 38)
                .background(Color.witsAccent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("wits friend")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Text(f.trainedToday ? "trained today" : "hasn't trained today")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(f.trainedToday ? Color.witsAccent : Color.witsMuted)
            }
            Spacer()
            if f.friendStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.witsWarm)
                    Text("\(f.friendStreak)").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Color.witsInk).monospacedDigit()
                }
            }
        }
        .padding(14)
        .cardSurface()
    }

    private func add() async {
        working = true
        error = nil
        let ok = await app.addFriend(codeInput)
        working = false
        if ok { codeInput = "" } else { error = "couldn't find that code." }
    }
}
