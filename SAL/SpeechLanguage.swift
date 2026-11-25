import Foundation
import FoundationModels
import NaturalLanguage

/// A language SAL can listen in. Replies are spoken in whatever language they're written in.
struct SpeechLanguage: Identifiable, Hashable {
    /// A BCP-47 identifier such as "es-US".
    let id: String

    var locale: Locale { Locale(identifier: id) }
    var languageCode: String { locale.language.languageCode?.identifier ?? "en" }

    /// The language's own name, e.g. "Español", so people can find it whatever the app's language.
    var nativeName: String {
        (locale.localizedString(forLanguageCode: languageCode) ?? id).localizedCapitalized
    }

    /// A short label for compact controls, e.g. "ES".
    var shortCode: String { languageCode.uppercased() }

    private static let storageKey = "sal.listeningLanguage"

    /// Languages commonly spoken in the US. Regions favor US variants where they exist.
    private static let candidates = [
        "en-US", "es-US", "zh-CN", "vi-VN", "ar-SA", "fr-FR", "ko-KR",
        "pt-BR", "de-DE", "ja-JP", "it-IT", "hi-IN"
    ].map(SpeechLanguage.init)

    /// Candidates the on-device model can answer in. Listening support is checked when the mic starts.
    static var available: [SpeechLanguage] {
        guard #available(iOS 26.0, *) else { return [english] }
        let supported = candidates.filter { SystemLanguageModel.default.supportsLocale($0.locale) }
        return supported.isEmpty ? [english] : supported
    }

    static let english = SpeechLanguage(id: "en-US")

    /// The saved choice, or the phone's language if SAL supports it.
    static var current: SpeechLanguage {
        get {
            if let saved = UserDefaults.standard.string(forKey: storageKey) {
                return SpeechLanguage(id: saved)
            }
            let deviceCode = Locale.current.language.languageCode?.identifier
            return available.first { $0.languageCode == deviceCode } ?? english
        }
        set { UserDefaults.standard.set(newValue.id, forKey: storageKey) }
    }

    /// Detects the language of a piece of text, returning an `NLLanguage` code such as "es" or
    /// "zh-Hans". Returns nil when the text is too short or ambiguous to call.
    static func detectLanguage(of text: String) -> String? {
        guard text.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence > 0.6 else { return nil }
        return language.rawValue
    }
}
