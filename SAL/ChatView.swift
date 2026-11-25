import SwiftUI

struct ChatView: View {
    /// A question handed over from another tab, such as Laws At A Glance. Cleared once sent.
    @Binding var pendingQuestion: String?
    let onSelectState: (USState) -> Void

    @State private var model: ChatModel
    @State private var showsStatePicker = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isComposerFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var orbSize = 170.0

    init(state: USState, history: ChatHistoryStore, pendingQuestion: Binding<String?>, onSelectState: @escaping (USState) -> Void) {
        _pendingQuestion = pendingQuestion
        self.onSelectState = onSelectState
        _model = State(initialValue: ChatModel(state: state, history: history))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button(action: model.stopSpeaking) {
                    PulsingOrb(mode: model.orbMode, wordBeat: model.speech.wordBeat)
                        .frame(width: orbSize, height: orbSize)
                }
                .buttonStyle(.plain)
                .accessibilityHint(model.speech.isSpeaking ? "Stops SAL from speaking." : "")
                .padding(.top, 8)

                Text(statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.default, value: statusText)
                    .padding(.bottom, 8)

                messageList
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("SAL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: model.startNewChat) {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(!model.hasConversation)
                    .accessibilityLabel("New chat")

                    Button {
                        model.speaksReplies.toggle()
                        if !model.speaksReplies { model.stopSpeaking() }
                    } label: {
                        Image(systemName: model.speaksReplies ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .accessibilityLabel(model.speaksReplies ? "Mute SAL’s voice" : "Unmute SAL’s voice")

                    Button {
                        model.handsFree.toggle()
                    } label: {
                        Image(systemName: model.handsFree ? "ear.fill" : "ear")
                    }
                    .disabled(model.unavailableMessage != nil)
                    .accessibilityLabel("Hey SAL hands-free")
                    .accessibilityValue(model.handsFree ? "On" : "Off")
                    .accessibilityHint("When on, say “Hey SAL” followed by your question.")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsStatePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(model.state.rawValue)
                                .fontWeight(.semibold)
                        }
                    }
                    .accessibilityLabel("State: \(model.state.name)")
                    .accessibilityHint("Changes which state’s laws SAL covers.")
                }
            }
            .sheet(isPresented: $showsStatePicker) {
                StateSelectionView(
                    suggestedState: model.state,
                    message: "Choose which state’s laws you want SAL to cover."
                ) { state in
                    showsStatePicker = false
                    guard state != model.state else { return }
                    model.tearDown()
                    onSelectState(state)
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .onAppear {
            model.greetIfNeeded()
            sendPendingQuestion()
            model.resumeAudio()
        }
        .onChange(of: pendingQuestion) { sendPendingQuestion() }
        // Release the mic when the app leaves the screen (for example when CarPlay takes over).
        .onChange(of: scenePhase) {
            if scenePhase == .active { model.resumeAudio() } else { model.pauseAudio() }
        }
        .onDisappear { model.pauseAudio() }
    }

    private func sendPendingQuestion() {
        guard let question = pendingQuestion else { return }
        pendingQuestion = nil
        model.send(question)
    }

    private var statusText: String {
        switch model.orbMode {
        case .speaking: "Speaking…"
        case .listening: model.mic.transcript.isEmpty ? "Listening…" : model.mic.transcript
        case .thinking: "Thinking…"
        case .idle: model.isWaitingForWakeWord ? "Say “Hey SAL” and ask your question" : "Tap the mic to talk, or type below"
        }
    }

    private var isTakingQuestion: Bool { model.orbMode == .listening }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.text) {
                guard let last = model.messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button(action: model.toggleListening) {
                Image(systemName: isTakingQuestion ? "stop.fill" : "mic.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(isTakingQuestion ? Color.red : Color(red: 0, green: 0.31, blue: 1)))
            }
            .buttonStyle(.plain)
            .disabled(model.isThinking || model.unavailableMessage != nil)
            .accessibilityLabel(isTakingQuestion ? "Stop listening and send" : "Talk to SAL")

            Menu {
                Picker("Listening language", selection: $model.language) {
                    ForEach(SpeechLanguage.available) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
            } label: {
                Text(model.language.shortCode)
                    .font(.footnote.weight(.bold))
                    .frame(minWidth: 34, minHeight: 34)
                    .background(Circle().strokeBorder(.tint, lineWidth: 1.5))
            }
            .accessibilityLabel("Listening language")
            .accessibilityValue(model.language.nativeName)

            TextField("Ask about \(model.state.name) traffic laws", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit(model.sendDraft)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .disabled(model.unavailableMessage != nil)

            Button(action: model.sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
            }
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isThinking)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct MessageBubble: View {
    let message: ChatModel.Message

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Group {
                if message.text.isEmpty {
                    ProgressView()
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isUser ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUser ? Color(red: 0, green: 0.31, blue: 1) : Color(.secondarySystemBackground))
            )
            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You: \(message.text)" : "SAL: \(message.text)")
    }
}

#Preview {
    ChatView(state: .michigan, history: ChatHistoryStore(fileName: "preview-history.json"), pendingQuestion: .constant(nil), onSelectState: { _ in })
}
