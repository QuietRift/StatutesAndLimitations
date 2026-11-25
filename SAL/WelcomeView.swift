import SwiftUI

struct WelcomeView: View {
    /// Connect this to the next onboarding page or your existing home screen.
    let onContinue: (USState) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 34.0
    @ScaledMetric(relativeTo: .largeTitle) private var brandSize = 57.0
    @ScaledMetric(relativeTo: .largeTitle) private var shieldWidth = 92.0
    @ScaledMetric(relativeTo: .largeTitle) private var shieldHeight = 105.0
    @ScaledMetric(relativeTo: .largeTitle) private var emblemSize = 45.0
    @ScaledMetric(relativeTo: .largeTitle) private var emblemOffset = -4.0
    @State private var location = StateLocationManager()
    @State private var bottomBarHeight = 135.0
    @State private var showsStatePicker = false
    @State private var suggestedState: USState?
    @State private var stateMessage = "Choose which state’s laws you want to explore."

    private var isDark: Bool { colorScheme == .dark }
    private var foreground: Color { isDark ? .white : Color(red: 0.015, green: 0.065, blue: 0.24) }
    private var secondary: Color {
        isDark ? Color(red: 0.86, green: 0.91, blue: 1) : Color(red: 0.20, green: 0.30, blue: 0.47)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WelcomeBackground(isDark: isDark)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        brand
                            .padding(.top, geometry.size.height < 650 ? 18 : 38)

                        Text("Know Your Rights\non the Road")
                            .font(.system(size: headlineSize, weight: .bold))
                            .tracking(-0.6)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 28)

                        Text("A simple guide to traffic stops,\ntraffic laws, and your legal rights.")
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)

                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 40 : 130)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geometry.size.height - bottomBarHeight), alignment: .top)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 12) {
                    Button(action: location.requestState) {
                        HStack(spacing: 12) {
                            if location.isBusy {
                                ProgressView().tint(.white)
                                Text(location.phase == .awaitingPermission ? "Waiting for permission…" : "Finding your state…")
                            } else {
                                Text("Get Started")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 12)
                        .background {
                            Capsule()
                                .fill(LinearGradient(colors: [Color(red: 0, green: 0.37, blue: 1), Color(red: 0, green: 0.25, blue: 1)], startPoint: .top, endPoint: .bottom))
                                .overlay { Capsule().strokeBorder(isDark ? Color.cyan.opacity(0.65) : .clear, lineWidth: 1) }
                        }
                        .shadow(color: .blue.opacity(isDark ? 0.20 : 0.12), radius: 12, y: 5)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(location.isBusy)
                    .accessibilityHint("Requests permission to find your state using approximate location.")

                    Button("Choose state manually") {
                        location.cancel()
                        suggestedState = nil
                        stateMessage = "You don’t have to share your location. Choose a state below."
                        showsStatePicker = true
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(foreground)
                    .frame(minHeight: 32)
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                // The buttons grow with Dynamic Type, so measure them instead of assuming a height.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomBarHeight = $0 }
            }
        }
        .onChange(of: location.phase) { _, phase in
            switch phase {
            case .found(let state):
                suggestedState = state
                stateMessage = "Your location suggests \(state.name). Confirm the state whose laws you want to view."
                showsStatePicker = true
            case .manualSelection(let message):
                suggestedState = nil
                stateMessage = message
                showsStatePicker = true
            default:
                break
            }
        }
        // Resetting to .idle on dismiss lets a repeated result (such as denied access) reopen the sheet.
        .sheet(isPresented: $showsStatePicker, onDismiss: { location.cancel() }) {
            StateSelectionView(suggestedState: suggestedState, message: stateMessage) { state in
                showsStatePicker = false
                location.cancel()
                onContinue(state)
            }
        }
        .onDisappear { location.cancel() }
    }

    private var brand: some View {
        VStack(spacing: 3) {
            ZStack {
                Image(systemName: "shield")
                    .resizable()
                    .scaledToFit()
                    .frame(width: shieldWidth, height: shieldHeight)
                Image(systemName: "scalemass")
                    .font(.system(size: emblemSize, weight: .regular))
                    .offset(y: emblemOffset)
            }
            .foregroundStyle(foreground)
            .accessibilityHidden(true)

            Text("SAL")
                .font(.system(size: brandSize, weight: .heavy))
                .tracking(-1)
                .foregroundStyle(foreground)
            Text("Statute & Limitations")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeBackground: View {
    let isDark: Bool
    private var base: Color {
        isDark ? Color(red: 0, green: 0.055, blue: 0.13) : Color(red: 0.94, green: 0.97, blue: 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                base
                Image("WelcomeRoad")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.48)
                    .clipped()
                    .overlay(isDark ? Color(red: 0, green: 0.035, blue: 0.10).opacity(0.40) : Color.white.opacity(0.10))
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.26),
                            .init(color: .black, location: 0.65),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                LinearGradient(colors: [.clear, base.opacity(0.8), base], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.16)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Light") {
    WelcomeView(onContinue: { _ in }).preferredColorScheme(.light)
}

#Preview("Dark") {
    WelcomeView(onContinue: { _ in }).preferredColorScheme(.dark)
}

#Preview("Large text") {
    WelcomeView(onContinue: { _ in })
        .environment(\.dynamicTypeSize, .accessibility3)
}
