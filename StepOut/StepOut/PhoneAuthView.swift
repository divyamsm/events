import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PhoneAuthView: View {
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var verificationID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingVerification = false

    var onSignedIn: (User) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo/Title
            VStack(spacing: 12) {
                Text("StepOut")
                    .font(.system(size: 48, weight: .bold))
                Text("Connect with friends and discover events")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 40)

            if !showingVerification {
                // Phone Number Entry
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phone Number")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("+1")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)

                            TextField("(555) 123-4567", text: $phoneNumber)
                                .keyboardType(.phonePad)
                                .font(.body)
                                .padding(.vertical, 16)
                                .onChange(of: phoneNumber) { newValue in
                                    phoneNumber = formatPhoneNumber(newValue)
                                }
                        }
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: sendVerificationCode) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Continue")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(phoneNumber.count >= 10 ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(phoneNumber.count < 10 || isLoading)
                }
                .padding(.horizontal, 32)
            } else {
                // Verification Code Entry
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verification Code")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Enter the 6-digit code sent to +1 \(phoneNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("123456", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .onChange(of: verificationCode) { newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                verificationCode = String(filtered.prefix(6))

                                if verificationCode.count == 6 {
                                    Task {
                                        await verifyCode()
                                    }
                                }
                            }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: { Task { await verifyCode() } }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Verify")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(verificationCode.count == 6 ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(verificationCode.count != 6 || isLoading)

                    Button(action: {
                        showingVerification = false
                        verificationCode = ""
                        errorMessage = nil
                    }) {
                        Text("Change phone number")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            // Terms and Privacy
            Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
    }

    private func formatPhoneNumber(_ number: String) -> String {
        // Remove all non-numeric characters
        let digits = number.filter { $0.isNumber }

        // Limit to 10 digits
        let limited = String(digits.prefix(10))

        // Format as (XXX) XXX-XXXX
        var formatted = ""
        for (index, character) in limited.enumerated() {
            if index == 0 {
                formatted += "("
            } else if index == 3 {
                formatted += ") "
            } else if index == 6 {
                formatted += "-"
            }
            formatted.append(character)
        }

        return formatted
    }

    private func sendVerificationCode() {
        errorMessage = nil
        isLoading = true

        // Remove formatting and add country code
        let cleanNumber = "+1" + phoneNumber.filter { $0.isNumber }

        print("[PhoneAuth] Sending verification to: \(cleanNumber)")

        // Simple verification - works with test phone numbers configured in Firebase
        PhoneAuthProvider.provider().verifyPhoneNumber(cleanNumber, uiDelegate: nil) { verificationID, error in
            isLoading = false

            if let error = error {
                print("[PhoneAuth] Error: \(error.localizedDescription)")
                errorMessage = "Failed to send code: \(error.localizedDescription)"
                return
            }

            print("[PhoneAuth] Got verification ID!")
            self.verificationID = verificationID
            showingVerification = true
        }
    }

    private func verifyCode() async {
        guard let verificationID = verificationID else {
            errorMessage = "No verification ID found"
            return
        }

        errorMessage = nil
        isLoading = true

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )

        do {
            let result = try await Auth.auth().signIn(with: credential)
            isLoading = false

            // Create user profile in Firestore if first time
            await createUserProfileIfNeeded(user: result.user)

            onSignedIn(result.user)
        } catch {
            isLoading = false
            errorMessage = "Invalid code. Please try again."
            verificationCode = ""
        }
    }

    private func createUserProfileIfNeeded(user: User) async {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)

        do {
            let doc = try await userRef.getDocument()
            if !doc.exists {
                // Create new user profile
                try await userRef.setData([
                    "phoneNumber": user.phoneNumber ?? "",
                    "displayName": user.phoneNumber ?? "User",
                    "photoURL": nil as String?,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

                print("[Auth] Created new user profile for \(user.uid)")
            }
        } catch {
            print("[Auth] Error creating user profile: \(error)")
        }
    }
}

#Preview {
    PhoneAuthView { user in
        print("Signed in as \(user.uid)")
    }
}
