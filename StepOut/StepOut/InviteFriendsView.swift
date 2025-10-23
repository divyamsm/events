import SwiftUI
import Contacts

struct InviteFriendsView: View {
    @StateObject private var contactsManager = ContactsManager()
    @State private var searchText = ""
    @Environment(\.dismiss) var dismiss

    var filteredContacts: [AppContact] {
        if searchText.isEmpty {
            return contactsManager.contacts
        }
        return contactsManager.contacts.filter { contact in
            let fullName = "\(contact.contact.givenName) \(contact.contact.familyName)".lowercased()
            return fullName.contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                if contactsManager.permissionStatus == .notDetermined || contactsManager.permissionStatus == .denied {
                    permissionView
                } else if contactsManager.isLoading {
                    ProgressView("Loading contacts...")
                } else if contactsManager.contacts.isEmpty {
                    emptyView
                } else {
                    contactsList
                }
            }
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .onAppear {
                contactsManager.checkPermission()
            }
        }
    }

    private var permissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                Text("Access Your Contacts")
                    .font(.title2.bold())

                Text("Find friends who are already using StepOut and invite others to join")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(action: {
                Task {
                    let granted = await contactsManager.requestPermission()
                    if granted {
                        await contactsManager.fetchContacts()
                    }
                }
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Allow Access")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Text("We'll never spam your contacts or share their info")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Contacts Found")
                .font(.headline)

            Text("Make sure you have contacts saved on your device")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var contactsList: some View {
        List {
            // App Users Section
            let appUsers = filteredContacts.filter { $0.isAppUser }
            if !appUsers.isEmpty {
                Section {
                    ForEach(appUsers) { appContact in
                        ContactRow(appContact: appContact, contactsManager: contactsManager)
                    }
                } header: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("On StepOut (\(appUsers.count))")
                    }
                }
            }

            // Non-App Users Section
            let nonAppUsers = filteredContacts.filter { !$0.isAppUser }
            if !nonAppUsers.isEmpty {
                Section {
                    ForEach(nonAppUsers) { appContact in
                        ContactRow(appContact: appContact, contactsManager: contactsManager)
                    }
                } header: {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Invite to StepOut (\(nonAppUsers.count))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct ContactRow: View {
    let appContact: AppContact
    let contactsManager: ContactsManager

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)

                if let imageData = appContact.contact.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    Text(initials)
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }

            // Name and Status
            VStack(alignment: .leading, spacing: 4) {
                Text(fullName)
                    .font(.headline)

                if appContact.isAppUser {
                    if let displayName = appContact.displayName {
                        Text("@\(displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("On StepOut")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                } else {
                    Text(contactInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action Button
            if appContact.isAppUser {
                // Add Friend button (placeholder)
                Button(action: {
                    // TODO: Implement add friend functionality
                }) {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
            } else {
                // Invite button
                Button(action: {
                    contactsManager.shareInviteLink(for: appContact.contact)
                }) {
                    Text("Invite")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var fullName: String {
        "\(appContact.contact.givenName) \(appContact.contact.familyName)".trimmingCharacters(in: .whitespaces)
    }

    private var initials: String {
        let first = appContact.contact.givenName.prefix(1)
        let last = appContact.contact.familyName.prefix(1)
        return "\(first)\(last)".uppercased()
    }

    private var contactInfo: String {
        if let phone = appContact.contact.phoneNumbers.first {
            return phone.value.stringValue
        } else if let email = appContact.contact.emailAddresses.first {
            return String(email.value)
        }
        return "No contact info"
    }
}

#Preview {
    InviteFriendsView()
}
