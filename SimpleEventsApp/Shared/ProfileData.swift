import Foundation
import CoreLocation

struct Contact: Identifiable {
    let id: UUID
    var name: String
    var isOnApp: Bool
    var initials: String

    init(id: UUID = UUID(), name: String, isOnApp: Bool) {
        self.id = id
        self.name = name
        self.isOnApp = isOnApp
        let components = name.split(separator: " ").compactMap { $0.first }
        self.initials = String(components.prefix(2)).uppercased()
    }
}

struct AttendedEvent: Identifiable {
    let id: UUID
    let eventID: UUID
    let date: Date
    let coverImageName: String?

    init(id: UUID = UUID(), eventID: UUID, date: Date, coverImageName: String? = nil) {
        self.id = id
        self.eventID = eventID
        self.date = date
        self.coverImageName = coverImageName
    }
}

struct UserProfile {
    var displayName: String
    var username: String
    var bio: String
    var joinDate: Date
    var primaryLocation: CLLocation?
    var friends: [Friend]
    var suggestedContacts: [Contact]
    var attendedEvents: [AttendedEvent]
}

enum ProfileRepository {
    static let calendar = Calendar(identifier: .gregorian)

    static var focusMonth: Date {
        calendar.date(from: DateComponents(year: 2025, month: 10, day: 1)) ?? .now
    }

    static let sampleProfile: UserProfile = {
        let friends = EventRepository.friends

        let contacts: [Contact] = [
            Contact(name: "Priya Raman", isOnApp: false),
            Contact(name: "Marcus Taylor", isOnApp: false),
            Contact(name: "Evelyn Chen", isOnApp: true),
            Contact(name: "Carlos Mendez", isOnApp: false),
            Contact(name: "Sandra Holt", isOnApp: true)
        ]

        let attended: [AttendedEvent] = [
            AttendedEvent(
                eventID: EventRepository.sampleEvents[0].id,
                date: calendar.date(from: DateComponents(year: 2025, month: 10, day: 3)) ?? .now,
                coverImageName: "calendar-event-1"
            ),
            AttendedEvent(
                eventID: EventRepository.sampleEvents[1].id,
                date: calendar.date(from: DateComponents(year: 2025, month: 10, day: 9)) ?? .now,
                coverImageName: "calendar-event-2"
            ),
            AttendedEvent(
                eventID: EventRepository.sampleEvents[2].id,
                date: calendar.date(from: DateComponents(year: 2025, month: 10, day: 18)) ?? .now,
                coverImageName: nil
            )
        ]

        return UserProfile(
            displayName: "Bharath Raghunath",
            username: "@bharathraghunath",
            bio: "Building a shared event feed with friends.",
            joinDate: calendar.date(from: DateComponents(year: 2023, month: 5, day: 12)) ?? .now,
            primaryLocation: nil,
            friends: friends,
            suggestedContacts: contacts,
            attendedEvents: attended
        )
    }()
}
