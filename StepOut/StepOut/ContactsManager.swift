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

    private let contactStore = CNContactStore()
    private let db = Firestore.firestore()

    init() {
        print("[Contacts] 🔵 ContactsManager initialized")
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
        // Extract phone numbers and emails
        var phoneNumbers: Set<String> = []
        var emails: Set<String> = []

        for contact in contacts {
            for phone in contact.phoneNumbers {
                let cleaned = cleanPhoneNumber(phone.value.stringValue)
                phoneNumbers.insert(cleaned)
            }

            for email in contact.emailAddresses {
                emails.insert(String(email.value).lowercased())
            }
        }

        // Query Firestore for matching users
        var appUserEmails: Set<String> = []
        var appUserPhones: Set<String> = []
        var emailToUserId: [String: String] = [:]

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
                    appUserPhones.insert(cleanPhoneNumber(phone))
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

                // Check if phone matches
                if !isAppUser {
                    for phone in contact.phoneNumbers {
                        let cleaned = cleanPhoneNumber(phone.value.stringValue)
                        if appUserPhones.contains(cleaned) {
                            isAppUser = true
                            break
                        }
                    }
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
        return phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }

    func sendFriendRequest(to userId: String) async throws {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions()
        let callable = functions.httpsCallable("sendFriendRequest")

        print("[Contacts] Sending friend request to: \(userId)")

        do {
            let result = try await callable.call(["recipientUserId": userId])
            print("[Contacts] Friend request sent successfully: \(result.data)")
        } catch {
            print("[Contacts] Error sending friend request: \(error)")
            throw error
        }
        #endif
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
