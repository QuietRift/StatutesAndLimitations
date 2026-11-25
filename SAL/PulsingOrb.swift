import SwiftUI

/// SAL's round chat figure. It breathes gently at rest and pulses with each word while speaking.
struct PulsingOrb: View {
    enum Mode { case idle, listening, thinking, speaking }

    let mode: Mode
    /// Changes every time a word is spoken; each change adds a quick beat to the pulse.
    let wordBeat: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastBeat = Date.distantPast

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let scale = scale(at: context.date)
            ZStack {
                // Soft halo that swells more than the core.
                Circle()
                    .fill(RadialGradient(colors: [.cyan.opacity(0.55), .blue.opacity(0)], center: .center, startRadius: 0, endRadius: 110))
                    .scaleEffect(1 + (scale - 1) * 2.2)
                    .opacity(mode == .idle ? 0.35 : 0.7)

                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.72, blue: 1), Color(red: 0, green: 0.37, blue: 1), Color(red: 0, green: 0.20, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        // Glassy highlight so the orb reads as a sphere.
                        Circle()
                            .fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: UnitPoint(x: 0.32, y: 0.28), startRadius: 2, endRadius: 70))
                    }
                    .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                    .shadow(color: .blue.opacity(0.35), radius: 18, y: 8)
                    .padding(28)
                    .scaleEffect(scale)
            }
        }
        .onChange(of: wordBeat) { lastBeat = .now }
        .accessibilityElement()
        .accessibilityLabel("SAL")
        .accessibilityValue(accessibilityValue)
    }

    private func scale(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        switch mode {
        case .idle:
            return 1 + 0.015 * sin(t * 1.6)
        case .thinking:
            return 1 + 0.035 * sin(t * 3)
        case .listening:
            return 1 + 0.03 * (sin(t * 4) + 1) / 2
        case .speaking:
            // Two out-of-phase waves feel more like a voice than a single sine.
            let wave = (sin(t * 9) + sin(t * 14.3)) / 4 + 0.5
            // Each spoken word adds a short beat that decays quickly.
            let beat = 0.07 * exp(-date.timeIntervalSince(lastBeat) * 9)
            return 1 + 0.06 * wave + beat
        }
    }

    private var accessibilityValue: String {
        switch mode {
        case .idle: "Ready"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        }
    }
}

#Preview {
    PulsingOrb(mode: .speaking, wordBeat: 0)
        .frame(width: 200, height: 200)
}
