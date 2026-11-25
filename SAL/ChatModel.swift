import Foundation
import Observation

@MainActor
@Observable
final class ChatModel {
    typealias Message = ChatMessage

    let state: USState
    let speech = SpeechOutput()
    let mic = SpeechInput()

    private(set) var messages: [Message] = []
    private(set) var isThinking = false
    var draft = ""
    var errorMessage: String?
    var speaksReplies = true

    /// Set when the on-device model can't be used on this device.
    let unavailableMessage: String?

    @ObservationIgnored private let history: ChatHistoryStore
    @ObservationIgnored private var responder: (any ChatResponder)?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var conversationID = UUID()

    init(state: USState, history: ChatHistoryStore) {
        self.state = state
        self.history = history
        switch LocalAssistant.makeResponder(for: state) {
        case .success(let responder):
            self.responder = responder
            unavailableMessage = nil
        case .failure(let reason):
            responder = nil
            unavailableMessage = reason.message
        }
    }

    var orbMode: PulsingOrb.Mode {
        if speech.isSpeaking { return .speaking }
        if mic.isListening { return .listening }
        if isThinking { return .thinking }
        return .idle
    }

    var hasConversation: Bool { messages.contains { $0.role == .user } }

    /// Greets the person once when the chat first appears.
    func greetIfNeeded() {
        guard messages.isEmpty else { return }
        let greeting = unavailableMessage
            ?? "Hi, I’m SAL. Ask me anything about traffic stops, traffic laws, or your rights on the road in \(state.name)."
        messages.append(Message(role: .assistant, text: greeting))
        if speaksReplies { speech.speak(greeting) }
    }

    /// Starts a fresh conversation. The previous one stays in History.
    func startNewChat() {
        tearDown()
        messages = []
        conversationID = UUID()
        // A new session so the model doesn't carry context over from the last conversation.
        if case .success(let responder) = LocalAssistant.makeResponder(for: state) {
            self.responder = responder
        }
        greetIfNeeded()
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        send(text)
    }

    func toggleListening() {
        if mic.isListening {
            // Send whatever was heard when the person taps the mic again.
            send(mic.stop())
            return
        }
        speech.stop()
        Task {
            do {
                try await mic.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Interrupts SAL mid-sentence.
    func stopSpeaking() {
        speech.stop()
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isThinking else { return }
        guard let responder else {
            errorMessage = unavailableMessage
            return
        }

        speech.stop()
        messages.append(Message(role: .user, text: prompt))
        let reply = Message(role: .assistant, text: "")
        messages.append(reply)
        isThinking = true

        replyTask = Task {
            var spokenCount = 0
            do {
                for try await partial in responder.streamReply(to: prompt) {
                    // Look the reply up by ID; the conversation may have been reset mid-stream.
                    guard let index = messages.firstIndex(where: { $0.id == reply.id }) else { break }
                    messages[index].text = partial
                    spokenCount = speakCompletedSentences(in: partial, from: spokenCount)
                }
                if let finished = messages.first(where: { $0.id == reply.id }) {
                    speakRemainder(of: finished.text, from: spokenCount)
                }
            } catch {
                if let index = messages.firstIndex(where: { $0.id == reply.id }), messages[index].text.isEmpty {
                    messages.remove(at: index)
                }
                if !(error is CancellationError) {
                    errorMessage = "SAL couldn’t answer that. \(error.localizedDescription)"
                }
            }
            isThinking = false
            saveToHistory()
        }
    }

    private func saveToHistory() {
        guard hasConversation else { return }
        history.save(Conversation(id: conversationID, state: state, updatedAt: .now, messages: messages))
    }

    // MARK: - Speaking while streaming

    /// Speaks the first sentence as soon as it streams in so SAL responds quickly. The rest is
    /// held back and spoken as one utterance at the end, which keeps intonation flowing
    /// instead of resetting at every sentence. Returns the new count of spoken characters.
    private func speakCompletedSentences(in text: String, from spokenCount: Int) -> Int {
        guard speaksReplies, spokenCount == 0 else { return spokenCount }
        // A sentence ends at . ! or ? followed by whitespace, so "257.625" or "e.g.," aren't split.
        guard let match = text.firstMatch(of: /[.!?]["”']?\s/) else { return spokenCount }
        let sentence = text[..<match.range.upperBound]
        speech.speak(String(sentence))
        return sentence.count
    }

    private func speakRemainder(of text: String, from spokenCount: Int) {
        guard speaksReplies, spokenCount < text.count else { return }
        speech.speak(String(text.dropFirst(spokenCount)))
    }

    /// Stops the mic and voice without abandoning a reply that's still generating,
    /// for example when the person switches tabs.
    func pauseAudio() {
        mic.stop()
        speech.stop()
    }

    func tearDown() {
        replyTask?.cancel()
        replyTask = nil
        isThinking = false
        pauseAudio()
    }
}
