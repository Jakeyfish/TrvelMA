import Foundation
import SwiftData

/// Local account metadata. Passwords are kept in Keychain, never in the database.
@Model
final class LocalAccount {
    @Attribute(.unique) var email: String
    var salutation: String = ""
    var phone: String
    var createdAt: Date
    var updatedAt: Date
    /// Stable identifier reserved for synchronization with a future server account.
    @Attribute(.unique) var syncID: String
    var schemaVersion: Int
    var syncState: Int

    init(email: String, salutation: String = "", phone: String, createdAt: Date = .now) {
        self.email = email
        self.salutation = salutation
        self.phone = phone
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.syncID = UUID().uuidString.lowercased()
        self.schemaVersion = 1
        self.syncState = 0
    }
}
