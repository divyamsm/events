import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EventPreferencesView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategories: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    let isOnboarding: Bool
    let onComplete: (([String]) -> Void)?

    // Event categories
    private let categories = [
        ("🏃", "Sports & Fitness"),
        ("🍕", "Food & Drinks"),
        ("🎵", "Music & Concerts"),
        ("🎨", "Arts & Culture"),
        ("🏔️", "Outdoor & Adventure"),
        ("💼", "Networking & Professional"),
        ("🎮", "Gaming & Esports"),
        ("🎉", "Parties & Nightlife"),
        ("📚", "Books & Learning"),
        ("🎬", "Movies & Theatre"),
        ("🧘", "Wellness & Mindfulness"),
        ("🍷", "Wine & Tasting")
    ]

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    if isOnboarding {
                        Spacer().frame(height: 20)
                    }

                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text(isOnboarding ? "What interests you?" : "Edit Preferences")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)

                        Text("Select at least 3 event types you'd like to see")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Categories Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(categories, id: \.1) { emoji, category in
                            CategoryCard(
                                emoji: emoji,
                                title: category,
                                isSelected: selectedCategories.contains(category),
                                onTap: {
                                    if selectedCategories.contains(category) {
                                        selectedCategories.remove(category)
                                    } else {
                                        selectedCategories.insert(category)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)

                    // Selection Counter
                    HStack {
                        Image(systemName: selectedCategories.count >= 3 ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedCategories.count >= 3 ? .green : .white.opacity(0.5))

                        Text("\(selectedCategories.count) selected")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))

                        if selectedCategories.count < 3 {
                            Text("(minimum 3)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // Continue Button
                    Button(action: { Task { await savePreferences() } }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text(isOnboarding ? "Continue" : "Save")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: selectedCategories.count >= 3 ? [.blue, .purple] : [.gray, .gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: selectedCategories.count >= 3 ? .blue.opacity(0.5) : .clear, radius: 10, y: 5)
                    }
                    .disabled(selectedCategories.count < 3 || isLoading)
                    .padding(.horizontal, 32)

                    if !isOnboarding {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
        .navigationBarHidden(isOnboarding)
        .task {
            await loadExistingPreferences()
        }
    }

    private func loadExistingPreferences() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let doc = try await Firestore.firestore().collection("users").document(uid).getDocument()
            if let prefs = doc.data()?["eventPreferences"] as? [String] {
                selectedCategories = Set(prefs)
            }
        } catch {
            print("[Preferences] Error loading: \(error)")
        }
    }

    private func savePreferences() async {
        guard selectedCategories.count >= 3 else {
            errorMessage = "Please select at least 3 categories"
            return
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Not authenticated"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let prefsArray = Array(selectedCategories)

            try await Firestore.firestore().collection("users").document(uid).updateData([
                "eventPreferences": prefsArray,
                "onboardingCompleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])

            print("[Preferences] ✅ Saved preferences: \(prefsArray)")

            isLoading = false

            if let onComplete = onComplete {
                onComplete(prefsArray)
            } else {
                dismiss()
            }
        } catch {
            isLoading = false
            errorMessage = "Failed to save preferences"
            print("[Preferences] ❌ Error: \(error)")
        }
    }
}

struct CategoryCard: View {
    let emoji: String
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 40))

                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: isSelected ? 3 : 1)
            )
            .scaleEffect(isSelected ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    EventPreferencesView(isOnboarding: true, onComplete: { prefs in
        print("Selected: \(prefs)")
    })
}
