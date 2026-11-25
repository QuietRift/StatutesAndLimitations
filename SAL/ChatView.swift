import SwiftUI

struct ChatView: View {
    let onChangeState: () -> Void

    @State private var model: ChatModel
    @FocusState private var isComposerFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var orbSize = 170.0

    init(state: USState, onChangeState: @escaping () -> Void) {
        self.onChangeState = onChangeState
        _model = State(initialValue: ChatModel(state: state))
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
            .navigationTitle("SAL · \(model.state.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Change state") {
                        model.tearDown()
                        onChangeState()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.speaksReplies.toggle()
                        if !model.speaksReplies { model.stopSpeaking() }
                    } label: {
                        Image(systemName: model.speaksReplies ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .accessibilityLabel(model.speaksReplies ? "Mute SAL’s voice" : "Unmute SAL’s voice")
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
        .onAppear { model.greetIfNeeded() }
        .onDisappear { model.tearDown() }
    }

    private var statusText: String {
        switch model.orbMode {
        case .speaking: "Speaking…"
        case .listening: model.mic.transcript.isEmpty ? "Listening…" : model.mic.transcript
        case .thinking: "Thinking…"
        case .idle: "Tap the mic to talk, or type below"
        }
    }

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
                Image(systemName: model.mic.isListening ? "stop.fill" : "mic.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(model.mic.isListening ? Color.red : Color(red: 0, green: 0.31, blue: 1)))
            }
            .buttonStyle(.plain)
            .disabled(model.isThinking || model.unavailableMessage != nil)
            .accessibilityLabel(model.mic.isListening ? "Stop listening and send" : "Talk to SAL")

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

private struct MessageBubble: View {
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
    ChatView(state: .michigan, onChangeState: {})
}
