import Foundation
import SwiftUI
import CoreLocation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@MainActor
final class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentSession: UserSession?
    @Published var isLoading: Bool = true
    private weak var appState: AppState?

    #if canImport(FirebaseAuth)
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    #endif

    init(appState: AppState? = nil) {
        self.appState = appState
        print("[Auth] 🔴 AuthenticationManager.init() called")
        setupAuthListener()
    }

    deinit {
        #if canImport(FirebaseAuth)
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        #endif
    }

    private func setupAuthListener() {
        print("[Auth] 🔴 setupAuthListener CALLED")
        #if canImport(FirebaseAuth)
        print("[Auth] 🔴 About to add auth state listener...")
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            print("[Auth] 🟢 AUTH STATE CHANGED - user: \(user?.uid ?? "nil")")
            Task { @MainActor [weak self] in
                print("[Auth] 🟢 Inside Task @MainActor")
                guard let self = self else {
                    print("[Auth] 🔴 self is nil, returning")
                    return
                }

                if let user = user {
                    print("[Auth] 🟢 User is signed in: \(user.uid)")
                    await self.createSession(for: user)
                    self.isAuthenticated = true
                } else {
                    print("[Auth] 🟡 No user signed in")
                    self.currentSession = nil
                    self.isAuthenticated = false
                }

                print("[Auth] 🟢 Setting isLoading = false")
                self.isLoading = false
            }
        }
        print("[Auth] 🟢 Auth state listener added successfully")
        #else
        // For preview/testing without Firebase
        isLoading = false
        isAuthenticated = false
        #endif
    }

    private func createSession(for user: User) async {
        #if canImport(FirebaseFirestore)
        // Fetch user profile from Firestore
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)

        do {
            let doc = try await userRef.getDocument()

            // Get user data with fallbacks
            let displayName = doc.data()?["displayName"] as? String
                           ?? user.displayName
                           ?? user.email?.components(separatedBy: "@").first
                           ?? "User"
            let photoURLString = doc.data()?["photoURL"] as? String
            let photoURL = photoURLString.flatMap { URL(string: $0) }

            // Read UUID from Firestore, or generate if missing
            let uuidString = doc.data()?["id"] as? String
            let uuid: UUID
            if let uuidString = uuidString, let existingUUID = UUID(uuidString: uuidString) {
                uuid = existingUUID
                print("[Auth] 🔍 User UUID from Firestore: \(uuidString)")
            } else {
                // UUID missing - generate and store it
                uuid = uuidFromFirebaseUID(user.uid)
                print("[Auth] ⚠️ UUID missing in Firestore, generated: \(uuid)")

                // Update Firestore with the UUID
                try? await userRef.setData(["id": uuid.uuidString], merge: true)
                print("[Auth] ✅ Saved UUID to Firestore")
            }

            let friend = Friend(
                id: uuid,
                name: displayName,
                avatarURL: photoURL
            )

            // Use San Francisco coordinates as default location
            // In production, you would request actual location permissions
            let location = CLLocation(latitude: 37.7749, longitude: -122.4194)

            currentSession = UserSession(user: friend, currentLocation: location, firebaseUID: user.uid)

            print("[Auth] ✅ Created session for user: \(user.uid), name: \(displayName)")

            // Register FCM token after successful login
            await registerFCMToken(for: user.uid)
        } catch {
            print("[Auth] ⚠️ Error fetching user profile: \(error)")

            // Fallback: create session with Firebase Auth data
            let uuid = uuidFromFirebaseUID(user.uid)
            let displayName = user.displayName
                           ?? user.email?.components(separatedBy: "@").first
                           ?? "User"
            let friend = Friend(
                id: uuid,
                name: displayName,
                avatarURL: nil
            )
            let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
            currentSession = UserSession(user: friend, currentLocation: location, firebaseUID: user.uid)

            print("[Auth] ✅ Created fallback session for user: \(user.uid)")

            // Register FCM token after successful login
            await registerFCMToken(for: user.uid)
        }
        #else
        // For preview/testing without Firebase
        let uuid = uuidFromFirebaseUID(user.uid)
        let friend = Friend(
            id: uuid,
            name: user.displayName ?? "User",
            avatarURL: nil
        )
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        currentSession = UserSession(user: friend, currentLocation: location)
        #endif
    }

    func signOut() {
        print("[Auth] 🔓 Signing out user: \(currentSession?.firebaseUID ?? "unknown")")

        #if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
            print("[Auth] ✅ Firebase sign out successful")
        } catch {
            print("[Auth] ❌ Error signing out: \(error)")
        }
        #endif

        // Clear the current session
        currentSession = nil
        print("[Auth] ✅ Session cleared")

        // Clear app state user data and reset onboarding
        appState?.clearUserData()
        appState?.isOnboarded = false
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        print("[Auth] ✅ AppState user data cleared and onboarding reset")
    }

    // Convert Firebase UID (string) to UUID for compatibility with existing code
    private func uuidFromFirebaseUID(_ uid: String) -> UUID {
        // Hash the Firebase UID to create a consistent UUID
        var hasher = Hasher()
        hasher.combine(uid)
        let hash = abs(hasher.finalize())

        // Convert hash to UUID format
        let uuidString = String(format: "%08X-%04X-%04X-%04X-%012X",
                               (hash >> 96) & 0xFFFFFFFF,
                               (hash >> 80) & 0xFFFF,
                               (hash >> 64) & 0xFFFF,
                               (hash >> 48) & 0xFFFF,
                               hash & 0xFFFFFFFFFFFF)

        return UUID(uuidString: uuidString) ?? UUID()
    }

    // Register FCM token for push notifications
    private func registerFCMToken(for uid: String) async {
        #if canImport(FirebaseMessaging) && canImport(FirebaseFirestore)
        do {
            let fcmToken = try await Messaging.messaging().token()
            print("[Auth] 🟢 Got FCM token: \(fcmToken)")

            let db = Firestore.firestore()
            try await db.collection("users").document(uid).setData([
                "pushTokens": FieldValue.arrayUnion([fcmToken])
            ], merge: true)

            print("[Auth] ✅ FCM token registered for user: \(uid)")
        } catch {
            print("[Auth] ❌ Error registering FCM token: \(error.localizedDescription)")
        }
        #endif
    }
}
