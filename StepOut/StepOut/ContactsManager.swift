import Foundation
import Contacts
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

struct AppContact: Identifiable {
    let id = UUID()
    let contact: CNContact
    let isAppUser: Bool
    let userId: String?
    let displayName: String?
}

@MainActor
class ContactsManager: ObservableObject {
    @Published var contacts: [AppContact] = []
    @Published var isLoading = false
    @Published var permissionStatus: CNAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var outgoingRequestsMap: [String: String] = [:] // recipientUserId -> inviteId
    @Published var friendsSet: Set<String> = [] // Set of friend userIds

    private let contactStore = CNContactStore()
    private let db = Firestore.firestore()
    private var outgoingRequestsListener: ListenerRegistration?
    private var friendsListener: ListenerRegistration?

    init() {
        print("[Contacts] 🔵 ContactsManager initialized")
    }

    deinit {
        outgoingRequestsListener?.remove()
        friendsListener?.remove()
    }

    func startListeningToOutgoingRequests(currentUserId: String) {
        print("[Contacts] 🎧 Starting listener for outgoing requests")

        // Real-time listener for all outgoing pending requests
        outgoingRequestsListener = db.collection("invites")
            .whereField("senderId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("[Contacts] ❌ Error listening to outgoing requests: \(error)")
                    return
                }

                guard let documents = snapshot?.documents else { return }

                Task { @MainActor in
                    var requestsMap: [String: String] = [:]

                    for doc in documents {
                        let data = doc.data()
                        if let recipientId = data["recipientUserId"] as? String {
                            requestsMap[recipientId] = doc.documentID
                        }
                    }

                    self.outgoingRequestsMap = requestsMap
                    print("[Contacts] 📊 Outgoing requests updated: \(requestsMap.count) pending")
                }
            }
    }

    func stopListeningToOutgoingRequests() {
        outgoingRequestsListener?.remove()
        outgoingRequestsListener = nil
    }

    func startListeningToFriends(currentUserId: String) {
        print("[Contacts] 🎧 Starting listener for friends")

        // Real-time listener for all friends
        friendsListener = db.collection("friends")
            .whereField("userId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("[Contacts] ❌ Error listening to friends: \(error)")
                    return
                }

                guard let documents = snapshot?.documents else { return }

                Task { @MainActor in
                    var friendsSet = Set<String>()

                    for doc in documents {
                        let data = doc.data()
                        if let friendId = data["friendId"] as? String {
                            friendsSet.insert(friendId)
                        }
                    }

                    self.friendsSet = friendsSet
                    print("[Contacts] 📊 Friends updated: \(friendsSet.count) friends")
                }
            }
    }

    func stopListeningToFriends() {
        friendsListener?.remove()
        friendsListener = nil
    }

    func isFriend(userId: String) -> Bool {
        return friendsSet.contains(userId)
    }

    func unfriend(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ContactsManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        print("[Contacts] Unfriending user: \(userId)")

        do {
            // Find and delete both friendship documents
            let friendsQuery1 = try await db.collection("friends")
                .whereField("userId", isEqualTo: currentUserId)
                .whereField("friendId", isEqualTo: userId)
                .whereField("status", isEqualTo: "active")
                .getDocuments()

            let friendsQuery2 = try await db.collection("friends")
                .whereField("userId", isEqualTo: userId)
                .whereField("friendId", isEqualTo: currentUserId)
                .whereField("status", isEqualTo: "active")
                .getDocuments()

            for doc in friendsQuery1.documents {
                try await doc.reference.delete()
            }

            for doc in friendsQuery2.documents {
                try await doc.reference.delete()
            }

            print("[Contacts] ✅ Unfriended successfully")
            // The real-time listener will automatically update friendsSet
        } catch {
            print("[Contacts] ❌ Error unfriending: \(error)")
            throw error
        }
    }

    func checkPermission() {
        permissionStatus = CNContactStore.authorizationStatus(for: .contacts)
        print("[Contacts] 🔵 checkPermission() called, status: \(permissionStatus.rawValue)")
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            await MainActor.run {
                permissionStatus = granted ? .authorized : .denied
            }
            print("[Contacts] Permission requested, granted: \(granted), status: \(permissionStatus.rawValue)")
            return granted
        } catch {
            print("[Contacts] Error requesting permission: \(error)")
            await MainActor.run {
                permissionStatus = .denied
            }
            return false
        }
    }

    func fetchContacts() async {
        guard permissionStatus == .authorized else {
            await MainActor.run {
                errorMessage = "Contacts permission not granted"
            }
            print("[Contacts] ❌ Cannot fetch - permission status: \(permissionStatus.rawValue)")
            return
        }

        print("[Contacts] ✅ Starting fetch, permission: \(permissionStatus.rawValue)")

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        let keysToFetch = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactImageDataKey
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)

        // Fetch contacts on background thread to avoid blocking UI
        let fetchedContacts: [CNContact] = await Task.detached(priority: .userInitiated) {
            var contacts: [CNContact] = []
            do {
                try self.contactStore.enumerateContacts(with: request) { contact, _ in
                    contacts.append(contact)
                }
                print("[Contacts] Fetched \(contacts.count) contacts from device")
            } catch {
                print("[Contacts] ❌ Error enumerating contacts: \(error)")
            }
            return contacts
        }.value

        // Match with app users
        await matchWithAppUsers(contacts: fetchedContacts)

        await MainActor.run {
            isLoading = false
        }
    }

    private func matchWithAppUsers(contacts: [CNContact]) async {
        // Get current user ID to filter them out
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("[Contacts] ❌ No current user, cannot filter")
            return
        }

        // Extract phone numbers and emails with all variants
        var contactPhoneVariants: [String: Set<String>] = [:] // contactId -> phone variants
        var emails: Set<String> = []

        for contact in contacts {
            let contactKey = "\(contact.identifier)"
            var allVariants = Set<String>()

            for phone in contact.phoneNumbers {
                let variants = normalizePhoneNumber(phone.value.stringValue)
                allVariants.formUnion(variants)
            }

            if !allVariants.isEmpty {
                contactPhoneVariants[contactKey] = allVariants
            }

            for email in contact.emailAddresses {
                emails.insert(String(email.value).lowercased())
            }
        }

        // Query Firestore for matching users
        var appUserEmails: Set<String> = []
        var appUserPhoneVariants: Set<String> = [] // All phone variants from app users
        var emailToUserId: [String: String] = [:]
        var phoneToUserId: [String: String] = [:] // Any variant -> userId

        do {
            // Query by emails (Firestore doesn't support 'in' for large arrays, so we'll do simplified matching)
            let usersSnapshot = try await db.collection("users").limit(to: 500).getDocuments()

            for doc in usersSnapshot.documents {
                let data = doc.data()
                if let email = data["email"] as? String {
                    appUserEmails.insert(email.lowercased())
                    emailToUserId[email.lowercased()] = doc.documentID
                }
                if let phone = data["phoneNumber"] as? String {
                    // Store all variants of this phone number
                    let variants = normalizePhoneNumber(phone)
                    appUserPhoneVariants.formUnion(variants)

                    // Map all variants to this user ID
                    for variant in variants {
                        phoneToUserId[variant] = doc.documentID
                    }
                }
            }

            // Create AppContact objects
            var appContacts: [AppContact] = []

            for contact in contacts {
                var isAppUser = false
                var userId: String?
                var displayName: String?

                // Check if email matches
                for email in contact.emailAddresses {
                    let emailStr = String(email.value).lowercased()
                    if appUserEmails.contains(emailStr) {
                        isAppUser = true
                        userId = emailToUserId[emailStr]

                        // Fetch display name from Firestore
                        if let uid = userId {
                            let userDoc = try? await db.collection("users").document(uid).getDocument()
                            displayName = userDoc?.data()?["displayName"] as? String
                        }
                        break
                    }
                }

                // Check if phone matches (using variants)
                if !isAppUser {
                    let contactKey = "\(contact.identifier)"
                    if let phoneVariants = contactPhoneVariants[contactKey] {
                        // Check if ANY variant matches ANY app user phone variant
                        for variant in phoneVariants {
                            if appUserPhoneVariants.contains(variant) {
                                isAppUser = true
                                userId = phoneToUserId[variant]

                                // Fetch display name if we have userId
                                if let uid = userId {
                                    let userDoc = try? await db.collection("users").document(uid).getDocument()
                                    displayName = userDoc?.data()?["displayName"] as? String
                                }
                                print("[Contacts] ✅ Matched phone variant '\(variant)' for contact \(contact.givenName) \(contact.familyName)")
                                break
                            }
                        }
                    }
                }

                // Filter out current user's own contact
                if let uid = userId, uid == currentUserId {
                    print("[Contacts] 🚫 Filtering out own contact: \(contact.givenName) \(contact.familyName)")
                    continue
                }

                appContacts.append(AppContact(
                    contact: contact,
                    isAppUser: isAppUser,
                    userId: userId,
                    displayName: displayName
                ))
            }

            // Sort: app users first
            let sortedContacts = appContacts.sorted { $0.isAppUser && !$1.isAppUser }

            await MainActor.run {
                self.contacts = sortedContacts
            }

            print("[Contacts] Total contacts: \(sortedContacts.count), App users: \(appContacts.filter { $0.isAppUser }.count)")

        } catch {
            print("[Contacts] Error matching users: \(error)")
        }
    }

    private func cleanPhoneNumber(_ phone: String) -> String {
        // Remove all non-digits
        let digitsOnly = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        // If it starts with country code (1 for US), also return version without it
        // This handles cases where some users have +1 and some don't
        return digitsOnly
    }

    private func normalizePhoneNumber(_ phone: String) -> Set<String> {
        // Remove all non-digits
        let digitsOnly = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        var variants = Set<String>()
        variants.insert(digitsOnly)

        // If it's a US number (11 digits starting with 1), also add the 10-digit version
        if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            let without1 = String(digitsOnly.dropFirst())
            variants.insert(without1)
        }

        // If it's a 10-digit number, also add the version with country code
        if digitsOnly.count == 10 {
            variants.insert("1" + digitsOnly)
        }

        return variants
    }

    func sendFriendRequest(to userId: String) async throws {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions()
        let callable = functions.httpsCallable("sendFriendRequest")

        print("[Contacts] Sending friend request to: \(userId)")

        do {
            let result = try await callable.call(["recipientUserId": userId])
            print("[Contacts] Friend request sent successfully: \(result.data)")
            // The real-time listener will automatically update outgoingRequestsMap
        } catch {
            print("[Contacts] Error sending friend request: \(error)")
            throw error
        }
        #endif
    }

    func isPending(userId: String) -> Bool {
        return outgoingRequestsMap.keys.contains(userId)
    }

    func cancelFriendRequest(to userId: String) async throws {
        guard let inviteId = outgoingRequestsMap[userId] else {
            print("[Contacts] ❌ No pending request found for userId: \(userId)")
            return
        }

        print("[Contacts] Canceling friend request: \(inviteId)")

        do {
            try await db.collection("invites").document(inviteId).delete()
            print("[Contacts] ✅ Friend request cancelled")
            // The real-time listener will automatically update outgoingRequestsMap
        } catch {
            print("[Contacts] ❌ Error canceling request: \(error)")
            throw error
        }
    }

    func shareInviteLink(for contact: CNContact) {
        let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        let message = """
        Hey \(name)! 👋

        I'm using StepOut to discover and share events with friends. Join me!

        Download: https://stepout.app/invite

        See you there! 🎉
        """

        // Create activity view controller
        let activityVC = UIActivityViewController(
            activityItems: [message],
            applicationActivities: nil
        )

        // Present it on the topmost view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            topController.present(activityVC, animated: true)
        }
    }
}
