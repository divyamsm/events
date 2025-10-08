import SwiftUI

struct ContentView: View {
    private let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List(EventRepository.sampleEvents) { event in
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.headline)
                    Text(event.location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(dateFormatter.localizedString(for: event.date, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Upcoming Events")
        }
    }
}

#Preview {
    ContentView()
}
