import Foundation
import Observation

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    let role: Role
    var text: String
}

struct Conversation: Identifiable, Codable, Hashable {
    var id = UUID()
    let state: USState
    var updatedAt: Date
    var messages: [ChatMessage]

    /// The first question asked, used as the conversation's title in History.
    var title: String {
        messages.first { $0.role == .user }?.text ?? "Conversation"
    }
}

/// Keeps past conversations on this device only, as JSON in Application Support.
@MainActor
@Observable
final class ChatHistoryStore {
    /// One store shared by the phone UI, CarPlay, and Siri so none overwrites the others' saves.
    static let shared = ChatHistoryStore()

    private(set) var conversations: [Conversation] = []

    @ObservationIgnored private let fileURL: URL

    init(fileName: String = "chat-history.json") {
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: fileName)
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = saved
        }
    }

    /// Inserts or updates a conversation and moves it to the top of the list.
    func save(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        conversations.remove(atOffsets: offsets)
        persist()
    }

    func deleteAll() {
        conversations.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
