import SwiftUI

/// The app's home after onboarding: Chat, Laws At A Glance, and History.
struct MainTabView: View {
    @Binding var stateCode: String

    private enum AppTab: Hashable { case chat, laws, history }

    @State private var selectedTab = AppTab.chat
    @State private var history = ChatHistoryStore.shared
    @State private var pendingQuestion: String?

    private var state: USState { USState(rawValue: stateCode) ?? .michigan }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView(state: state, history: history, pendingQuestion: $pendingQuestion) { newState in
                stateCode = newState.rawValue
            }
            // Rebuild the chat when the state changes so SAL's instructions match it.
            .id(state)
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }
            .tag(AppTab.chat)

            LawsAtAGlanceView(state: state) { question in
                pendingQuestion = question
                selectedTab = .chat
            }
            .tabItem { Label("Laws At A Glance", systemImage: "book.closed.fill") }
            .tag(AppTab.laws)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
        }
        .environment(history)
    }
}

#Preview {
    MainTabView(stateCode: .constant("MI"))
}
