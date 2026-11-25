import CarPlay
import Observation
import UIKit

/// SAL on the car's screen. Designed to be voice-first: a short list to start a conversation,
/// then CarPlay's voice screen while SAL listens, thinks, and speaks. Hands-free “Hey SAL”
/// stays on while the voice screen is showing.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private enum VoiceState: String, CaseIterable {
        case ready, listening, thinking, speaking
    }

    private var interfaceController: CPInterfaceController?
    private var model: ChatModel?
    private var voiceTemplate: CPVoiceControlTemplate?
    private var idleDismissTask: Task<Void, Never>?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let savedCode = UserDefaults.standard.string(forKey: "sal.selectedState") ?? USState.michigan.rawValue
        let state = USState(rawValue: savedCode) ?? .michigan
        model = ChatModel(state: state, history: .shared)
        interfaceController.setRootTemplate(makeRootTemplate(for: state), animated: false, completion: nil)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        model?.handsFree = false
        model?.tearDown()
        model = nil
        voiceTemplate = nil
        self.interfaceController = nil
    }

    // MARK: - Templates

    private func makeRootTemplate(for state: USState) -> CPListTemplate {
        let talk = CPListItem(text: "Talk to SAL", detailText: "Or say “Hey SAL” once it’s open", image: UIImage(systemName: "mic.fill"))
        talk.handler = { [weak self] _, completion in
            self?.presentVoiceScreen(question: nil)
            completion()
        }

        let topics: [(String, String)] = [
            ("Traffic stops", "What are my rights during a traffic stop in \(state.name)?"),
            ("Vehicle searches", "When can police search my car in \(state.name), and can I refuse?"),
            ("After an accident", "What am I legally required to do after a car accident in \(state.name)?"),
            ("Phone use while driving", "What are the rules for using a phone while driving in \(state.name)?")
        ]
        let topicItems = topics.map { title, question in
            let item = CPListItem(text: title, detailText: nil, image: UIImage(systemName: "text.bubble"))
            item.handler = { [weak self] _, completion in
                self?.presentVoiceScreen(question: question)
                completion()
            }
            return item
        }

        return CPListTemplate(title: "SAL · \(state.rawValue)", sections: [
            CPListSection(items: [talk]),
            CPListSection(items: topicItems, header: "Quick questions", sectionIndexTitle: nil)
        ])
    }

    private func makeVoiceTemplate() -> CPVoiceControlTemplate {
        let states = VoiceState.allCases.map { state in
            let voiceState = CPVoiceControlState(identifier: state.rawValue, titleVariants: titles(for: state), image: image(for: state), repeats: true)
            if #available(iOS 26.4, *) {
                voiceState.actionButtons = [
                    CPButton(image: UIImage(systemName: "xmark") ?? UIImage()) { [weak self] _ in self?.dismissVoiceScreen() }
                ]
            }
            return voiceState
        }
        return CPVoiceControlTemplate(voiceControlStates: states)
    }

    private func titles(for state: VoiceState) -> [String] {
        switch state {
        case .ready: ["Say “Hey SAL” and ask", "Say “Hey SAL”"]
        case .listening: ["Listening…"]
        case .thinking: ["Thinking…"]
        case .speaking: ["SAL is speaking"]
        }
    }

    private func image(for state: VoiceState) -> UIImage? {
        switch state {
        case .ready: UIImage(systemName: "ear")
        case .listening: UIImage(systemName: "waveform")
        case .thinking: UIImage(systemName: "ellipsis")
        case .speaking: UIImage(systemName: "speaker.wave.2.fill")
        }
    }

    // MARK: - Conversation

    private func presentVoiceScreen(question: String?) {
        guard let interfaceController, let model else { return }
        if voiceTemplate == nil {
            let template = makeVoiceTemplate()
            voiceTemplate = template
            interfaceController.presentTemplate(template, animated: true, completion: nil)
            observeModel()
        }
        if let question {
            model.handsFree = true
            model.send(question)
        } else {
            // Tapping “Talk to SAL” is already the cue, so skip the wake word this time.
            model.listenHandsFree(skipWakeWord: true)
        }
    }

    /// Before iOS 26.4 the voice screen can't show a close button, so close it after a quiet spell.
    private func scheduleIdleDismissIfNeeded(isIdle: Bool) {
        idleDismissTask?.cancel()
        if #available(iOS 26.4, *) { return }
        guard isIdle else { return }
        idleDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.dismissVoiceScreen()
        }
    }

    private func dismissVoiceScreen() {
        idleDismissTask?.cancel()
        model?.handsFree = false
        model?.pauseAudio()
        voiceTemplate = nil
        interfaceController?.dismissTemplate(animated: true, completion: nil)
    }

    /// Mirrors SAL's state onto the voice screen whenever it changes.
    private func observeModel() {
        guard let model, voiceTemplate != nil else { return }
        let state: VoiceState = switch model.orbMode {
        case .speaking: .speaking
        case .thinking: .thinking
        case .listening: .listening
        case .idle: .ready
        }
        if voiceTemplate?.activeStateIdentifier != state.rawValue {
            voiceTemplate?.activateVoiceControlState(withIdentifier: state.rawValue)
        }
        scheduleIdleDismissIfNeeded(isIdle: state == .ready)
        withObservationTracking {
            _ = model.orbMode
        } onChange: {
            Task { @MainActor [weak self] in self?.observeModel() }
        }
    }
}
