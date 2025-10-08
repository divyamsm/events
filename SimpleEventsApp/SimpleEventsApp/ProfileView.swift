import SwiftUI
import UIKit

struct ProfileView: View {
    private let profile = ProfileRepository.sampleProfile
    private let calendar = ProfileRepository.calendar
    private let focusMonth = ProfileRepository.focusMonth

    @State private var showSettings = false
    @State private var showFriends = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                headerSection
                actionRow
                calendarSection
                statsStrip
                activitySegment
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                }
                .accessibilityLabel("Open settings")
            }
        }
        .sheet(isPresented: $showFriends) {
            FriendsSheetView(profile: profile)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsPlaceholderView()
                .presentationDetents([.medium])
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName)
                        .font(.title.bold())
                    Text(profile.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    Text(profile.bio)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.8), .blue.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)
                    .overlay(
                        Text(initials(for: profile.displayName))
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var actionRow: some View {
        HStack(spacing: 18) {
            Button {
                showFriends.toggle()
            } label: {
                actionButtonLabel(
                    systemImage: "person.2.fill",
                    title: "\(profile.friends.count) Friends"
                )
            }
            .buttonStyle(.plain)

            Button {
                showSettings.toggle()
            } label: {
                actionButtonLabel(
                    systemImage: "bell.badge.fill",
                    title: "Alerts"
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func actionButtonLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.headline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(.primary)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProfileCalendarView(
                month: focusMonth,
                calendar: calendar,
                attendedEvents: profile.attendedEvents
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var statsStrip: some View {
        HStack(spacing: 24) {
            statTile(
                icon: "heart.fill",
                title: "Events",
                value: "\(profile.attendedEvents.count)"
            )

            statTile(
                icon: "flame.fill",
                title: "Streak",
                value: "2 days"
            )

            statTile(
                icon: "person.2.wave.2.fill",
                title: "Invites",
                value: "\(profile.suggestedContacts.filter { !$0.isOnApp }.count)"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func statTile(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.primary)
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var activitySegment: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.headline)
            HStack(spacing: 16) {
                highlightChip("Rollcalls", symbol: "megaphone.fill", isActive: false)
                highlightChip("Lockets", symbol: "square.grid.3x3.fill", isActive: true)
                highlightChip("Daily", symbol: "sparkles", isActive: false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func highlightChip(_ title: String, symbol: String, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .background(
            Capsule(style: .circular)
                .fill(isActive ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
        )
    }

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ").compactMap { $0.first }
        return String(components.prefix(2)).uppercased()
    }
}

private struct ProfileCalendarView: View {
    let month: Date
    let calendar: Calendar
    let attendedEvents: [AttendedEvent]

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private var weekdaySymbols: [String] {
        calendar.shortWeekdaySymbols.map { String($0.prefix(1)) }
    }

    private var eventsByDay: [Int: [AttendedEvent]] {
        Dictionary(grouping: attendedEvents) { event in
            calendar.component(.day, from: event.date)
        }
    }

    private var dayGrid: [Int?] {
        let monthInterval = calendar.dateInterval(of: .month, for: month) ?? .init(start: month, duration: 0)
        let days = Array(calendar.range(of: .day, in: .month, for: month) ?? 1..<31)
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let leadingEmpty = Array(repeating: Optional<Int>.none, count: leadingCount)
        let trailingEmptyCount: Int = {
            let total = leadingEmpty.count + days.count
            let remainder = total % 7
            return remainder == 0 ? 0 : 7 - remainder
        }()
        let trailingEmpty = Array(repeating: Optional<Int>.none, count: trailingEmptyCount)
        return leadingEmpty + days.map { Optional($0) } + trailingEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(monthFormatter.string(from: month))
                .font(.title3.bold())

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 12) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(dayGrid.enumerated()), id: \.offset) { _, day in
                    CalendarDayCell(
                        day: day,
                        events: day.flatMap { eventsByDay[$0] } ?? []
                    )
                }
            }
        }
    }
}

private struct CalendarDayCell: View {
    let day: Int?
    let events: [AttendedEvent]

    var body: some View {
        VStack(spacing: 6) {
            if let day {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(width: 40, height: 40)

                    if let event = events.first {
                        eventThumbnail(for: event)
                    }

                    if events.count > 1 {
                        Text("\(events.count)")
                            .font(.caption2.bold())
                            .padding(4)
                            .background(Color.black.opacity(0.75), in: Circle())
                            .foregroundStyle(.white)
                            .offset(x: 12, y: 12)
                    }
                }
                Text("\(day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Color.clear
                    .frame(height: 48)
            }
        }
    }

    @ViewBuilder
    private func eventThumbnail(for event: AttendedEvent) -> some View {
        if let coverName = event.coverImageName, UIImage(named: coverName) != nil {
            Image(coverName)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                )
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.8), .pink.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.white)
                )
        }
    }
}

private struct FriendsSheetView: View {
    let profile: UserProfile

    var body: some View {
        NavigationStack {
            List {
                Section("Your Friends") {
                    ForEach(profile.friends) { friend in
                        FriendRow(friend: friend, isOnApp: true)
                    }
                }

                Section("Invite Contacts") {
                    ForEach(profile.suggestedContacts) { contact in
                        FriendRow(friend: Friend(id: contact.id, name: contact.name, avatarURL: nil), isOnApp: contact.isOnApp)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}

private struct FriendRow: View {
    let friend: Friend
    let isOnApp: Bool

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.85), .purple.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Text(friend.initials)
                        .font(.headline)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(.body.weight(.semibold))
                Text(isOnApp ? "On Simple Events" : "Invite to join")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isOnApp {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Invite") { }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemBackground))
                    )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "slider.horizontal.3")
                    .font(.largeTitle)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: Circle())
                Text("Settings coming soon")
                    .font(.title2.bold())
                Text("We’ll let you customize notifications, privacy, and more right here.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}
