import Foundation
import CoreLocation

struct PendingInvite: Identifiable {
    let id: UUID
    var name: String
    var direction: Direction
    var contact: String?

    enum Direction: String {
        case sent
        case received
    }

    init(id: UUID = UUID(), name: String, direction: Direction, contact: String? = nil) {
        self.id = id
        self.name = name
        self.direction = direction
        self.contact = contact
    }
}

struct AttendedEvent: Identifiable {
    let id: UUID
    let eventID: UUID
    let date: Date
    let title: String
    let location: String
    let startAt: Date?
    let endAt: Date?
    let coverImageName: String?
    let coverImageURL: URL?

    init(id: UUID = UUID(), eventID: UUID, date: Date, title: String, location: String, startAt: Date? = nil, endAt: Date? = nil, coverImageName: String? = nil, coverImageURL: URL? = nil) {
        self.id = id
        self.eventID = eventID
        self.date = date
        self.title = title
        self.location = location
        self.startAt = startAt
        self.endAt = endAt
        self.coverImageName = coverImageName
        self.coverImageURL = coverImageURL
    }
}

struct ProfileStats {
    var hostedCount: Int
    var attendedCount: Int
    var friendCount: Int
    var invitesSent: Int
}

struct UserProfile {
    var id: UUID
    var displayName: String
    var username: String
    var bio: String
    var phoneNumber: String?
    var joinDate: Date
    var primaryLocation: CLLocation?
    var photoURL: URL?
    var friends: [Friend]
    var pendingInvites: [PendingInvite]
    var attendedEvents: [AttendedEvent]
    var stats: ProfileStats
}

enum ProfileRepository {
    static let calendar = Calendar(identifier: .gregorian)

    static var focusMonth: Date {
        calendar.date(from: DateComponents(year: 2025, month: 10, day: 1)) ?? .now
    }

    static let sampleProfile: UserProfile = {
        let friends = EventRepository.friends

        return UserProfile(
            id: UUID(uuidString: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942")!,
            displayName: "Bharath Raghunath",
            username: "@bharathraghunath",
            bio: "Building a shared event feed with friends.",
            phoneNumber: nil,
            joinDate: calendar.date(from: DateComponents(year: 2023, month: 5, day: 12)) ?? .now,
            primaryLocation: nil,
            photoURL: nil,
            friends: friends,
            pendingInvites: [],
            attendedEvents: [],
            stats: ProfileStats(
                hostedCount: 0,
                attendedCount: 0,
                friendCount: friends.count,
                invitesSent: 0
            )
        )
    }()
}
