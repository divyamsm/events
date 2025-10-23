import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var profile: UserProfile?
    @Published var isLoading = true
    @Published var errorMessage: String?

    @Published var displayName: String = ""
    @Published var username: String = ""
    @Published var email: String = ""
    @Published var bio: String = ""
    @Published var photoURL: URL?
    @Published var joinDate: Date = Date()
    @Published var stats = ProfileStats(hostedCount: 0, attendedCount: 0, friendCount: 0, invitesSent: 0)
    @Published var eventPreferences: [String] = []

    private let db = Firestore.firestore()

    func loadProfile() async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No user signed in"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch user document from Firestore
            let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()

            if let data = userDoc.data() {
                // Update published properties
                displayName = data["displayName"] as? String ?? currentUser.displayName ?? "User"
                username = data["username"] as? String ?? ""
                email = data["email"] as? String ?? currentUser.email ?? ""
                bio = data["bio"] as? String ?? ""

                if let photoURLString = data["photoURL"] as? String, !photoURLString.isEmpty {
                    photoURL = URL(string: photoURLString)
                }

                // Parse join date
                if let timestamp = data["createdAt"] as? Timestamp {
                    joinDate = timestamp.dateValue()
                }

                // Load preferences
                if let prefs = data["eventPreferences"] as? [String] {
                    eventPreferences = prefs
                }

                // Load stats
                await loadStats(userId: currentUser.uid)

                print("[Profile] ✅ Loaded profile for \(displayName)")
            } else {
                // Profile doesn't exist in Firestore, use Firebase Auth data
                displayName = currentUser.displayName ?? currentUser.email?.components(separatedBy: "@").first ?? "User"
                email = currentUser.email ?? ""

                print("[Profile] ⚠️ No Firestore profile found, using Auth data")
            }

            isLoading = false
        } catch {
            errorMessage = "Failed to load profile: \(error.localizedDescription)"
            isLoading = false
            print("[Profile] ❌ Error loading profile: \(error)")
        }
    }

    private func loadStats(userId: String) async {
        // Load event statistics
        do {
            // Count hosted events
            let hostedSnapshot = try await db.collection("events")
                .whereField("ownerId", isEqualTo: userId)
                .getDocuments()

            stats.hostedCount = hostedSnapshot.documents.count

            // Count attended events (members subcollection)
            let eventsSnapshot = try await db.collection("events").getDocuments()
            var attendedCount = 0

            for eventDoc in eventsSnapshot.documents {
                let membersSnapshot = try await eventDoc.reference
                    .collection("members")
                    .whereField("userId", isEqualTo: userId)
                    .whereField("status", isEqualTo: "accepted")
                    .getDocuments()

                if !membersSnapshot.documents.isEmpty {
                    attendedCount += 1
                }
            }

            stats.attendedCount = attendedCount

            // This is a simplified version - in production, you'd have a separate friends collection
            stats.friendCount = 0
            stats.invitesSent = 0

        } catch {
            print("[Profile] ⚠️ Error loading stats: \(error)")
        }
    }

    func updateProfile(displayName: String? = nil, bio: String? = nil, photoURL: URL? = nil) async {
        guard let currentUser = Auth.auth().currentUser else { return }

        var updates: [String: Any] = [:]

        if let displayName = displayName {
            updates["displayName"] = displayName
            self.displayName = displayName
        }

        if let bio = bio {
            updates["bio"] = bio
            self.bio = bio
        }

        if let photoURL = photoURL {
            updates["photoURL"] = photoURL.absoluteString
            self.photoURL = photoURL
        }

        updates["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db.collection("users").document(currentUser.uid).updateData(updates)
            print("[Profile] ✅ Profile updated")
        } catch {
            print("[Profile] ❌ Error updating profile: \(error)")
            errorMessage = "Failed to update profile"
        }
    }

    func updateEventPreferences(_ preferences: [String]) async {
        guard let currentUser = Auth.auth().currentUser else { return }

        do {
            try await db.collection("users").document(currentUser.uid).updateData([
                "eventPreferences": preferences,
                "updatedAt": FieldValue.serverTimestamp()
            ])

            self.eventPreferences = preferences
            print("[Profile] ✅ Event preferences updated")
        } catch {
            print("[Profile] ❌ Error updating preferences: \(error)")
            errorMessage = "Failed to update preferences"
        }
    }
}
