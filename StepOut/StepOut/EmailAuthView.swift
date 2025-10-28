import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EmailAuthView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var username = ""
    @State private var phoneNumber = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var showPassword = false
    @State private var showVerificationView = false
    @State private var verificationSent = false
    @State private var canResend = false
    @State private var resendCountdown = 0
    @State private var pendingUser: User?
    @State private var showEventPreferences = false
    @State private var userNeedsOnboarding = true

    var onSignedIn: (User) -> Void

    var body: some View {
        ZStack {
            // Gradient Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if showEventPreferences {
                EventPreferencesView(isOnboarding: true) { preferences in
                    // Preferences saved, now sign in
                    if let user = pendingUser {
                        onSignedIn(user)
                    }
                }
            } else if showVerificationView {
                EmailVerificationView(
                    email: email,
                    user: pendingUser,
                    canResend: $canResend,
                    resendCountdown: $resendCountdown,
                    onVerified: { user in
                        // User verified, create profile and show preferences
                        Task {
                            await createUserProfile(user: user, displayName: displayName, username: username)
                            // Show event preferences onboarding
                            showVerificationView = false
                            showEventPreferences = true
                        }
                    },
                    onResend: {
                        Task {
                            await resendVerificationEmail()
                        }
                    },
                    onCancel: {
                        showVerificationView = false
                        // Delete the unverified account
                        Task {
                            try? await pendingUser?.delete()
                            pendingUser = nil
                        }
                    }
                )
            } else {
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer().frame(height: 40)

                        // Logo/Title
                        VStack(spacing: 16) {
                            Image(systemName: "figure.walk.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Text("StepOut")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.white)

                            Text(isSignUp ? "Create your account" : "Welcome back!")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.bottom, 20)

                        // Auth Form
                        VStack(spacing: 24) {
                            if isSignUp {
                                signUpForm
                            } else {
                                signInForm
                            }

                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(12)
                                .transition(.scale.combined(with: .opacity))
                            }

                            // Action Button
                            Button(action: { Task { await handleAuth() } }) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text(isSignUp ? "Create Account" : "Sign In")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: isFormValid ? [.blue, .purple] : [.gray, .gray],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: isFormValid ? .blue.opacity(0.5) : .clear, radius: 10, y: 5)
                            }
                            .disabled(!isFormValid || isLoading)
                            .animation(.easeInOut, value: isFormValid)

                            // Forgot Password (only show when signing in)
                            if !isSignUp {
                                Button(action: { Task { await handleForgotPassword() } }) {
                                    Text("Forgot Password?")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                                .padding(.top, 4)
                            }

                            // Toggle between Sign In and Sign Up
                            Button(action: {
                                withAnimation(.spring()) {
                                    isSignUp.toggle()
                                    errorMessage = nil
                                    clearFields()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                        .foregroundColor(.white.opacity(0.7))
                                    Text(isSignUp ? "Sign In" : "Sign Up")
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                                .font(.subheadline)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 32)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
    }

    // MARK: - Sign In Form
    private var signInForm: some View {
        VStack(spacing: 20) {
            // Email Field
            FormField(
                title: "Email Address",
                placeholder: "your.email@domain.com",
                text: $email,
                keyboardType: .emailAddress,
                validation: emailValidation
            )

            // Password Field
            PasswordFormField(
                title: "Password",
                placeholder: "Enter your password",
                text: $password,
                showPassword: $showPassword,
                showToggle: true
            )
        }
    }

    // MARK: - Sign Up Form
    private var signUpForm: some View {
        VStack(spacing: 20) {
            // Email Field
            FormField(
                title: "Email Address",
                placeholder: "your.email@domain.com",
                text: $email,
                keyboardType: .emailAddress,
                validation: emailValidation
            )

            // Display Name Field
            FormField(
                title: "Full Name",
                placeholder: "John Doe",
                text: $displayName,
                validation: nameValidation
            )

            // Username Field
            UsernameFormField(
                text: $username,
                isChecking: $isCheckingUsername,
                isAvailable: $usernameAvailable,
                onCheck: checkUsernameAvailability
            )

            // Phone Number Field
            FormField(
                title: "Phone Number",
                placeholder: "+12137065381",
                text: $phoneNumber,
                validation: phoneValidation
            )
            .keyboardType(.phonePad)
            .textInputAutocapitalization(.never)

            // Password Field
            PasswordFormField(
                title: "Password",
                placeholder: "Create a strong password",
                text: $password,
                showPassword: $showPassword,
                showToggle: true,
                validation: passwordValidation,
                isSignUp: true
            )

            // Confirm Password Field
            PasswordFormField(
                title: "Confirm Password",
                placeholder: "Re-enter your password",
                text: $confirmPassword,
                showPassword: $showPassword,
                showToggle: false,
                validation: confirmPasswordValidation
            )
        }
    }

    // MARK: - Validation Logic
    private var emailValidation: ValidationResult {
        if email.isEmpty {
            return .idle
        }
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email) ? .valid : .invalid("Please enter a valid email")
    }

    private var nameValidation: ValidationResult {
        if displayName.isEmpty {
            return .idle
        }
        return displayName.count >= 2 ? .valid : .invalid("Name must be at least 2 characters")
    }

    private var phoneValidation: ValidationResult {
        if phoneNumber.isEmpty {
            return .idle
        }
        // E.164 format: +[country code][number]
        let phoneRegex = "^\\+[1-9]\\d{1,14}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return predicate.evaluate(with: phoneNumber) ? .valid : .invalid("Use format: +12137065381")
    }

    private var passwordValidation: ValidationResult {
        if password.isEmpty {
            return .idle
        }

        var errors: [String] = []

        if password.count < 8 {
            errors.append("8+ characters")
        }
        if !password.contains(where: { $0.isUppercase }) {
            errors.append("uppercase letter")
        }
        if !password.contains(where: { $0.isLowercase }) {
            errors.append("lowercase letter")
        }
        if !password.contains(where: { $0.isNumber }) {
            errors.append("number")
        }
        if !password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }) {
            errors.append("special character")
        }

        if errors.isEmpty {
            return .valid
        } else {
            return .invalid("Missing: " + errors.joined(separator: ", "))
        }
    }

    private var confirmPasswordValidation: ValidationResult {
        if confirmPassword.isEmpty {
            return .idle
        }
        return password == confirmPassword ? .valid : .invalid("Passwords don't match")
    }

    private var isFormValid: Bool {
        if isSignUp {
            return emailValidation == .valid &&
                   nameValidation == .valid &&
                   passwordValidation == .valid &&
                   confirmPasswordValidation == .valid &&
                   !username.isEmpty &&
                   usernameAvailable == true
        } else {
            return emailValidation == .valid && !password.isEmpty
        }
    }

    // MARK: - Username Availability Check
    private func checkUsernameAvailability() async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 3 else {
            usernameAvailable = nil
            return
        }

        isCheckingUsername = true
        usernameAvailable = nil

        // Add a small delay to avoid excessive checks
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let db = Firestore.firestore()

        do {
            let snapshot = try await db.collection("usernames").document(trimmed).getDocument()
            usernameAvailable = !snapshot.exists
        } catch {
            print("[Auth] Error checking username: \(error)")
            usernameAvailable = nil
        }

        isCheckingUsername = false
    }

    // MARK: - Authentication Handler
    private func handleAuth() async {
        errorMessage = nil
        isLoading = true

        do {
            let result: AuthDataResult

            if isSignUp {
                // Create new account
                result = try await Auth.auth().createUser(withEmail: email, password: password)
                print("[Auth] Created new user: \(result.user.uid)")

                // Update display name
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()

                // Create user profile immediately after signup
                await createUserProfile(user: result.user, displayName: displayName, username: username)
                print("[Auth] Created user profile in Firestore")

                // Send email verification
                try await result.user.sendEmailVerification()
                print("[Auth] Verification email sent to \(email)")

                isLoading = false

                // Store pending user and show verification screen
                pendingUser = result.user
                showVerificationView = true
                startResendTimer()

            } else {
                // Sign in existing user
                result = try await Auth.auth().signIn(withEmail: email, password: password)
                print("[Auth] Signed in user: \(result.user.uid)")

                // Reload to get latest email verification status
                try await result.user.reload()

                // Check if email verification is required (production mode)
                // TEMPORARILY DISABLED for development - re-enable for production
                /*
                if !result.user.isEmailVerified {
                    errorMessage = "Please verify your email first. Check your inbox."
                    try? await Auth.auth().signOut()
                    isLoading = false
                    return
                }
                */

                // Create profile if it doesn't exist (for existing users)
                let db = Firestore.firestore()
                let userDoc = try? await db.collection("users").document(result.user.uid).getDocument()
                if userDoc?.exists != true {
                    print("[Auth] User document doesn't exist, creating profile")
                    await createUserProfile(
                        user: result.user,
                        displayName: result.user.displayName ?? result.user.email?.components(separatedBy: "@").first ?? "User",
                        username: "user\(result.user.uid.prefix(8))"
                    )
                }

                isLoading = false
                onSignedIn(result.user)
            }

        } catch let error as NSError {
            isLoading = false

            // Handle specific Firebase auth errors
            if let authError = AuthErrorCode(_bridgedNSError: error) {
                switch authError.code {
                case .invalidEmail:
                    errorMessage = "Please enter a valid email address"
                case .wrongPassword:
                    errorMessage = "Incorrect email or password"
                case .userNotFound:
                    errorMessage = "Incorrect email or password"
                case .emailAlreadyInUse:
                    errorMessage = "This email is already registered"
                case .weakPassword:
                    errorMessage = "Password is too weak. Use a stronger password"
                case .networkError:
                    errorMessage = "Network error. Check your connection"
                case .tooManyRequests:
                    errorMessage = "Too many attempts. Please try again later"
                case .invalidCredential:
                    errorMessage = "Incorrect email or password"
                default:
                    // Don't show technical errors to users
                    errorMessage = "Authentication failed. Please check your credentials and try again"
                }
            } else {
                errorMessage = error.localizedDescription
            }

            print("[Auth] Error: \(error.localizedDescription)")
        }
    }

    private func resendVerificationEmail() async {
        guard let user = pendingUser else { return }

        do {
            try await user.sendEmailVerification()
            print("[Auth] Verification email resent")
            startResendTimer()
        } catch {
            print("[Auth] Error resending verification: \(error)")
        }
    }

    private func startResendTimer() {
        canResend = false
        resendCountdown = 60

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                canResend = true
                timer.invalidate()
            }
        }
    }

    private func createUserProfile(user: User, displayName: String, username: String) async {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        let usernameRef = db.collection("usernames").document(username.lowercased())

        do {
            // Use batch write to ensure both documents are created atomically
            let batch = db.batch()

            // Create user profile
            var profileData: [String: Any] = [
                "email": user.email ?? "",
                "displayName": displayName,
                "username": username.lowercased(),
                "photoURL": NSNull(),
                "emailVerified": true,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            // Add phone number if provided
            if !phoneNumber.isEmpty {
                profileData["phoneNumber"] = phoneNumber
            }

            batch.setData(profileData, forDocument: userRef)

            // Reserve username
            batch.setData([
                "uid": user.uid,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: usernameRef)

            try await batch.commit()

            print("[Auth] Created user profile and reserved username for \(user.uid)")
        } catch {
            print("[Auth] Error creating user profile: \(error)")
        }
    }

    private func clearFields() {
        email = ""
        password = ""
        confirmPassword = ""
        displayName = ""
        username = ""
        phoneNumber = ""
        usernameAvailable = nil
    }

    private func handleForgotPassword() async {
        guard !email.isEmpty else {
            errorMessage = "Please enter your email address first"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            errorMessage = "Password reset email sent! Check your inbox."
            isLoading = false
        } catch {
            errorMessage = "Failed to send reset email. Please check your email address."
            isLoading = false
        }
    }
}

// MARK: - Email Verification View
struct EmailVerificationView: View {
    let email: String
    let user: User?
    @Binding var canResend: Bool
    @Binding var resendCountdown: Int
    let onVerified: (User) -> Void
    let onResend: () -> Void
    let onCancel: () -> Void

    @State private var isChecking = false
    @State private var checkMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "envelope.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Title & Instructions
            VStack(spacing: 12) {
                Text("Verify Your Email")
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text("We've sent a verification link to")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Text(email)
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                Text("Click the link in the email to verify your account, then tap 'I've Verified' below.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

            if let message = checkMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(message.contains("verified") ? .green : .orange)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .transition(.opacity)
            }

            // Action Buttons
            VStack(spacing: 16) {
                // Check Verification Button
                Button(action: { Task { await checkVerification() } }) {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("I've Verified My Email")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .green.opacity(0.5), radius: 10, y: 5)
                }
                .disabled(isChecking)

                // Resend Button
                Button(action: onResend) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        if canResend {
                            Text("Resend Verification Email")
                        } else {
                            Text("Resend in \(resendCountdown)s")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(canResend ? .blue : .white.opacity(0.5))
                }
                .disabled(!canResend)

                // Cancel Button
                Button(action: onCancel) {
                    Text("Cancel & Go Back")
                        .font(.subheadline)
                        .foregroundColor(.red.opacity(0.8))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 32)

            Spacer()

            // Help Text
            VStack(spacing: 8) {
                Text("Didn't receive the email?")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                Text("Check your spam folder or request a new one")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.bottom, 40)
        }
        .animation(.easeInOut, value: checkMessage)
    }

    private func checkVerification() async {
        guard let user = user else { return }

        isChecking = true
        checkMessage = nil

        do {
            // Reload user to get latest email verification status
            try await user.reload()

            if user.isEmailVerified {
                checkMessage = "Email verified successfully!"
                try? await Task.sleep(nanoseconds: 500_000_000)
                onVerified(user)
            } else {
                checkMessage = "Email not verified yet. Please check your inbox and click the verification link."
            }

            isChecking = false
        } catch {
            isChecking = false
            checkMessage = "Error checking verification. Please try again."
            print("[Auth] Error checking verification: \(error)")
        }
    }
}

// MARK: - Validation Result
enum ValidationResult: Equatable {
    case idle
    case valid
    case invalid(String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

// MARK: - Form Field Component
struct FormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var validation: ValidationResult = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            HStack {
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                    .keyboardType(keyboardType)
                    .autocapitalization(keyboardType == .emailAddress ? .none : .words)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)

                if case .valid = validation {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .padding(.trailing, 16)
                } else if case .invalid = validation {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .padding(.trailing, 16)
                }
            }
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )

            if case .invalid(let message) = validation {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text(message)
                }
                .font(.caption)
                .foregroundColor(.red.opacity(0.9))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: validation)
    }

    private var borderColor: Color {
        switch validation {
        case .valid:
            return .green.opacity(0.5)
        case .invalid:
            return .red.opacity(0.5)
        case .idle:
            return .clear
        }
    }
}

// MARK: - Password Form Field
struct PasswordFormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    var showToggle: Bool = true
    var validation: ValidationResult = .idle
    var isSignUp: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            HStack {
                if showPassword {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                        .font(.body)
                        .foregroundColor(.white)
                        .autocapitalization(.none)
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                        .font(.body)
                        .foregroundColor(.white)
                        .autocapitalization(.none)
                }

                if showToggle {
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                if case .valid = validation {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if case .invalid = validation {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )

            if isSignUp && !text.isEmpty {
                PasswordStrengthIndicator(password: text)
            }

            if case .invalid(let message) = validation {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text(message)
                }
                .font(.caption)
                .foregroundColor(.red.opacity(0.9))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: validation)
    }

    private var borderColor: Color {
        switch validation {
        case .valid:
            return .green.opacity(0.5)
        case .invalid:
            return .red.opacity(0.5)
        case .idle:
            return .clear
        }
    }
}

// MARK: - Username Form Field
struct UsernameFormField: View {
    @Binding var text: String
    @Binding var isChecking: Bool
    @Binding var isAvailable: Bool?
    let onCheck: () async -> Void

    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Username")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            HStack {
                Text("@")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.body)

                TextField("", text: $text, prompt: Text("username").foregroundColor(.white.opacity(0.3)))
                    .font(.body)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .onChange(of: text) { newValue in
                        // Only allow alphanumeric and underscore
                        let filtered = newValue.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                        if filtered != newValue {
                            text = filtered
                        }

                        // Debounce username check
                        debounceTask?.cancel()
                        debounceTask = Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            if !Task.isCancelled {
                                await onCheck()
                            }
                        }
                    }

                if isChecking {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let available = isAvailable {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(available ? .green : .red)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )

            if text.count > 0 && text.count < 3 {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("Username must be at least 3 characters")
                }
                .font(.caption)
                .foregroundColor(.orange.opacity(0.9))
            } else if let available = isAvailable, !available {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("This username is already taken")
                }
                .font(.caption)
                .foregroundColor(.red.opacity(0.9))
            } else if let available = isAvailable, available {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                    Text("Username is available!")
                }
                .font(.caption)
                .foregroundColor(.green.opacity(0.9))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAvailable)
    }

    private var borderColor: Color {
        if let available = isAvailable {
            return available ? .green.opacity(0.5) : .red.opacity(0.5)
        }
        return .clear
    }
}

// MARK: - Password Strength Indicator
struct PasswordStrengthIndicator: View {
    let password: String

    private var strength: (level: Int, color: Color, text: String) {
        var score = 0

        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.contains(where: { $0.isUppercase }) { score += 1 }
        if password.contains(where: { $0.isLowercase }) { score += 1 }
        if password.contains(where: { $0.isNumber }) { score += 1 }
        if password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }) { score += 1 }

        switch score {
        case 0...2:
            return (1, .red, "Weak")
        case 3...4:
            return (2, .orange, "Medium")
        case 5:
            return (3, .yellow, "Good")
        default:
            return (4, .green, "Strong")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index < strength.level ? strength.color : Color.white.opacity(0.2))
                        .frame(height: 4)
                }
            }

            Text("Password strength: \(strength.text)")
                .font(.caption)
                .foregroundColor(strength.color)
        }
    }
}

#Preview {
    EmailAuthView { user in
        print("Signed in as \(user.uid)")
    }
}
