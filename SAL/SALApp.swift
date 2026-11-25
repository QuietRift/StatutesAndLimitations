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
                MainTabView(stateCode: $selectedStateCode)
            } else {
                WelcomeView { state in
                    selectedStateCode = state.rawValue
                    onboardingCompleted = true
                }
            }
        }
    }
}
