import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

@MainActor
final class PhoneAuthViewModel: ObservableObject {
    @Published private(set) var isSendingCode = false
    @Published private(set) var isVerifyingCode = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var formattedDisplayNumber: String = ""
    @Published private(set) var codeHint: String?

    private var verificationID: String?

    func sendCode(for rawInput: String) async -> Bool {
#if DEBUG
        guard let phone = normalize(rawInput) else {
            errorMessage = "Enter a valid 10-digit US phone number."
            return false
        }

        formattedDisplayNumber = phone.display
        verificationID = simulatorVerificationID
        codeHint = "Debug build shortcut: enter \(simulatorOTP) on the next screen."
        errorMessage = nil
        return true
#else
#if canImport(FirebaseAuth)
        guard FirebaseApp.app() != nil else {
            errorMessage = "Firebase isn't configured. Double check your GoogleService-Info.plist."
            return false
        }

        guard let phone = normalize(rawInput) else {
            errorMessage = "Enter a valid 10-digit US phone number."
            return false
        }

        if isSimulator {
            formattedDisplayNumber = phone.display
            verificationID = simulatorVerificationID
            codeHint = "Simulator shortcut: enter \(simulatorOTP) on the next screen."
            errorMessage = nil
            return true
        } else {
            errorMessage = nil
            isSendingCode = true
            defer { isSendingCode = false }

            do {
                formattedDisplayNumber = phone.display

                let verificationID = try await requestVerificationID(e164: phone.e164)
                self.verificationID = verificationID
                codeHint = nil
                return true
            } catch {
                errorMessage = error.presentableMessage
                return false
            }
        }
#else
        errorMessage = "FirebaseAuth is not available in this build."
        return false
#endif
#endif
    }

    func verify(code: String) async -> Bool {
#if DEBUG
        guard code.count == 6 else {
            errorMessage = "The code should be 6 digits."
            return false
        }
        guard code == simulatorOTP else {
            errorMessage = "Use \(simulatorOTP) in debug builds."
            return false
        }
        codeHint = nil
        errorMessage = nil
        if verificationID == nil {
            verificationID = simulatorVerificationID
        }
        return true
#else
#if canImport(FirebaseAuth)
        guard FirebaseApp.app() != nil else {
            errorMessage = "Firebase isn't configured. Try restarting the app."
            return false
        }

        if isSimulator {
            guard verificationID == simulatorVerificationID else {
                errorMessage = "Please resend the code and try again."
                return false
            }
            guard code == simulatorOTP else {
                errorMessage = "Use \(simulatorOTP) when testing on the simulator."
                return false
            }

            do {
                codeHint = nil
                if Auth.auth().currentUser == nil {
                    _ = try await Auth.auth().signInAnonymously()
                }
                return true
            } catch {
                errorMessage = error.presentableMessage
                return false
            }
        } else {
            guard code.count >= 6 else {
                errorMessage = "The code should be 6 digits."
                return false
            }

            guard let verificationID else {
                errorMessage = "We couldn't find a pending verification. Please resend the code."
                return false
            }

            errorMessage = nil
            isVerifyingCode = true
            defer { isVerifyingCode = false }

            do {
                let credential = PhoneAuthProvider.provider().credential(
                    withVerificationID: verificationID,
                    verificationCode: code
                )
                _ = try await signIn(with: credential)
                return true
            } catch {
                errorMessage = error.presentableMessage
                return false
            }
        }
#else
        errorMessage = "FirebaseAuth is not available in this build."
        return false
#endif
#endif
    }

    func reset() {
        verificationID = nil
        formattedDisplayNumber = ""
        errorMessage = nil
        isSendingCode = false
        isVerifyingCode = false
        codeHint = nil
    }

#if canImport(FirebaseAuth)
    private func requestVerificationID(e164: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil) { id, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let id {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(throwing: PhoneAuthError.unknown)
                }
            }
        }
    }

    private func signIn(with credential: PhoneAuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: PhoneAuthError.unknown)
                }
            }
        }
    }

    private func normalize(_ raw: String) -> (display: String, e164: String)? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 10 else { return nil }

        let trimmed: String
        if digits.count == 11, digits.hasPrefix("1") {
            trimmed = String(digits.suffix(10))
        } else if digits.count == 10 {
            trimmed = digits
        } else {
            trimmed = String(digits.suffix(10))
        }

        let formatted = formatForDisplay(trimmed)
        let e164 = "+1\(trimmed)"

        return (formatted, e164)
    }

    private func formatForDisplay(_ digits: String) -> String {
        guard digits.count == 10 else { return digits }
        let area = digits.prefix(3)
        let exchange = digits.dropFirst(3).prefix(3)
        let subscriber = digits.suffix(4)
        return "(\(area)) \(exchange)-\(subscriber)"
    }

    private var isSimulator: Bool {
#if targetEnvironment(simulator)
        return true
#else
        return false
#endif
    }

    private var simulatorOTP: String {
        "123456"
    }

    private var simulatorVerificationID: String {
        "SIMULATOR_VERIFICATION"
    }
#endif
}

private enum PhoneAuthError: Error {
    case unknown
}

private extension Error {
    var presentableMessage: String {
#if canImport(FirebaseAuth)
        let nsError = self as NSError
        if nsError.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .invalidPhoneNumber:
                return "That phone number looks invalid. Double check it and try again."
            case .missingPhoneNumber:
                return "Enter your phone number first."
            case .quotaExceeded:
                return "We’ve sent too many codes today. Try again later."
            case .sessionExpired:
                return "This code expired. Request a new one."
            case .invalidVerificationCode:
                return "That code didn’t match. Double check the digits."
            case .appNotVerified:
                return "This device isn’t authorized for phone auth yet. Add it as a test number or finish APNs setup."
            default:
                break
            }
        }
        return nsError.localizedDescription
#else
        return (self as NSError).localizedDescription
#endif
    }
}
