import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Terms of Service")
                        .font(.largeTitle.bold())
                        .padding(.bottom, 8)

                    Group {
                        sectionHeader("Agreement to Terms")
                        sectionText("By using StepOut, you agree to these Terms of Service. If you do not agree, do not use the app.")

                        sectionHeader("User Conduct")
                        sectionText("You agree to use StepOut responsibly and not to:")
                        bulletPoint("Post offensive, hateful, or discriminatory content")
                        bulletPoint("Harass, threaten, or harm other users")
                        bulletPoint("Post spam or misleading information")
                        bulletPoint("Violate any laws or regulations")
                        bulletPoint("Impersonate others or create fake accounts")
                        bulletPoint("Post sexually explicit or violent content")

                        sectionHeader("Zero Tolerance Policy")
                        sectionText("StepOut has ZERO TOLERANCE for objectionable content or abusive behavior. Violations will result in immediate account suspension or termination.")

                        sectionHeader("Content Moderation")
                        sectionText("We actively monitor and moderate user-generated content. Users can report inappropriate content or abusive users. All reports are reviewed within 24 hours.")

                        sectionHeader("User Responsibilities")
                        bulletPoint("You are responsible for all content you post")
                        bulletPoint("You must be at least 13 years old to use StepOut")
                        bulletPoint("You must provide accurate information")
                        bulletPoint("You must respect other users' privacy")

                        sectionHeader("Enforcement")
                        sectionText("We reserve the right to remove any content and terminate any account that violates these terms, without prior notice.")

                        sectionHeader("Reporting")
                        sectionText("If you see inappropriate content or abusive behavior, please report it immediately using the Report button. We take all reports seriously.")

                        sectionHeader("Privacy")
                        sectionText("Your use of StepOut is also governed by our Privacy Policy. We collect and use your data as described in our Privacy Policy.")

                        sectionHeader("Changes to Terms")
                        sectionText("We may update these Terms from time to time. Continued use of the app after changes constitutes acceptance of the new Terms.")

                        sectionHeader("Contact")
                        sectionText("For questions about these Terms, contact us at: support@stepout.app")
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Accept") {
                        onAccept()
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .padding(.top, 8)
    }

    private func sectionText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }
}

#Preview {
    TermsOfServiceView(onAccept: {})
}
