import AVFoundation
import CoreLocation
import Photos
import UIKit
import UserNotifications

@MainActor
final class MediaPermissionHandler: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = MediaPermissionHandler()

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    @Published var cameraAuthorized: Bool = false
    @Published var microphoneAuthorized: Bool = false
    @Published var locationAuthorized: Bool = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        refreshStatuses()
    }

    func refreshStatuses() {
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let locStatus = locationManager.authorizationStatus
        locationAuthorized = (locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways)
    }

    private nonisolated static func hasExternalAudioOutputRoute(_ session: AVAudioSession) -> Bool {
        session.currentRoute.outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .carAudio, .airPlay, .usbAudio:
                return true
            default:
                return false
            }
        }
    }

    nonisolated static func configureAudioSessionForCall(
        speaker: Bool = true,
        activate: Bool = false,
        explicitRouteToggle: Bool = false
    ) {
        let session = AVAudioSession.sharedInstance()
        do {
            var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
            if speaker {
                options.insert(.defaultToSpeaker)
            }
            try session.setCategory(
                .playAndRecord,
                mode: speaker ? .videoChat : .voiceChat,
                options: options
            )
            if activate {
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            }
            if explicitRouteToggle {
                try? session.overrideOutputAudioPort(speaker ? .speaker : .none)
            } else if !hasExternalAudioOutputRoute(session) {
                try? session.overrideOutputAudioPort(speaker ? .speaker : .none)
            }
        } catch {
            print("[KinnectAudio] Call AudioSession error: \(error)")
        }
    }

    nonisolated func configureAudioSessionForCall(
        speaker: Bool = true,
        activate: Bool = false,
        explicitRouteToggle: Bool = false
    ) {
        Self.configureAudioSessionForCall(
            speaker: speaker,
            activate: activate,
            explicitRouteToggle: explicitRouteToggle
        )
    }

    nonisolated static func configureAudioSessionForLiveViewer() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            if !hasExternalAudioOutputRoute(session) {
                try? session.overrideOutputAudioPort(.speaker)
            }
        } catch {
            do {
                try session.setCategory(
                    .playback,
                    mode: .moviePlayback,
                    options: []
                )
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                print("[KinnectAudio] Live viewer AudioSession error: \(error)")
            }
        }
    }

    nonisolated func configureAudioSessionForLiveViewer() {
        Self.configureAudioSessionForLiveViewer()
    }

    nonisolated static func configureAudioSessionForMedia() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[KinnectAudio] Media AudioSession error: \(error)")
        }
    }

    nonisolated func configureAudioSessionForMedia() {
        Self.configureAudioSessionForMedia()
    }

    func requestMicrophoneAccess() async -> Bool {
        if UIReviewFixture.isEnabled && !UIReviewFixture.allowsCapturePrompt {
            return false
        }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let granted: Bool
        switch status {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            granted = false
        }
        self.microphoneAuthorized = granted
        return granted
    }

    func requestCameraAccess() async -> Bool {
        if UIReviewFixture.isEnabled && !UIReviewFixture.allowsCapturePrompt {
            return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        switch status {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            granted = false
        }
        self.cameraAuthorized = granted
        return granted
    }

    /// Requests Microphone and (optionally) Camera permissions and returns the true authorization result.
    func ensureCallPermissions(requireVideo: Bool) async -> Bool {
        let micOk = await requestMicrophoneAccess()
        guard micOk else { return false }
        guard requireVideo else { return true }
        return await requestCameraAccess()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                Task { @MainActor in
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func requestCurrentLocation() async -> CLLocationCoordinate2D? {
        return await requestCurrentCoordinates()
    }

    func requestCurrentCoordinates() async -> CLLocationCoordinate2D? {
        var status = locationManager.authorizationStatus
        if status == .denied || status == .restricted {
            self.locationAuthorized = false
            return nil
        }
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                if let existing = self.authContinuation {
                    self.authContinuation = nil
                    existing.resume(returning: self.locationManager.authorizationStatus)
                }
                self.authContinuation = continuation
                self.locationManager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            self.locationAuthorized = false
            return nil
        }
        self.locationAuthorized = true
        if let loc = locationManager.location {
            return loc.coordinate
        }
        return await withCheckedContinuation { continuation in
            if let existing = self.locationContinuation {
                self.locationContinuation = nil
                existing.resume(returning: nil)
            }
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.locationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
            if status != .notDetermined, let cont = self.authContinuation {
                self.authContinuation = nil
                cont.resume(returning: status)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cont = self.locationContinuation {
                self.locationContinuation = nil
                cont.resume(returning: coord)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cont = self.locationContinuation {
                self.locationContinuation = nil
                cont.resume(returning: nil)
            }
        }
    }
}
