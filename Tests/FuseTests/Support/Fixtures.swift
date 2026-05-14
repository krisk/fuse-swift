import Foundation

struct Author: Sendable, Codable, Equatable {
    let firstName: String
    let lastName: String?
}

struct Book: Sendable, Codable, Equatable {
    let title: String
    let subtitle: String?
    let author: Author
}
