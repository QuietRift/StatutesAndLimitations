import AppIntents
import Foundation

/// Lets people ask SAL through Siri (“Hey Siri, ask SAL”), including hands-free and in CarPlay.
/// Siri asks for the question, SAL answers on-device, and Siri reads the answer aloud.
struct AskSALIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask SAL"
    static let description = IntentDescription("Ask SAL a question about traffic laws, traffic stops, or your rights on the road.")

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask SAL?")
    var question: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let savedCode = UserDefaults.standard.string(forKey: "sal.selectedState") ?? USState.michigan.rawValue
        let state = USState(rawValue: savedCode) ?? .michigan

        let responder: any ChatResponder
        switch LocalAssistant.makeResponder(for: state) {
        case .success(let ready): responder = ready
        case .failure(let reason): throw AskSALError(message: reason.message)
        }
        let answer = try await responder.reply(to: question)

        // Saving happens last, after anything that could make Siri re-run this intent.
        await MainActor.run {
            ChatHistoryStore.shared.save(Conversation(
                state: state,
                updatedAt: .now,
                messages: [ChatMessage(role: .user, text: question), ChatMessage(role: .assistant, text: answer)]
            ))
        }
        return .result(value: answer, dialog: "\(answer)")
    }
}

private struct AskSALError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

struct SALShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskSALIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Ask SAL",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )
    }
}
