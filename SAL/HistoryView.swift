import SwiftUI

struct HistoryView: View {
    @Environment(ChatHistoryStore.self) private var history
    @State private var confirmsClearAll = false

    var body: some View {
        NavigationStack {
            Group {
                if history.conversations.isEmpty {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your chats with SAL are saved here, on this device only.")
                    )
                } else {
                    List {
                        ForEach(history.conversations) { conversation in
                            NavigationLink(value: conversation) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text("\(conversation.state.name) · \(conversation.updatedAt.formatted(.relative(presentation: .named)))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete(perform: history.delete)
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Conversation.self) { conversation in
                ConversationDetailView(conversation: conversation)
            }
            .toolbar {
                if !history.conversations.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear All", role: .destructive) { confirmsClearAll = true }
                    }
                }
            }
            .confirmationDialog("Delete all conversations?", isPresented: $confirmsClearAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive, action: history.deleteAll)
            } message: {
                Text("This can’t be undone.")
            }
        }
    }
}

private struct ConversationDetailView: View {
    let conversation: Conversation

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(conversation.messages) { message in
                    MessageBubble(message: message)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    HistoryView()
        .environment(ChatHistoryStore(fileName: "preview-history.json"))
}
