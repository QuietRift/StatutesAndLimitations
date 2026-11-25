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

    /// The language SAL listens in. Replies follow whatever language the person uses.
    var language = SpeechLanguage.current {
        didSet {
            SpeechLanguage.current = language
            speech.preferredLanguage = language
            // Restart listening so the new language takes effect right away.
            if mic.isListening {
                mic.stop()
                if handsFree { listenHandsFree() }
            }
        }
    }

    /// When on, SAL listens continuously for “Hey SAL” followed by a question,
    /// and starts listening again after each answer.
    var handsFree = false {
        didSet {
            guard handsFree != oldValue else { return }
            if !handsFree {
                stopHandsFree()
            } else if !isEnablingHandsFree {
                listenHandsFree()
            }
        }
    }

    /// True once “Hey SAL” has been heard and SAL is capturing the question.
    private(set) var heardWakeWord = false

    /// Set when the on-device model can't be used on this device.
    let unavailableMessage: String?

    @ObservationIgnored private let history: ChatHistoryStore
    @ObservationIgnored private var responder: (any ChatResponder)?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var conversationID = UUID()
    /// Where the question starts in the hands-free transcript; nil until the wake word is heard.
    @ObservationIgnored private var questionStart: Int?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var isEnablingHandsFree = false

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
        speech.preferredLanguage = language
        mic.onTranscript = { [weak self] text in self?.handleHandsFreeTranscript(text) }
        speech.onFinishedSpeaking = { [weak self] in self?.resumeHandsFreeIfNeeded() }
    }

    var orbMode: PulsingOrb.Mode {
        if speech.isSpeaking { return .speaking }
        if isThinking { return .thinking }
        // While waiting for “Hey SAL”, the orb rests instead of looking like it's taking a question.
        if mic.isListening && (!handsFree || heardWakeWord) { return .listening }
        return .idle
    }

    var isWaitingForWakeWord: Bool { handsFree && mic.isListening && !heardWakeWord }

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
        if handsFree {
            // In hands-free mode the mic button skips the wake word, or sends what's been said so far.
            if heardWakeWord { finishHandsFreeQuestion() } else { listenHandsFree(skipWakeWord: true) }
            return
        }
        if mic.isListening {
            // Send whatever was heard when the person taps the mic again.
            send(mic.stop())
            return
        }
        speech.stop()
        Task {
            do {
                try await mic.start(language: language)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Interrupts SAL mid-sentence.
    func stopSpeaking() {
        speech.stop()
        resumeHandsFreeIfNeeded()
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isThinking else { return }
        guard let responder else {
            errorMessage = unavailableMessage
            return
        }

        speech.stop()
        mic.stop()
        heardWakeWord = false
        // The model answers in the question's language, so voice the reply in that language.
        speech.languageHint = SpeechLanguage.detectLanguage(of: prompt) ?? language.languageCode
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
            // A cancelled reply belongs to a conversation that was already reset.
            guard !Task.isCancelled else { return }
            isThinking = false
            saveToHistory()
            resumeHandsFreeIfNeeded()
        }
    }

    private func saveToHistory() {
        guard hasConversation else { return }
        history.save(Conversation(id: conversationID, state: state, updatedAt: .now, messages: messages))
    }

    // MARK: - Hands-free (“Hey SAL”)

    /// Matches “Hey SAL” and the ways speech recognition tends to spell it, in several languages.
    private static let wakePhrase = /\b(?:hey|hi|hay|ey|ok|okay|oye|hé|hallo)[\s,.!]*(?:sal|saul|sol|sahl|sall)\b/.ignoresCase()

    /// Starts listening for “Hey SAL”, or for a question directly when `skipWakeWord` is set
    /// (for example after tapping the mic or “Talk to SAL” in CarPlay).
    func listenHandsFree(skipWakeWord: Bool = false) {
        guard unavailableMessage == nil else {
            errorMessage = unavailableMessage
            handsFree = false
            return
        }
        if !handsFree {
            isEnablingHandsFree = true
            handsFree = true
            isEnablingHandsFree = false
        }
        speech.stop()
        silenceTask?.cancel()
        heardWakeWord = skipWakeWord
        questionStart = skipWakeWord ? 0 : nil
        guard !isThinking else { return }
        Task {
            do {
                try await mic.start(language: language)
            } catch {
                errorMessage = error.localizedDescription
                handsFree = false
            }
        }
    }

    private func stopHandsFree() {
        silenceTask?.cancel()
        heardWakeWord = false
        questionStart = nil
        mic.stop()
    }

    private func resumeHandsFreeIfNeeded() {
        guard handsFree, !isThinking, !speech.isSpeaking, !mic.isListening else { return }
        listenHandsFree()
    }

    private func handleHandsFreeTranscript(_ text: String) {
        guard handsFree else { return }
        if questionStart == nil, let match = text.firstMatch(of: Self.wakePhrase) {
            questionStart = text.distance(from: text.startIndex, to: match.range.upperBound)
            heardWakeWord = true
        }
        guard let questionStart else { return }

        // Send once the person pauses. Allow longer if they've only said “Hey SAL” so far.
        let question = Self.cleanQuestion(String(text.dropFirst(questionStart)))
        silenceTask?.cancel()
        silenceTask = Task {
            try? await Task.sleep(for: .seconds(question.isEmpty ? 6 : 1.6))
            guard !Task.isCancelled else { return }
            finishHandsFreeQuestion()
        }
    }

    private func finishHandsFreeQuestion() {
        silenceTask?.cancel()
        let question = Self.cleanQuestion(String(mic.stop().dropFirst(questionStart ?? 0)))
        questionStart = nil
        heardWakeWord = false
        if question.isEmpty {
            resumeHandsFreeIfNeeded()
        } else {
            send(question)
        }
    }

    private static func cleanQuestion(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // MARK: - Speaking while streaming

    /// Speaks the first sentence as soon as it streams in so SAL responds quickly. The rest is
    /// held back and spoken as one utterance at the end, which keeps intonation flowing
    /// instead of resetting at every sentence. Returns the new count of spoken characters.
    private func speakCompletedSentences(in text: String, from spokenCount: Int) -> Int {
        guard speaksReplies, spokenCount == 0 else { return spokenCount }
        // A sentence ends at . ! ? (or 。！？) followed by whitespace, so "257.625" isn't split.
        guard let match = text.firstMatch(of: /[.!?。！？]["”']?\s/) else { return spokenCount }
        let sentence = text[..<match.range.upperBound]
        speech.speak(String(sentence))
        return sentence.count
    }

    private func speakRemainder(of text: String, from spokenCount: Int) {
        guard speaksReplies, spokenCount < text.count else { return }
        speech.speak(String(text.dropFirst(spokenCount)))
    }

    /// Stops the mic and voice without abandoning a reply that's still generating,
    /// for example when the person switches tabs. Hands-free resumes on `resumeAudio()`.
    func pauseAudio() {
        silenceTask?.cancel()
        mic.stop()
        speech.stop()
    }

    func resumeAudio() {
        resumeHandsFreeIfNeeded()
    }

    func tearDown() {
        replyTask?.cancel()
        replyTask = nil
        isThinking = false
        pauseAudio()
    }
}
