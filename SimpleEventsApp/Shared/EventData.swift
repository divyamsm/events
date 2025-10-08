import Foundation
import CoreLocation

struct Friend: Identifiable, Hashable {
    let id: UUID
    var name: String
    var avatarURL: URL?

    var initials: String {
        let components = name
            .split(separator: " ")
            .compactMap { $0.first }
        return String(components.prefix(2)).uppercased()
    }
}

struct UserSession {
    let user: Friend
    let currentLocation: CLLocation

    static let sample: UserSession = {
        let user = Friend(
            id: UUID(uuidString: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942")!,
            name: "You",
            avatarURL: nil
        )
        return UserSession(
            user: user,
            currentLocation: CLLocation(latitude: 37.7749, longitude: -122.4194)
        )
    }()
}

struct Event: Identifiable, Hashable {
    let id: UUID
    var title: String
    var date: Date
    var location: String
    var imageURL: URL
    var coordinate: CLLocationCoordinate2D?
    var attendingFriendIDs: [UUID]
    var invitedByFriendIDs: [UUID]
    var sharedInviteFriendIDs: [UUID]

    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        location: String,
        imageURL: URL,
        coordinate: CLLocationCoordinate2D? = nil,
        attendingFriendIDs: [UUID] = [],
        invitedByFriendIDs: [UUID] = [],
        sharedInviteFriendIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.location = location
        self.imageURL = imageURL
        self.coordinate = coordinate
        self.attendingFriendIDs = attendingFriendIDs
        self.invitedByFriendIDs = invitedByFriendIDs
        self.sharedInviteFriendIDs = sharedInviteFriendIDs
    }
    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Event {
    func distance(from location: CLLocation?) -> CLLocationDistance? {
        guard
            let coordinate,
            let location
        else {
            return nil
        }

        let eventLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: eventLocation)
    }
}

enum EventRepository {
    static let currentUser = UserSession.sample.user

    private static let friendDisha = Friend(
        id: UUID(uuidString: "F7B10C18-5A0F-4C16-ABF3-8DFD52E3E570")!,
        name: "Disha Kapoor",
        avatarURL: URL(string: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=400&q=80")
    )

    private static let friendDivyam = Friend(
        id: UUID(uuidString: "02D4F551-8C88-4A58-9783-BA5B4B4AD9B6")!,
        name: "Divyam Mehta",
        avatarURL: URL(string: "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80")
    )

    private static let friendShreyas = Friend(
        id: UUID(uuidString: "A9A796D4-5EE0-4FC9-9C03-FA041E3C0E9B")!,
        name: "Shreyas Iyer",
        avatarURL: URL(string: "https://images.unsplash.com/photo-1529665253569-6d01c0eaf7b6?auto=format&fit=crop&w=400&q=80")
    )

    private static let friendJordan = Friend(
        id: UUID(uuidString: "1E3FC403-346F-4ADC-8B3E-359BAAF343B5")!,
        name: "Jordan Lee",
        avatarURL: URL(string: "https://images.unsplash.com/photo-1614287946122-7caa6d31bcb4?auto=format&fit=crop&w=400&q=80")
    )

    private static let friendMaya = Friend(
        id: UUID(uuidString: "6B7C5D7E-1D90-4FD0-8B7E-75E0A9A9B415")!,
        name: "Maya Chen",
        avatarURL: URL(string: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80")
    )

    static let friends: [Friend] = [
        friendDisha,
        friendDivyam,
        friendShreyas,
        friendJordan,
        friendMaya
    ]

    static let sampleEvents: [Event] = [
        Event(
            id: UUID(uuidString: "A2D2B22B-5C36-4E67-8F41-1F68A39F8E03")!,
            title: "Swift Meetup",
            date: .now.addingTimeInterval(60 * 60 * 24 * 2),
            location: "San Francisco, CA",
            imageURL: URL(string: "https://images.unsplash.com/photo-1521737604893-d14cc237f11d?auto=format&fit=crop&w=1400&q=80")!,
            coordinate: CLLocationCoordinate2D(latitude: 37.776_321, longitude: -122.417_864),
            attendingFriendIDs: [friendDisha.id, friendDivyam.id],
            invitedByFriendIDs: [friendShreyas.id]
        ),
        Event(
            id: UUID(uuidString: "D354D6E7-885C-4949-A2D7-0C79431635F7")!,
            title: "UI Design Workshop",
            date: .now.addingTimeInterval(60 * 60 * 24 * 7),
            location: "Remote",
            imageURL: URL(string: "https://images.unsplash.com/photo-1522202176988-66273c2fd55f?auto=format&fit=crop&w=1400&q=80")!,
            coordinate: nil,
            attendingFriendIDs: [friendMaya.id],
            invitedByFriendIDs: []
        ),
        Event(
            id: UUID(uuidString: "8C7B1B8F-6F02-49DA-AB43-6C45CE3631DC")!,
            title: "Hackathon",
            date: .now.addingTimeInterval(60 * 60 * 24 * 14),
            location: "New York, NY",
            imageURL: URL(string: "https://images.unsplash.com/photo-1545239351-1141bd82e8a6?auto=format&fit=crop&w=1400&q=80")!,
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.006),
            attendingFriendIDs: [friendJordan.id],
            invitedByFriendIDs: []
        )
    ]
}
