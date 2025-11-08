import SwiftUI

struct BlockedUsersView: View {
    let currentUserId: String
    let onUnblock: () -> Void
    @StateObject private var manager = BlockedUsersManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showUnblockConfirmation: BlockedUsersManager.BlockedUserProfile?

    var body: some View {
        content
            .navigationTitle("Blocked Users")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await manager.loadBlockedUsers(for: currentUserId)
            }
            .alert(item: $showUnblockConfirmation) { profile in
                Alert(
                    title: Text("Unblock \(profile.name)?"),
                    message: Text("You will see their events in your feed again."),
                    primaryButton: .destructive(Text("Unblock")) {
                        Task {
                            let success = await manager.unblockUser(profile.id, currentUserId: currentUserId)
                            if success {
                                print("[BlockedUsersView] User unblocked, calling refresh callback")
                                onUnblock()
                            }
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
    }

    private var content: some View {
        Group {
            if manager.isLoading {
                ProgressView("Loading blocked users...")
            } else if manager.blockedUserProfiles.isEmpty {
                emptyState
            } else {
                blockedUsersList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Blocked Users")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You haven't blocked anyone yet")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var blockedUsersList: some View {
        List {
            Section {
                ForEach(manager.blockedUserProfiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.headline)

                            Text("Blocked \(profile.blockedAt, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            showUnblockConfirmation = profile
                        }) {
                            Text("Unblock")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("\(manager.blockedUserProfiles.count) blocked \(manager.blockedUserProfiles.count == 1 ? "user" : "users")")
            } footer: {
                Text("Blocked users cannot see your events and you won't see their events in your feed.")
            }
        }
    }
}
