import Foundation

struct Event: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let location: String

    init(id: UUID = UUID(), title: String, date: Date, location: String) {
        self.id = id
        self.title = title
        self.date = date
        self.location = location
    }
}

enum EventRepository {
    static let sampleEvents: [Event] = [
        Event(id: UUID(uuidString: "A2D2B22B-5C36-4E67-8F41-1F68A39F8E03")!,
              title: "Swift Meetup",
              date: .now.addingTimeInterval(60 * 60 * 24 * 2),
              location: "San Francisco"),
        Event(id: UUID(uuidString: "D354D6E7-885C-4949-A2D7-0C79431635F7")!,
              title: "UI Design Workshop",
              date: .now.addingTimeInterval(60 * 60 * 24 * 7),
              location: "Remote"),
        Event(id: UUID(uuidString: "8C7B1B8F-6F02-49DA-AB43-6C45CE3631DC")!,
              title: "Hackathon",
              date: .now.addingTimeInterval(60 * 60 * 24 * 14),
              location: "New York")
    ]
}
