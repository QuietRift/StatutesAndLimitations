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

    /// The listening language; its region breaks ties between voices (e.g. US Spanish over Spain).
    @ObservationIgnored var preferredLanguage = SpeechLanguage.current
    /// The language expected for the next reply, used when a chunk is too short to detect.
    @ObservationIgnored var languageHint: String?
    /// Called when the last queued utterance finishes on its own (not when stopped).
    @ObservationIgnored var onFinishedSpeaking: (() -> Void)?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var pendingUtterances = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let cleaned = Self.cleanForSpeech(text)
        guard !cleaned.isEmpty else { return }
        if pendingUtterances == 0 { Self.configureSessionForSpeech() }

        let languageCode = SpeechLanguage.detectLanguage(of: cleaned) ?? languageHint ?? preferredLanguage.languageCode
        languageHint = languageCode

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = Self.bestVoice(for: languageCode, preferredRegion: preferredLanguage.locale.region?.identifier)
        // A touch slower than default with no extra gaps reads more like a person talking.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        utterance.prefersAssistiveTechnologySettings = true
        pendingUtterances += 1
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private static var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    /// The most natural installed voice for a language: Premium, then Enhanced, then the default,
    /// preferring the listener's region (and the US) when several regions exist.
    /// People can download Premium voices in Settings › Accessibility › Spoken Content › Voices.
    private static func bestVoice(for languageCode: String, preferredRegion: String?) -> AVSpeechSynthesisVoice? {
        let cacheKey = "\(languageCode)|\(preferredRegion ?? "")"
        if let cached = voiceCache[cacheKey] { return cached }

        // NaturalLanguage reports Chinese by script; voices are tagged by region.
        let voicePrefix = switch languageCode {
        case "zh-Hans": "zh-CN"
        case "zh-Hant": "zh-TW"
        default: languageCode
        }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            ($0.language == voicePrefix || $0.language.hasPrefix(voicePrefix + "-"))
                && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            var score = voice.quality.rawValue * 10
            if let preferredRegion, voice.language.hasSuffix("-" + preferredRegion) { score += 3 }
            if voice.language.hasSuffix("-US") { score += 1 }
            return score
        }
        let voice = candidates.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: voicePrefix)
        voiceCache[cacheKey] = voice
        return voice
    }

    /// Uses the spoken-audio playback mode, which is tuned for voice and avoids the
    /// thinner sound of the record-enabled session used while listening.
    private static func configureSessionForSpeech() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    /// Strips formatting the model sometimes adds so the voice doesn't read symbols aloud.
    private static func cleanForSpeech(_ text: String) -> String {
        var result = text
        for symbol in ["**", "__", "`", "#", "* ", "- "] {
            result = result.replacingOccurrences(of: symbol, with: symbol.hasSuffix(" ") ? " " : "")
        }
        return result
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pendingUtterances = 0
        isSpeaking = false
    }

    private func utteranceEnded(finished: Bool) {
        let wasSpeaking = isSpeaking
        pendingUtterances = max(0, pendingUtterances - 1)
        isSpeaking = pendingUtterances > 0
        if finished, wasSpeaking, !isSpeaking { onFinishedSpeaking?() }
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.wordBeat &+= 1 }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded(finished: true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded(finished: false) }
    }
}

/// Transcribes the microphone so the person can talk to SAL.
///
/// Uses `SpeechAnalyzer` and `SpeechTranscriber`, which run entirely on the device.
/// Audio and transcripts are never sent to Apple, and only microphone permission is needed.
/// (The older `SFSpeechRecognizer` shows a system prompt saying speech goes to Apple.)
@MainActor
@Observable
final class SpeechInput {
    enum InputError: LocalizedError {
        case notAuthorized, unavailable
        case languageUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Allow microphone access in Settings to talk to SAL."
            case .unavailable: "On-device speech recognition isn’t available on this device. You can type instead."
            case .languageUnavailable(let name): "SAL can’t listen in \(name) on this device yet. Choose another language or type instead."
            }
        }
    }

    private(set) var isListening = false
    private(set) var transcript = ""
    /// Called with the full transcript every time it changes, while listening.
    @ObservationIgnored var onTranscript: ((String) -> Void)?

    /// Holds an `OnDeviceTranscription`; typed loosely because that class needs iOS 26.
    @ObservationIgnored private var transcription: AnyObject?
    /// Bumped by every start and stop so a slow start that's been superseded can tell.
    @ObservationIgnored private var generation = 0

    func start(language: SpeechLanguage) async throws {
        guard #available(iOS 26.0, *) else { throw InputError.unavailable }
        stop()
        generation += 1
        let startGeneration = generation
        guard await AVAudioApplication.requestRecordPermission() else { throw InputError.notAuthorized }
        guard startGeneration == generation else { return }

        transcript = ""
        let transcription = OnDeviceTranscription()
        self.transcription = transcription
        try await transcription.start(language: language) { [weak self] text in
            guard let self, self.isListening else { return }
            self.transcript = text
            self.onTranscript?(text)
        }
        // stop() or another start() was called while this one was still setting up.
        guard startGeneration == generation else {
            transcription.stop()
            return
        }
        isListening = true
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stop() -> String {
        generation += 1
        if #available(iOS 26.0, *), let transcription = transcription as? OnDeviceTranscription {
            transcription.stop()
        }
        transcription = nil
        isListening = false
        return transcript
    }
}

@available(iOS 26.0, *)
@MainActor
private final class OnDeviceTranscription {
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    func start(language: SpeechLanguage, onText: @escaping @MainActor (String) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else { throw SpeechInput.InputError.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
            throw SpeechInput.InputError.languageUnavailable(language.nativeName)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

        // The speech model is downloaded once from Apple if it isn't already on the device.
        // This only downloads; no audio is uploaded.
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechInput.InputError.unavailable
        }

        // Finalized phrases accumulate; the in-progress (volatile) phrase is shown after them.
        resultsTask = Task {
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        onText(finalized)
                    } else {
                        onText(finalized + text)
                    }
                }
            } catch {}
        }

        let (inputs, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: inputs)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Convert microphone buffers to the analyzer's format and feed them in.
        let input = audioEngine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: format) else {
            throw SpeechInput.InputError.unavailable
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, with: converter, to: format) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Resamples a microphone buffer into the format the speech model expects.
    private nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        inputContinuation?.finish()
        inputContinuation = nil
        let analyzer = analyzer
        let resultsTask = resultsTask
        self.analyzer = nil
        self.resultsTask = nil
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            resultsTask?.cancel()
        }
    }
}
