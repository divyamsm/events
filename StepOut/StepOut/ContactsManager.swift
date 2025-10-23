import Foundation
import Contacts
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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

    func checkPermission() {
        permissionStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            permissionStatus = granted ? .authorized : .denied
            return granted
        } catch {
            print("[Contacts] Error requesting permission: \(error)")
            permissionStatus = .denied
            return false
        }
    }

    func fetchContacts() async {
        guard permissionStatus == .authorized else {
            errorMessage = "Contacts permission not granted"
            return
        }

        isLoading = true
        errorMessage = nil

        let keysToFetch = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactImageDataKey
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)

        var fetchedContacts: [CNContact] = []

        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                fetchedContacts.append(contact)
            }

            print("[Contacts] Fetched \(fetchedContacts.count) contacts")

            // Match with app users
            await matchWithAppUsers(contacts: fetchedContacts)

            isLoading = false
        } catch {
            print("[Contacts] Error fetching: \(error)")
            errorMessage = "Failed to fetch contacts"
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
            self.contacts = appContacts.sorted { $0.isAppUser && !$1.isAppUser }

            print("[Contacts] Matched \(appContacts.filter { $0.isAppUser }.count) app users")

        } catch {
            print("[Contacts] Error matching users: \(error)")
        }
    }

    private func cleanPhoneNumber(_ phone: String) -> String {
        return phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
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

        // Present it
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}
