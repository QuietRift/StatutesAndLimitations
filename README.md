# SAL welcome screen — SwiftUI / iOS 17+

Open **SALWelcome.xcodeproj** in full Xcode. The shared scheme is **SAL**.
There are no third-party packages or runtime AI dependencies.

## Run the starter

1. Open the project, choose an iPhone simulator or connected iPhone, and select your signing team under **Signing & Capabilities**.
2. Change `com.example.sal.welcome` to your team's unique bundle identifier.
3. Run. The welcome screen follows the device's light/dark appearance. The Light, Dark and Large text previews are in `WelcomeView.swift`.

Only the welcome screen and location/state selection are implemented. `SALApp.swift` contains a small completion handoff screen, not your future home page. Replace that handoff with your real next page when it is ready.

## Add it to your existing app instead

Copy these files into your app target:

- `WelcomeView.swift`
- `StateLocationManager.swift`
- `StateSelectionView.swift`
- `USState.swift`
- `Assets.xcassets/WelcomeRoad.imageset`

Keep your existing `@main` App; **do not also add SALApp.swift**. In its root view, route into the welcome screen:

```swift
@AppStorage("sal.onboardingCompleted.v1") private var completed = false
@AppStorage("sal.selectedState") private var stateCode = "MI"

// Inside body:
if completed {
    YourHomeView() // Replace with your actual next screen.
} else {
    WelcomeView { state in
        stateCode = state.rawValue
        completed = true
    }
}
```

Add the following keys to your target's Info settings (the included project already has them):

| Key | Type | Value |
|---|---|---|
| NSLocationWhenInUseUsageDescription | String | SAL uses your approximate location to identify your state so you can choose the traffic-law information you want to view. You can also choose a state manually. |
| NSLocationDefaultAccuracyReduced | Boolean | YES |

Merge the included `PrivacyInfo.xcprivacy` UserDefaults declaration into your existing privacy manifest if you already have one. Its `CA92.1` reason covers settings readable only by this app. Reassess the full app's privacy details when adding features or SDKs.

## What happens after Get Started

1. On the first request, iOS presents its real **Allow Once / Allow While Using App / Don't Allow** location dialog. iOS controls the exact button wording and presentation. The app controls the reason text through the Info key above.
2. After authorization, the app requests one approximate location and uses Apple's reverse geocoder to identify the U.S. state.
3. A sheet lets the user confirm or change the state. Approximate location can be ambiguous near state borders, so confirmation is intentional.
4. Denied/restricted permissions, unavailable location, a failed geocode, offline use or a 20-second lookup timeout lead to manual state selection. Manual selection is also available directly on the welcome screen.
5. Michigan is the only enabled content region. If another state is detected, the app explicitly says it is unsupported and lets the user deliberately choose Michigan instead. It never silently claims Michigan laws apply elsewhere.
6. Only the confirmed state code and onboarding-completed flag are persisted in UserDefaults. The app does not retain coordinates, continuously track the user, request background location, or send coordinates to a developer-owned server. Apple's geocoding service processes the location lookup.

The OS does not repeat its permission dialog after a decision. On later requests the app uses the existing permission or provides the manual route. The welcome screen itself is shown only until a state is confirmed.

## Test on an iPhone before TestFlight

- Fresh install: tap Get Started and check that the permission dialog names SAL and explains state selection.
- Allow Once and Allow While Using App: confirm the detected state, then relaunch and verify the welcome screen is skipped.
- Precise Location off: confirm the approximate result and check state selection still works.
- Don't Allow / global Location Services off: verify manual selection remains available.
- Airplane mode / failed lookup: verify the timeout or error provides manual selection without trapping the user.
- Outside Michigan or outside the U.S.: verify the support message and deliberate Michigan selection.
- Cancel the state sheet, retry, or choose manually while a lookup is pending: stale results must not change the selected state.
- Small iPhone, large Dynamic Type, VoiceOver, light and dark mode: all text must remain reachable and buttons operable.
- For a fresh permission prompt during development, reset Location & Privacy in the device's Settings. Deleting an app alone should not be relied on to reset every permission in every testing setup.

For TestFlight you still need your Apple Developer team, registered bundle identifier, App Store Connect app record and signing. Archive a Release build for an iOS device, validate and upload it from Xcode, then install and test that build through TestFlight. This package has not been signed, archived, uploaded, or approved for distribution.

## Compatibility and verification

The source targets iOS 17+ using Swift 5 language mode. This environment has only macOS command-line developer tools; it has **not** built the iOS target or run the native screen. Source parsing, state-code/name checks, project/plist structure and asset configuration were checked here. Full Xcode compilation and real-device permission testing remain necessary.

`CLGeocoder` is used to obtain the structured `administrativeArea` value on iOS 17+. Apple marks this API deprecated in iOS 26 but it remains available. If you change to an iOS-26-only deployment target, plan a MapKit geocoding migration that preserves structured state identification; do not mistake a country-level `region` field for a U.S. state or infer a state from arbitrary street text.

## Artwork

The shield/scales are native SF Symbols, so no logo bitmap is required. `WelcomeRoad.png` is a generated static photograph inspired by the supplied mockup, not a crop of the mockup and not generated inside the app. Light/dark overlays share the same asset. Replace it with your final licensed photo if preferred. The exact built-in image-generation prompt is in `Artwork.txt`.

## Apple references

- [When-in-use authorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization())
- [Required location purpose string](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationwheninuseusagedescription)
- [Privacy manifest required-reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
- [CLGeocoder deprecation and replacement](https://developer.apple.com/documentation/corelocation/clgeocoder/reversegeocodelocation(_:completionhandler:))
