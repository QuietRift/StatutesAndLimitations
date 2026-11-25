import AVFoundation
import Observation
import Speech

/// Reads assistant replies aloud and reports when speech is happening so the orb can pulse.
@MainActor
@Observable
final class SpeechOutput: NSObject {
    private(set) var isSpeaking = false
    /// Increments on every spoken word; the orb uses it to add a beat to its pulse.
    private(set) var wordBeat = 0

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var pendingUtterances = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        pendingUtterances += 1
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pendingUtterances = 0
        isSpeaking = false
    }

    private func utteranceEnded() {
        pendingUtterances = max(0, pendingUtterances - 1)
        isSpeaking = pendingUtterances > 0
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.wordBeat &+= 1 }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }
}

/// Transcribes the microphone on-device so the person can talk to SAL.
@MainActor
@Observable
final class SpeechInput {
    enum InputError: LocalizedError {
        case notAuthorized, unavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Allow microphone and speech recognition access in Settings to talk to SAL."
            case .unavailable: "On-device speech recognition isn’t available right now. You can type instead."
            }
        }
    }

    private(set) var isListening = false
    private(set) var transcript = ""

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start() async throws {
        guard await Self.requestAuthorization() else { throw InputError.notAuthorized }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw InputError.unavailable
        }

        stop()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep everything on the device; nothing is sent to a server.
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if error != nil || isFinal { self.stop() }
            }
        }
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stop() -> String {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        return transcript
    }

    private static func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
