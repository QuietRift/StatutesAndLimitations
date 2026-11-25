import Foundation
import FoundationModels

/// Streams replies from a local, on-device language model.
protocol ChatResponder {
    /// Yields the full response text so far each time new tokens arrive.
    func streamReply(to prompt: String) -> AsyncThrowingStream<String, Error>
}

enum LocalAssistant {
    /// Returns an on-device responder, or a user-facing reason why one isn't available.
    static func makeResponder(for state: USState) -> Result<any ChatResponder, UnavailableReason> {
        guard #available(iOS 26.0, *) else { return .failure(.osTooOld) }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .success(FoundationModelResponder(state: state))
        case .unavailable(.deviceNotEligible):
            return .failure(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .failure(.appleIntelligenceDisabled)
        case .unavailable(.modelNotReady):
            return .failure(.modelNotReady)
        case .unavailable:
            return .failure(.unknown)
        }
    }

    enum UnavailableReason: Error {
        case osTooOld, deviceNotEligible, appleIntelligenceDisabled, modelNotReady, unknown

        var message: String {
            switch self {
            case .osTooOld: "SAL’s assistant needs iOS 26 or later."
            case .deviceNotEligible: "This device doesn’t support the on-device model SAL uses."
            case .appleIntelligenceDisabled: "Turn on Apple Intelligence in Settings to talk with SAL."
            case .modelNotReady: "The on-device model is still downloading. Try again shortly."
            case .unknown: "The on-device model isn’t available right now."
            }
        }
    }
}

@available(iOS 26.0, *)
private final class FoundationModelResponder: ChatResponder {
    private let session: LanguageModelSession

    init(state: USState) {
        session = LanguageModelSession(instructions: """
            You are SAL (Statute & Limitations), a calm, friendly assistant that explains \
            traffic laws, traffic stops, and drivers’ rights in \(state.name). \
            Your replies are read aloud, so keep them short and conversational: \
            two to four sentences, plain language, no markdown, lists, or headings. \
            Give general legal information, not legal advice, and suggest contacting a \
            licensed \(state.name) attorney for a specific situation. \
            If you’re unsure of a specific statute or penalty, say so instead of guessing. \
            For emergencies, tell the person to call 911.
            """)
        session.prewarm()
    }

    func streamReply(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
