import Foundation
import SwiftUI
import CoreLocation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@MainActor
final class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentSession: UserSession?
    @Published var isLoading: Bool = true

    #if canImport(FirebaseAuth)
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    #endif

    init() {
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

            // Convert Firebase UID to UUID by hashing it
            let uuid = uuidFromFirebaseUID(user.uid)

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
        #if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
            print("[Auth] User signed out")
        } catch {
            print("[Auth] Error signing out: \(error)")
        }
        #endif
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
}
