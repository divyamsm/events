import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@MainActor
class BlockedUsersManager: ObservableObject {
    @Published var blockedUsers: Set<String> = []
    @Published var blockedUserProfiles: [BlockedUserProfile] = []
    @Published var isLoading = false

    struct BlockedUserProfile: Identifiable {
        let id: String
        let name: String
        let blockedAt: Date
    }

    func loadBlockedUsers(for userId: String) async {
        print("[BlockedUsersManager] Loading blocked users for: \(userId)")
        isLoading = true
        defer { isLoading = false }

        #if canImport(FirebaseFirestore)
        do {
            let db = Firestore.firestore()

            // Load blocked user IDs
            let blockedSnapshot = try await db.collection("users")
                .document(userId)
                .collection("blocked")
                .getDocuments()

            blockedUsers = Set(blockedSnapshot.documents.map { $0.documentID })
            print("[BlockedUsersManager] Loaded \(blockedUsers.count) blocked user IDs")

            // Load profile information for each blocked user
            var profiles: [BlockedUserProfile] = []

            for doc in blockedSnapshot.documents {
                let blockedUserId = doc.documentID
                let blockedAt = (doc.data()["blockedAt"] as? Timestamp)?.dateValue() ?? Date()

                // Fetch user profile
                let userDoc = try await db.collection("users").document(blockedUserId).getDocument()
                let userName = userDoc.data()?["displayName"] as? String ?? "User \(blockedUserId.prefix(8))"

                profiles.append(BlockedUserProfile(
                    id: blockedUserId,
                    name: userName,
                    blockedAt: blockedAt
                ))
            }

            blockedUserProfiles = profiles.sorted { $0.blockedAt > $1.blockedAt }
            print("[BlockedUsersManager] Loaded \(profiles.count) blocked user profiles")
        } catch {
            print("[BlockedUsersManager] Error loading blocked users: \(error.localizedDescription)")
        }
        #endif
    }

    func unblockUser(_ userId: String, currentUserId: String) async -> Bool {
        print("[BlockedUsersManager] Unblocking user: \(userId)")

        #if canImport(FirebaseFirestore)
        do {
            let db = Firestore.firestore()

            try await db.collection("users")
                .document(currentUserId)
                .collection("blocked")
                .document(userId)
                .delete()

            blockedUsers.remove(userId)
            blockedUserProfiles.removeAll { $0.id == userId }

            print("[BlockedUsersManager] Successfully unblocked user: \(userId)")
            return true
        } catch {
            print("[BlockedUsersManager] Error unblocking user: \(error.localizedDescription)")
            return false
        }
        #else
        return false
        #endif
    }
}
