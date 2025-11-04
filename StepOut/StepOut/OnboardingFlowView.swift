import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step: Step = .splash
    @State private var phoneNumber: String = ""
    @State private var otpCode: String = ""
    @State private var contactsAllowed: Bool = false
    @State private var selectedCategories: Set<OnboardingEventCategory> = []
    @Namespace private var animationNamespace
    @StateObject private var authViewModel = PhoneAuthViewModel()

    private let categories: [OnboardingEventCategory] = OnboardingEventCategory.samples
    private let sampleContacts: [ContactItem] = ContactItem.samples

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.12, green: 0.12, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                content
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.96))
                    )
                    .padding(.horizontal, 12)
                Spacer(minLength: 24)
                if step.shouldShowProgress {
                    ProgressDots(current: step.progressIndex, total: Step.progressTotal)
                        .padding(.bottom, 24)
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: advanceFromSplash)
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .splash:
            SplashView()
        case .phone:
            phoneCapture
        case .otp:
            otpCapture
        case .contacts:
            contactsPermission
        case .interests:
            interestSelection
        }
    }

    private var phoneCapture: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingHeader(
                title: "Enter your phone number",
                subtitle: "We’ll send a one-time passcode to verify your account."
            )

            TextField("Phone Number", text: $phoneNumber)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .padding()
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.primary.opacity(phoneNumber.count >= 10 ? 0.4 : 0.15), lineWidth: 1)
                )
                .onChange(of: phoneNumber) { newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != phoneNumber {
                        phoneNumber = filtered
                    } else if phoneNumber.count > 15 {
                        phoneNumber = String(phoneNumber.prefix(15))
                    }
                }

            if let error = authViewModel.errorMessage, step == .phone {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let hint = authViewModel.codeHint, step == .phone {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            PrimaryButton(
                title: "Send Code",
                isEnabled: phoneNumber.count >= 10,
                isLoading: authViewModel.isSendingCode
            ) {
                Task {
                    let success = await authViewModel.sendCode(for: phoneNumber)
                    if success {
                        otpCode = ""
                        withAnimation {
                            step = .otp
                        }
                    }
                }
            }
        }
    }

    private var otpCapture: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                title: "Verify it’s you",
                subtitle: "Enter the 6-digit code we just texted to \(formattedPhoneNumber())."
            )

            OTPInputView(code: $otpCode)

            if let error = authViewModel.errorMessage, step == .otp {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let hint = authViewModel.codeHint, step == .otp {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            PrimaryButton(
                title: "Continue",
                isEnabled: otpCode.count == 6,
                isLoading: authViewModel.isVerifyingCode
            ) {
                Task {
                    let success = await authViewModel.verify(code: otpCode)
                    if success {
                        withAnimation {
                            step = .contacts
                        }
                    }
                }
            }

            Button("Didn’t get a code? Resend") {
                Task {
                    _ = await authViewModel.sendCode(for: phoneNumber)
                    otpCode = ""
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .disabled(authViewModel.isSendingCode)
        }
    }

    private var contactsPermission: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                title: "Share your contacts",
                subtitle: "See which friends are already on Simple Events and invite others in one tap."
            )

            VStack(spacing: 12) {
                ForEach(sampleContacts) { contact in
                    HStack {
                        Circle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(contact.initials)
                                    .font(.headline.weight(.semibold))
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contact.name)
                                .font(.body.weight(.semibold))
                            Text(contact.isOnApp ? "Already on Simple Events" : "Invite with one tap")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if contact.isOnApp {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "message.fill")
                                .foregroundStyle(.blue.opacity(0.75))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))

            Toggle(isOn: $contactsAllowed.animation()) {
                Text("Allow access to contacts")
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))

            Spacer(minLength: 12)

            PrimaryButton(
                title: contactsAllowed ? "Sync Contacts & Continue" : "Not Now, Continue",
                isEnabled: true
            ) {
                withAnimation {
                    step = .interests
                }
            }
        }
    }

    private var interestSelection: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                title: "Pick event vibes",
                subtitle: "Choose at least three so we can recommend the best upcoming events."
            )

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 18)], spacing: 18) {
                    ForEach(categories) { category in
                        CategoryCardView(
                            category: category,
                            isSelected: selectedCategories.contains(category),
                            namespace: animationNamespace
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                toggleCategory(category)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 360)

            Spacer(minLength: 12)

            PrimaryButton(
                title: selectedCategories.count >= 3 ? "Finish & Explore" : "Choose \(3 - selectedCategories.count) more",
                isEnabled: selectedCategories.count >= 3
            ) {
                appState.isOnboarded = true
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func toggleCategory(_ category: OnboardingEventCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    private func formattedPhoneNumber() -> String {
        if authViewModel.formattedDisplayNumber.isEmpty == false {
            return authViewModel.formattedDisplayNumber
        }

        let digits = phoneNumber.filter(\.isNumber)
        guard digits.count >= 4 else { return phoneNumber }
        let mask = "(XXX) XXX-XXXX"
        var result = ""
        var index = digits.startIndex

        for ch in mask where index < digits.endIndex {
            if ch == "X" {
                result.append(digits[index])
                index = digits.index(after: index)
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private func advanceFromSplash() {
        guard step == .splash else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation {
                step = .contacts
            }
        }
    }

    private enum Step: CaseIterable {
        case splash, phone, otp, contacts, interests

        var shouldShowProgress: Bool {
            switch self {
            case .splash, .phone, .otp:
                return false
            case .contacts, .interests:
                return true
            }
        }

        var progressIndex: Int {
            switch self {
            case .splash:
                return 0
            case .contacts:
                return 0
            case .interests:
                return 1
            case .phone, .otp:
                return 0
            }
        }

        static var progressTotal: Int { 2 }
    }
}

private struct OnboardingHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        let backgroundColor: Color = (isEnabled && !isLoading) ? .blue : Color.gray.opacity(0.3)

        Button {
            guard !isLoading else { return }
            action()
        } label: {
            ZStack {
                Text(title)
                    .font(.headline.weight(.bold))
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundColor)
            )
            .foregroundStyle(.white)
        }
        .disabled(!isEnabled || isLoading)
    }
}

private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == current ? 10 : 8, height: index == current ? 10 : 8)
            }
        }
    }
}

private struct SplashView: View {
    @State private var pulse = false
    @State private var drawProgress: CGFloat = 0
    @State private var showTagline = false

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(LinearGradient(
                            colors: [.white.opacity(Double(0.35 - Double(index) * 0.1)), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ), lineWidth: CGFloat(6 - index * 2))
                        .frame(width: CGFloat(130 + index * 26), height: CGFloat(130 + index * 26))
                        .scaleEffect(pulse ? 1.05 : 0.85)
                        .opacity(pulse ? 0.4 : 0.15)
                        .animation(
                            .easeInOut(duration: 1.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12),
                            value: pulse
                        )
                }

                TimelinePath(progress: drawProgress)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 140, height: 140)

                VStack(spacing: 6) {
                    Image(systemName: "location.north.line.fill")
                        .font(.title2.weight(.bold))
                        .rotationEffect(.degrees(pulse ? 5 : -5))
                        .foregroundStyle(.white)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)

                    Text("StepOut")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(spacing: 6) {
                Text("Find the moment.")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .opacity(showTagline ? 1 : 0)
                    .offset(y: showTagline ? 0 : 8)
                    .animation(.easeOut(duration: 0.6), value: showTagline)

                Text("Curated events, shared instantly.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(showTagline ? 1 : 0)
                    .offset(y: showTagline ? 0 : 8)
                    .animation(.easeOut(duration: 0.6).delay(0.08), value: showTagline)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 1.2)) {
                    drawProgress = 1
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                showTagline = true
            }
        }
    }
}

private struct TimelinePath: Shape {
    var progress: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let insetRect = rect.insetBy(dx: 16, dy: 16)
        let top = CGPoint(x: insetRect.midX, y: insetRect.minY)
        let right = CGPoint(x: insetRect.maxX, y: insetRect.midY)
        let bottom = CGPoint(x: insetRect.midX, y: insetRect.maxY)
        let left = CGPoint(x: insetRect.minX, y: insetRect.midY)

        path.move(to: top)
        path.addLine(to: right)
        path.addLine(to: bottom)
        path.addLine(to: left)
        path.addLine(to: top)

        return path.trimmedPath(from: 0, to: min(max(progress, 0), 1))
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
}

private struct OTPInputView: View {
    @Binding var code: String

    private let maxDigits = 6
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<maxDigits, id: \.self) { index in
                let character = character(at: index)
                Text(character)
                    .font(.title2.weight(.semibold))
                    .frame(width: 54, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(index == code.count ? 0.4 : 0.18), lineWidth: 1)
                    )
            }
        }
        .overlay(
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityLabel("One time passcode")
                .onChange(of: code) { newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != code {
                        code = filtered
                    } else if code.count > maxDigits {
                        code = String(code.prefix(maxDigits))
                    }
                }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isFocused = true
            }
        }
    }

    private func character(at index: Int) -> String {
        guard index < code.count else { return "◦" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }
}

private struct CategoryCardView: View {
    let category: OnboardingEventCategory
    let isSelected: Bool
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: category.iconName)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                )
                .foregroundStyle(.blue)

            Text(category.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                if isSelected {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.blue, lineWidth: 2)
                        .matchedGeometryEffect(id: category.id, in: namespace)
                }
            }
        )
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .shadow(color: isSelected ? Color.blue.opacity(0.2) : .clear, radius: 8, y: 6)
    }
}

private struct OnboardingEventCategory: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let iconName: String

    static let samples: [OnboardingEventCategory] = [
        OnboardingEventCategory(title: "Tech Conferences", iconName: "desktopcomputer"),
        OnboardingEventCategory(title: "Live Music & Festivals", iconName: "music.mic"),
        OnboardingEventCategory(title: "Art & Culture Nights", iconName: "paintpalette.fill"),
        OnboardingEventCategory(title: "Startup Meetups", iconName: "lightbulb.max.fill"),
        OnboardingEventCategory(title: "Food & Drink Pop-ups", iconName: "fork.knife"),
        OnboardingEventCategory(title: "Outdoor Adventures", iconName: "leaf.fill"),
        OnboardingEventCategory(title: "Gaming & Esports", iconName: "gamecontroller.fill"),
        OnboardingEventCategory(title: "Wellness & Fitness", iconName: "figure.run"),
        OnboardingEventCategory(title: "Workshops & Classes", iconName: "book.closed.fill"),
        OnboardingEventCategory(title: "Sports & Rec", iconName: "sportscourt")
    ]
}

private struct ContactItem: Identifiable {
    let id = UUID()
    let name: String
    let isOnApp: Bool
    var initials: String {
        let comps = name.split(separator: " ").compactMap { $0.first }
        return String(comps.prefix(2)).uppercased()
    }

    static let samples: [ContactItem] = [
        ContactItem(name: "Disha Kapoor", isOnApp: true),
        ContactItem(name: "Divyam Mehta", isOnApp: false),
        ContactItem(name: "Shreyas Iyer", isOnApp: true),
        ContactItem(name: "Jordan Lee", isOnApp: false),
        ContactItem(name: "Maya Chen", isOnApp: false)
    ]
}
