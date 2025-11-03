import Foundation

/// Simple cache manager for storing and retrieving app data
actor CacheManager {
    static let shared = CacheManager()

    private let userDefaults = UserDefaults.standard
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    private init() {
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonDecoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Generic Cache Methods

    func save<T: Codable>(_ value: T, forKey key: String) {
        do {
            let data = try jsonEncoder.encode(value)
            userDefaults.set(data, forKey: key)
            userDefaults.set(Date(), forKey: "\(key)_timestamp")
            print("[Cache] ✅ Saved \(key)")
        } catch {
            print("[Cache] ❌ Failed to save \(key): \(error)")
        }
    }

    func load<T: Codable>(forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else {
            print("[Cache] ⚠️ No cache found for \(key)")
            return nil
        }

        do {
            let value = try jsonDecoder.decode(T.self, from: data)
            print("[Cache] ✅ Loaded \(key)")
            return value
        } catch {
            print("[Cache] ❌ Failed to load \(key): \(error)")
            return nil
        }
    }

    func getCacheAge(forKey key: String) -> TimeInterval? {
        guard let timestamp = userDefaults.object(forKey: "\(key)_timestamp") as? Date else {
            return nil
        }
        return Date().timeIntervalSince(timestamp)
    }

    func isCacheStale(forKey key: String, maxAge: TimeInterval = 300) -> Bool {
        guard let age = getCacheAge(forKey: key) else {
            return true
        }
        return age > maxAge
    }

    func clear(key: String) {
        userDefaults.removeObject(forKey: key)
        userDefaults.removeObject(forKey: "\(key)_timestamp")
        print("[Cache] 🗑️ Cleared \(key)")
    }

    func clearAll() {
        let keys = ["feed_events", "event_photos", "event_comments"]
        keys.forEach { key in
            userDefaults.removeObject(forKey: key)
            userDefaults.removeObject(forKey: "\(key)_timestamp")
        }
        print("[Cache] 🗑️ Cleared all caches")
    }
}

// MARK: - Cache Keys
extension CacheManager {
    static let feedEventsKey = "feed_events"
    static func photosKey(eventId: String) -> String {
        "event_photos_\(eventId)"
    }
    static func commentsKey(eventId: String) -> String {
        "event_comments_\(eventId)"
    }
}
