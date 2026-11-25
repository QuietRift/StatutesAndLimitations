import SwiftUI

/// Example host app. If adding to an existing project, keep that project's @main
/// App and integrate WelcomeView using the example in README instead.
@main
struct SALApp: App {
    @AppStorage("sal.onboardingCompleted.v1") private var onboardingCompleted = false
    @AppStorage("sal.selectedState") private var selectedStateCode = "MI"

    var body: some Scene {
        WindowGroup {
            if onboardingCompleted {
                let state = USState(rawValue: selectedStateCode) ?? .michigan
                // Replace this handoff view with your real home page when ready.
                ContentUnavailableView {
                    Label("\(state.name) selected", systemImage: "checkmark.seal")
                } description: {
                    Text("Your state is set. SAL’s traffic-law information covers \(state.name).")
                } actions: {
                    Button("Change state") { onboardingCompleted = false }
                }
            } else {
                WelcomeView { state in
                    selectedStateCode = state.rawValue
                    onboardingCompleted = true
                }
            }
        }
    }
}
