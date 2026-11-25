import CoreLocation
import Foundation
import MapKit
import Observation

/// Requests one approximate location after the user taps Get Started.
/// Coordinates are never written to storage or sent to an app-owned server.
@MainActor
@Observable
final class StateLocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum Phase: Equatable {
        case idle
        case awaitingPermission
        case locating
        case found(USState)
        case manualSelection(String)
    }

    private(set) var phase: Phase = .idle

    var isBusy: Bool {
        phase == .awaitingPermission || phase == .locating
    }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var attemptID = UUID()
    @ObservationIgnored private var requestedByUser = false
    @ObservationIgnored private var geocoding: Task<Void, Never>?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestState() {
        guard !isBusy else { return }
        attemptID = UUID()
        requestedByUser = true
        switch manager.authorizationStatus {
        case .notDetermined:
            phase = .awaitingPermission
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locateOnce()
        case .denied, .restricted:
            finishManually("Location access is off. You can choose a state yourself.")
        @unknown default:
            finishManually("We couldn’t access your location. Please choose a state.")
        }
    }

    /// Also invalidates late callbacks when the user chooses the manual route.
    func cancel() {
        requestedByUser = false
        attemptID = UUID()
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        geocoding?.cancel()
        geocoding = nil
        phase = .idle
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requestedByUser else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if phase == .awaitingPermission { locateOnce() }
        case .denied, .restricted:
            finishManually("You can continue without sharing your location. Choose a state below.")
        case .notDetermined:
            break
        @unknown default:
            finishManually("Please choose your state manually.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requestedByUser, phase == .locating, geocoding == nil else { return }
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 180 else {
            // requestLocation() delivers a single update, so waiting would only run out the timeout.
            finishManually("We couldn’t find your state right now. You can select it yourself.")
            return
        }
        let currentAttempt = attemptID
        geocoding = Task { [weak self] in
            let state = await Self.resolveState(for: location)
            guard let self, !Task.isCancelled,
                  self.attemptID == currentAttempt, self.requestedByUser else { return }
            if let state {
                self.complete(.found(state))
            } else {
                self.finishManually("We couldn’t identify a U.S. state. Choose one manually, even without internet.")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard requestedByUser else { return }
        finishManually("We couldn’t find your state right now. You can select it yourself.")
    }

    /// Reverse geocodes with MapKit on iOS 26+, where CLGeocoder is deprecated,
    /// and falls back to CLGeocoder on earlier systems.
    private nonisolated static func resolveState(for location: CLLocation) async -> USState? {
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let address = try? await request.mapItems.first?.addressRepresentations,
                  address.region == .unitedStates,
                  let cityWithContext = address.cityWithContext(.full) else { return nil }
            // MapKit has no structured state field, so read it from the "City, ST" context,
            // checking from the end so a city named after a state doesn't match first.
            return cityWithContext
                .split(separator: ",")
                .reversed()
                .lazy
                .compactMap { USState.resolve(codeOrName: String($0)) }
                .first
        } else {
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
                location, preferredLocale: Locale(identifier: "en_US"))
            guard let placemark = placemarks?.first, placemark.isoCountryCode == "US",
                  let stateName = placemark.administrativeArea else { return nil }
            return USState.resolve(codeOrName: stateName)
        }
    }

    private func locateOnce() {
        phase = .locating
        manager.requestLocation()
        let currentAttempt = attemptID
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) }
            catch { return }
            guard let self, self.attemptID == currentAttempt, self.requestedByUser else { return }
            self.finishManually("Finding your state is taking longer than expected. Please choose it below.")
        }
    }

    private func finishManually(_ message: String) {
        complete(.manualSelection(message))
    }

    private func complete(_ result: Phase) {
        requestedByUser = false
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        geocoding?.cancel()
        geocoding = nil
        attemptID = UUID()
        phase = result
    }
}
