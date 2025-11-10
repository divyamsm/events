import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Main Modern Onboarding Flow
struct ModernOnboardingFlow: View {
    @State private var currentScreen: OnboardingScreen = .welcome
    @State private var slideTransition: AnyTransition = .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))

    var onComplete: (User) -> Void

    var body: some View {
        ZStack {
            // Beautiful gradient background
            AnimatedGradientBackground()
                .ignoresSafeArea()

            // Screen content
            Group {
                switch currentScreen {
                case .welcome:
                    WelcomeScreen(
                        onLogin: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .login
                            }
                        },
                        onSignUp: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .signUpName
                            }
                        }
                    )
                    .transition(slideTransition)

                case .login:
                    LoginScreen(
                        onBack: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .welcome
                            }
                        },
                        onSuccess: { user in
                            onComplete(user)
                        }
                    )
                    .transition(slideTransition)

                case .signUpName:
                    SignUpNameStep(
                        onBack: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .welcome
                            }
                        },
                        onNext: { name in
                            SignUpFlowState.shared.name = name
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .signUpEmail
                            }
                        }
                    )
                    .transition(slideTransition)

                case .signUpEmail:
                    SignUpEmailStep(
                        onBack: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .signUpName
                            }
                        },
                        onNext: { email, password, username in
                            SignUpFlowState.shared.email = email
                            SignUpFlowState.shared.password = password
                            SignUpFlowState.shared.username = username
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .signUpPhone
                            }
                        }
                    )
                    .transition(slideTransition)

                case .signUpPhone:
                    SignUpPhoneStep(
                        onBack: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .signUpEmail
                            }
                        },
                        onNext: { phone in
                            SignUpFlowState.shared.phone = phone
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .signUpInterests
                            }
                        }
                    )
                    .transition(slideTransition)

                case .signUpInterests:
                    SignUpInterestsStep(
                        onBack: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentScreen = .signUpPhone
                            }
                        },
                        onComplete: { interests, completion in
                            SignUpFlowState.shared.interests = interests
                            Task {
                                await createAccount(completion: completion)
                            }
                        }
                    )
                    .transition(slideTransition)
                }
            }
        }
        .onAppear {
            // Reset signup state when onboarding flow appears
            SignUpFlowState.shared.reset()
        }
    }

    private func createAccount(completion: @escaping (Bool, String?) -> Void) async {
        let state = SignUpFlowState.shared

        do {
            // Create Firebase account
            let result = try await Auth.auth().createUser(withEmail: state.email, password: state.password)

            // Update display name
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = state.name
            try await changeRequest.commitChanges()

            // Generate consistent UUID from Firebase UID
            let uuid = uuidFromFirebaseUID(result.user.uid)

            // Create Firestore profile
            let db = Firestore.firestore()
            let userRef = db.collection("users").document(result.user.uid)
            let usernameRef = db.collection("usernames").document(state.username.lowercased())

            let batch = db.batch()

            var profileData: [String: Any] = [
                "id": uuid.uuidString,  // Store UUID for backend mapping
                "email": state.email,
                "displayName": state.name,
                "username": state.username.lowercased(),
                "phoneNumber": state.phone,
                "emailVerified": false,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            // Add interests as event preferences
            if !state.interests.isEmpty {
                profileData["interests"] = state.interests
            }

            batch.setData(profileData, forDocument: userRef)
            batch.setData([
                "uid": result.user.uid,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: usernameRef)

            try await batch.commit()

            // Success - complete onboarding
            await MainActor.run {
                completion(true, nil)
                onComplete(result.user)
            }

        } catch {
            print("[ModernOnboarding] Error creating account: \(error)")
            let errorMessage = getErrorMessage(from: error)
            await MainActor.run {
                completion(false, errorMessage)
            }
        }
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

    private func getErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "FIRAuthErrorDomain" {
            switch nsError.code {
            case 17007: // ERROR_EMAIL_ALREADY_IN_USE
                return "This email is already registered. Please login instead."
            case 17008: // ERROR_INVALID_EMAIL
                return "Please enter a valid email address."
            case 17026: // ERROR_WEAK_PASSWORD
                return "Password is too weak. Please use a stronger password."
            default:
                break
            }
        }
        return "Failed to create account. Please try again."
    }
}

// MARK: - Onboarding Screens Enum
enum OnboardingScreen {
    case welcome
    case login
    case signUpName
    case signUpEmail
    case signUpPhone
    case signUpInterests
}

// MARK: - Sign Up Flow State
class SignUpFlowState {
    static let shared = SignUpFlowState()

    var name = ""
    var email = ""
    var password = ""
    var username = ""
    var phone = ""
    var interests: [String] = []

    private init() {}

    func reset() {
        name = ""
        email = ""
        password = ""
        username = ""
        phone = ""
        interests = []
    }
}

// MARK: - Animated Gradient Background
struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.1, blue: 0.2),
                Color(red: 0.2, green: 0.1, blue: 0.3),
                Color(red: 0.15, green: 0.15, blue: 0.25)
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Welcome Screen
struct WelcomeScreen: View {
    @State private var showContent = false
    @State private var logoScale = 0.5
    @State private var logoOpacity = 0.0

    let onLogin: () -> Void
    let onSignUp: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Hero Logo & Title
            VStack(spacing: 24) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .shadow(color: .blue.opacity(0.5), radius: 20, y: 10)

                VStack(spacing: 12) {
                    Text("StepOut")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("Make every moment count")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
            }

            Spacer()

            // Action Buttons
            VStack(spacing: 16) {
                // Sign Up Button
                Button(action: onSignUp) {
                    HStack {
                        Text("Create Account")
                            .font(.title3.weight(.semibold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.5), radius: 15, y: 8)
                }
                .scaleEffect(showContent ? 1 : 0.9)
                .opacity(showContent ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: showContent)

                // Login Button
                Button(action: onLogin) {
                    HStack {
                        Text("I already have an account")
                        Image(systemName: "arrow.right")
                    }
                    .font(.body.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .scaleEffect(showContent ? 1 : 0.9)
                .opacity(showContent ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: showContent)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                showContent = true
            }
        }
    }
}

// MARK: - Login Screen
struct LoginScreen: View {
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onBack: () -> Void
    let onSuccess: (User) -> Void

    private var isValid: Bool {
        !email.isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)

            ScrollView {
                VStack(spacing: 32) {
                    // Title
                    VStack(spacing: 12) {
                        Text("Welcome Back")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)

                        Text("Sign in to continue")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 24) {
                        OnboardingTextField(
                            title: "Email",
                            placeholder: "your.email@example.com",
                            text: $email,
                            icon: "envelope.fill",
                            keyboardType: .emailAddress
                        )

                        OnboardingPasswordField(
                            title: "Password",
                            placeholder: "Enter your password",
                            text: $password,
                            showPassword: $showPassword,
                            icon: "lock.fill"
                        )
                    }
                    .padding(.horizontal, 32)

                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal, 32)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Login Button
                    Button(action: { Task { await login() } }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign In")
                                    .font(.headline)
                                Image(systemName: "arrow.right.circle.fill")
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: isValid ? [.blue, .purple] : [.gray.opacity(0.3), .gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: isValid ? .blue.opacity(0.4) : .clear, radius: 15, y: 8)
                    }
                    .disabled(!isValid || isLoading)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
            }

            Spacer()
        }
    }

    private func login() async {
        errorMessage = nil
        isLoading = true

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            isLoading = false
            await MainActor.run {
                onSuccess(result.user)
            }
        } catch {
            isLoading = false
            errorMessage = "Invalid email or password. Please try again."
        }
    }
}

// MARK: - Modern Text Field Component
struct OnboardingTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.blue.opacity(0.8))
                    .frame(width: 20)

                TextField("", text: $text)
                    .placeholder(when: text.isEmpty) {
                        Text(placeholder)
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .keyboardType(keyboardType)
                    .autocapitalization(keyboardType == .emailAddress ? .none : .words)
                    .foregroundColor(.white)
                    .font(.body)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(Color.white.opacity(0.08))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

// MARK: - Modern Password Field Component
struct OnboardingPasswordField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.blue.opacity(0.8))
                    .frame(width: 20)

                if showPassword {
                    TextField("", text: $text)
                        .placeholder(when: text.isEmpty) {
                            Text(placeholder)
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .foregroundColor(.white)
                        .font(.body)
                        .autocapitalization(.none)
                } else {
                    SecureField("", text: $text)
                        .placeholder(when: text.isEmpty) {
                            Text(placeholder)
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .foregroundColor(.white)
                        .font(.body)
                        .autocapitalization(.none)
                }

                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(Color.white.opacity(0.08))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

// Placeholder modifier helper
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Sign Up Name Step
struct SignUpNameStep: View {
    @State private var name = ""
    @State private var showContent = false

    let onBack: () -> Void
    let onNext: (String) -> Void

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                Text("Step 1/4")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)

            ScrollView {
                VStack(spacing: 32) {
                    // Icon & Title
                    VStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(showContent ? 1 : 0.8)
                            .opacity(showContent ? 1 : 0)

                        VStack(spacing: 8) {
                            Text("What's your name?")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)

                            Text("Let's get to know you")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 10)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 24) {
                        OnboardingTextField(
                            title: "Full Name",
                            placeholder: "John Doe",
                            text: $name,
                            icon: "person.fill",
                            keyboardType: .default
                        )
                    }
                    .padding(.horizontal, 32)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                    // Continue Button
                    Button(action: { onNext(name.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
                        HStack {
                            Text("Continue")
                                .font(.headline)
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: isValid ? [.blue, .purple] : [.gray.opacity(0.3), .gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: isValid ? .blue.opacity(0.4) : .clear, radius: 15, y: 8)
                    }
                    .disabled(!isValid)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                }
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }
}

// MARK: - Sign Up Email Step
struct SignUpEmailStep: View {
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var showPassword = false
    @State private var showContent = false
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var errorMessage: String?

    let onBack: () -> Void
    let onNext: (String, String, String) -> Void

    private var isValid: Bool {
        isValidEmail(email) &&
        isValidPassword(password) &&
        !username.isEmpty &&
        usernameAvailable == true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                Text("Step 2/4")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)

            ScrollView {
                VStack(spacing: 32) {
                    // Icon & Title
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(showContent ? 1 : 0.8)
                            .opacity(showContent ? 1 : 0)

                        VStack(spacing: 8) {
                            Text("Create your account")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)

                            Text("Set up your login credentials")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 10)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 24) {
                        OnboardingTextField(
                            title: "Email",
                            placeholder: "your.email@example.com",
                            text: $email,
                            icon: "envelope.fill",
                            keyboardType: .emailAddress
                        )

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Username")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.9))

                            HStack(spacing: 16) {
                                Image(systemName: "at")
                                    .foregroundColor(.blue.opacity(0.8))
                                    .frame(width: 20)

                                TextField("", text: $username)
                                    .placeholder(when: username.isEmpty) {
                                        Text("username")
                                            .foregroundColor(.white.opacity(0.3))
                                    }
                                    .autocapitalization(.none)
                                    .foregroundColor(.white)
                                    .font(.body)
                                    .onChange(of: username) { _ in
                                        checkUsernameAvailability()
                                    }

                                if isCheckingUsername {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else if let available = usernameAvailable {
                                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(available ? .green : .red)
                                }
                            }
                            .padding(.vertical, 18)
                            .padding(.horizontal, 20)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        usernameAvailable == true ? Color.green.opacity(0.5) :
                                        usernameAvailable == false ? Color.red.opacity(0.5) :
                                        Color.white.opacity(0.15),
                                        lineWidth: 1
                                    )
                            )
                        }

                        OnboardingPasswordField(
                            title: "Password",
                            placeholder: "At least 8 characters",
                            text: $password,
                            showPassword: $showPassword,
                            icon: "lock.fill"
                        )

                        // Password strength indicator
                        if !password.isEmpty {
                            OnboardingPasswordStrengthIndicator(password: password)
                        }
                    }
                    .padding(.horizontal, 32)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal, 32)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Continue Button
                    Button(action: { onNext(email, password, username.lowercased()) }) {
                        HStack {
                            Text("Continue")
                                .font(.headline)
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: isValid ? [.blue, .purple] : [.gray.opacity(0.3), .gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: isValid ? .blue.opacity(0.4) : .clear, radius: 15, y: 8)
                    }
                    .disabled(!isValid)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                }
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func isValidPassword(_ password: String) -> Bool {
        return password.count >= 8 &&
               password.contains(where: { $0.isUppercase }) &&
               password.contains(where: { $0.isLowercase }) &&
               password.contains(where: { $0.isNumber })
    }

    private func checkUsernameAvailability() {
        guard !username.isEmpty else {
            usernameAvailable = nil
            return
        }

        isCheckingUsername = true
        usernameAvailable = nil

        Task {
            do {
                let db = Firestore.firestore()
                let snapshot = try await db.collection("usernames").document(username.lowercased()).getDocument()

                await MainActor.run {
                    usernameAvailable = !snapshot.exists
                    isCheckingUsername = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not check username availability"
                    isCheckingUsername = false
                }
            }
        }
    }
}

// MARK: - Password Strength Indicator
struct OnboardingPasswordStrengthIndicator: View {
    let password: String

    private var strength: PasswordStrength {
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.contains(where: { $0.isUppercase }) { score += 1 }
        if password.contains(where: { $0.isLowercase }) { score += 1 }
        if password.contains(where: { $0.isNumber }) { score += 1 }
        if password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }) { score += 1 }

        switch score {
        case 0...2: return .weak
        case 3...4: return .medium
        default: return .strong
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Rectangle()
                    .fill(index < strength.rawValue ? strength.color : Color.white.opacity(0.2))
                    .frame(height: 4)
                    .cornerRadius(2)
            }

            Text(strength.text)
                .font(.caption.weight(.medium))
                .foregroundColor(strength.color)
        }
        .padding(.horizontal, 32)
    }

    enum PasswordStrength: Int {
        case weak = 1
        case medium = 2
        case strong = 3

        var color: Color {
            switch self {
            case .weak: return .red
            case .medium: return .orange
            case .strong: return .green
            }
        }

        var text: String {
            switch self {
            case .weak: return "Weak"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }
    }
}

// MARK: - Sign Up Phone Step
struct SignUpPhoneStep: View {
    @State private var countryCode = "+1"
    @State private var phone = ""
    @State private var showContent = false
    @State private var agreedToTerms = false
    @State private var showTermsSheet = false

    let onBack: () -> Void
    let onNext: (String) -> Void

    private var isValid: Bool {
        let digits = phone.filter { $0.isNumber }
        return digits.count >= 10 && agreedToTerms
    }

    private var formattedPhone: String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 10 else { return countryCode + " " + phone }

        let trimmed: String
        if digits.count == 11, digits.hasPrefix("1") {
            trimmed = String(digits.suffix(10))
        } else if digits.count == 10 {
            trimmed = digits
        } else {
            trimmed = String(digits.suffix(10))
        }

        let area = trimmed.prefix(3)
        let exchange = trimmed.dropFirst(3).prefix(3)
        let subscriber = trimmed.suffix(4)
        return "\(countryCode) (\(area)) \(exchange)-\(subscriber)"
    }

    private let countryCodes = [
        ("+1", "🇺🇸 US"),
        ("+1", "🇨🇦 CA"),
        ("+44", "🇬🇧 UK"),
        ("+91", "🇮🇳 IN"),
        ("+86", "🇨🇳 CN"),
        ("+81", "🇯🇵 JP"),
        ("+49", "🇩🇪 DE"),
        ("+33", "🇫🇷 FR"),
        ("+39", "🇮🇹 IT"),
        ("+34", "🇪🇸 ES"),
        ("+61", "🇦🇺 AU"),
        ("+55", "🇧🇷 BR"),
        ("+52", "🇲🇽 MX"),
        ("+7", "🇷🇺 RU"),
        ("+82", "🇰🇷 KR")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                Text("Step 3/4")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)

            ScrollView {
                VStack(spacing: 32) {
                    // Icon & Title
                    VStack(spacing: 16) {
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(showContent ? 1 : 0.8)
                            .opacity(showContent ? 1 : 0)

                        VStack(spacing: 8) {
                            Text("Your phone number")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)

                            Text("We'll use this for account recovery")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 10)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 24) {
                        // Country Code Picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Country Code")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.9))

                            Menu {
                                ForEach(countryCodes, id: \.0) { code in
                                    Button(action: { countryCode = code.0 }) {
                                        Text("\(code.1) \(code.0)")
                                    }
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "globe")
                                        .foregroundColor(.blue.opacity(0.8))
                                        .frame(width: 20)

                                    Text(countryCode)
                                        .foregroundColor(.white)
                                        .font(.body)

                                    Spacer()

                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.white.opacity(0.5))
                                        .font(.caption)
                                }
                                .padding(.vertical, 18)
                                .padding(.horizontal, 20)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }

                        // Phone Number Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Phone Number")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.9))

                            HStack(spacing: 16) {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.blue.opacity(0.8))
                                    .frame(width: 20)

                                TextField("", text: $phone)
                                    .placeholder(when: phone.isEmpty) {
                                        Text("(555) 123-4567")
                                            .foregroundColor(.white.opacity(0.3))
                                    }
                                    .keyboardType(.phonePad)
                                    .foregroundColor(.white)
                                    .font(.body)
                            }
                            .padding(.vertical, 18)
                            .padding(.horizontal, 20)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        }

                        if phone.filter({ $0.isNumber }).count >= 10 {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Valid: \(formattedPhone)")
                                    .font(.callout)
                                    .foregroundColor(.green)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Terms and Conditions Checkbox
                        Button(action: { agreedToTerms.toggle() }) {
                            HStack(spacing: 12) {
                                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                    .foregroundColor(agreedToTerms ? .blue : .white.opacity(0.5))
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Text("I agree to the")
                                            .font(.callout)
                                            .foregroundColor(.white.opacity(0.9))
                                        Button(action: { showTermsSheet = true }) {
                                            Text("Terms & Conditions")
                                                .font(.callout.weight(.semibold))
                                                .foregroundColor(.blue)
                                                .underline()
                                        }
                                    }
                                    Text("Required to create account")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 32)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                    // Continue Button
                    Button(action: { onNext(formattedPhone) }) {
                        HStack {
                            Text("Continue")
                                .font(.headline)
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: isValid ? [.blue, .purple] : [.gray.opacity(0.3), .gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: isValid ? .blue.opacity(0.4) : .clear, radius: 15, y: 8)
                    }
                    .disabled(!isValid)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                }
            }

            Spacer()
        }
        .sheet(isPresented: $showTermsSheet) {
            TermsAndConditionsView()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }
}

// MARK: - Terms and Conditions View
struct TermsAndConditionsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Terms and Conditions")
                        .font(.largeTitle.bold())
                        .padding(.bottom, 8)

                    Group {
                        SectionHeader(title: "1. Acceptance of Terms")
                        Text("By accessing and using StepOut (\"the App\"), you accept and agree to be bound by the terms and provisions of this agreement. If you do not agree to these terms, please do not use the App.")

                        SectionHeader(title: "2. Use License")
                        Text("Permission is granted to temporarily use the App for personal, non-commercial purposes. This license shall automatically terminate if you violate any of these restrictions.")

                        SectionHeader(title: "3. User Content and Privacy")
                        Text("You retain all rights to any content you submit, post or display on or through the App. By submitting content, you grant us a worldwide, non-exclusive, royalty-free license to use, reproduce, and distribute such content in connection with the App.")

                        Text("We collect and process personal information as described in our Privacy Policy. By using the App, you consent to such processing and warrant that all data provided by you is accurate.")

                        SectionHeader(title: "4. Copyright and Distribution")
                        Text("The App and its original content, features, and functionality are owned by StepOut and are protected by international copyright, trademark, patent, trade secret, and other intellectual property laws.")

                        Text("You may not reproduce, distribute, modify, create derivative works of, publicly display, publicly perform, republish, download, store, or transmit any of the material on our App without prior written consent.")

                        SectionHeader(title: "5. Event Participation")
                        Text("The App allows users to create and join events. You are solely responsible for your participation in any events. StepOut is not liable for any injuries, damages, or losses incurred during event participation.")

                        Text("Event creators are responsible for ensuring their events comply with all applicable laws and regulations. StepOut reserves the right to remove any event that violates these terms or applicable laws.")

                        SectionHeader(title: "6. Prohibited Conduct")
                        Text("You agree not to:")
                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint(text: "Use the App for any illegal purpose or in violation of any laws")
                            BulletPoint(text: "Post false, misleading, or fraudulent information")
                            BulletPoint(text: "Harass, abuse, or harm other users")
                            BulletPoint(text: "Impersonate any person or entity")
                            BulletPoint(text: "Interfere with or disrupt the App or servers")
                        }

                        SectionHeader(title: "7. Account Termination")
                        Text("We reserve the right to terminate or suspend your account and access to the App immediately, without prior notice, for conduct that we believe violates these Terms or is harmful to other users, us, or third parties.")

                        SectionHeader(title: "8. Disclaimer of Warranties")
                        Text("The App is provided \"as is\" and \"as available\" without warranties of any kind, either express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and non-infringement.")

                        SectionHeader(title: "9. Limitation of Liability")
                        Text("In no event shall StepOut, its directors, employees, or agents be liable for any indirect, incidental, special, consequential, or punitive damages arising out of or relating to your use of the App.")

                        SectionHeader(title: "10. Indemnification")
                        Text("You agree to indemnify and hold harmless StepOut and its affiliates from any claims, damages, losses, liabilities, and expenses arising from your use of the App or violation of these Terms.")

                        SectionHeader(title: "11. Changes to Terms")
                        Text("We reserve the right to modify these terms at any time. We will notify users of any material changes by posting the new Terms on the App. Your continued use of the App after such modifications constitutes acceptance of the updated Terms.")

                        SectionHeader(title: "12. Governing Law")
                        Text("These Terms shall be governed by and construed in accordance with the laws of the United States, without regard to its conflict of law provisions.")

                        SectionHeader(title: "13. Contact Information")
                        Text("If you have questions about these Terms, please contact us at:")
                        Text("bharathraghunath007@gmail.com")
                            .foregroundColor(.blue)
                            .padding(.leading, 16)

                        Text("Last Updated: January 2025")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 16)
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline.bold())
            .padding(.top, 8)
    }
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
            Text(text)
                .font(.body)
        }
        .padding(.leading, 16)
    }
}

// MARK: - Sign Up Interests Step
struct SignUpInterestsStep: View {
    @State private var selectedInterests: Set<String> = []
    @State private var showContent = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    let onBack: () -> Void
    let onComplete: ([String], @escaping (Bool, String?) -> Void) -> Void

    private let availableInterests = [
        ("music.note", "Music"),
        ("sportscourt", "Sports"),
        ("paintpalette", "Art"),
        ("fork.knife", "Food"),
        ("airplane", "Travel"),
        ("book", "Books"),
        ("film", "Movies"),
        ("gamecontroller", "Gaming"),
        ("dumbbell", "Fitness"),
        ("camera", "Photography"),
        ("laptopcomputer", "Tech"),
        ("leaf", "Nature"),
        ("theatermasks", "Theater"),
        ("bicycle", "Cycling"),
        ("figure.yoga", "Yoga")
    ]

    private var isValid: Bool {
        selectedInterests.count >= 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                Text("Step 4/4")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)

            ScrollView {
                VStack(spacing: 32) {
                    // Icon & Title
                    VStack(spacing: 16) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(showContent ? 1 : 0.8)
                            .opacity(showContent ? 1 : 0)

                        VStack(spacing: 8) {
                            Text("Your interests")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)

                            Text("Pick at least 3 things you enjoy")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 10)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.top, 40)

                    // Interests Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(availableInterests, id: \.1) { interest in
                            InterestCard(
                                icon: interest.0,
                                title: interest.1,
                                isSelected: selectedInterests.contains(interest.1)
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selectedInterests.contains(interest.1) {
                                        selectedInterests.remove(interest.1)
                                    } else {
                                        selectedInterests.insert(interest.1)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                    // Selection count
                    if selectedInterests.count > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: selectedInterests.count >= 3 ? "checkmark.circle.fill" : "info.circle.fill")
                                .foregroundColor(selectedInterests.count >= 3 ? .green : .orange)
                            Text("\(selectedInterests.count) selected \(selectedInterests.count >= 3 ? "✓" : "(need \(3 - selectedInterests.count) more)")")
                                .font(.callout)
                                .foregroundColor(selectedInterests.count >= 3 ? .green : .orange)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal, 32)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Create Account Button
                    Button(action: {
                        isCreating = true
                        errorMessage = nil
                        onComplete(Array(selectedInterests)) { success, error in
                            isCreating = false
                            if !success {
                                errorMessage = error
                            }
                        }
                    }) {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Create Account")
                                    .font(.headline)
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: isValid ? [.blue, .purple] : [.gray.opacity(0.3), .gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: isValid ? .blue.opacity(0.4) : .clear, radius: 15, y: 8)
                    }
                    .disabled(!isValid || isCreating)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                }
                .padding(.bottom, 50)
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }
}

// MARK: - Interest Card Component
struct InterestCard: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? .white : .blue.opacity(0.8))

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [.white.opacity(0.08), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.blue.opacity(0.8) : Color.white.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 10, y: 5)
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
    }
}
