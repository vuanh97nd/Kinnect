import AVFoundation
import CoreLocation
import Photos
import UIKit
import UserNotifications

final class MediaPermissionHandler: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = MediaPermissionHandler()

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

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

    func configureAudioSessionForCall(speaker: Bool = true) {
        let session = AVAudioSession.sharedInstance()
        do {
            var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
            if speaker {
                options.insert(.defaultToSpeaker)
            }
            try session.setCategory(.playAndRecord, mode: .videoChat, options: options)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[KinnectAudio] Call AudioSession error: \(error)")
        }
    }

    func configureAudioSessionForMedia() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("[KinnectAudio] Media AudioSession error: \(error)")
        }
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
        await MainActor.run { self.microphoneAuthorized = granted }
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
        await MainActor.run { self.cameraAuthorized = granted }
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
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func requestCurrentLocation() async -> CLLocationCoordinate2D? {
        return await requestCurrentCoordinates()
    }

    func requestCurrentCoordinates() async -> CLLocationCoordinate2D? {
        let status = locationManager.authorizationStatus
        if status == .denied || status == .restricted {
            return nil
        }
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        let updated = locationManager.authorizationStatus
        guard updated == .authorizedWhenInUse || updated == .authorizedAlways else {
            await MainActor.run { self.locationAuthorized = false }
            return nil
        }
        await MainActor.run { self.locationAuthorized = true }
        if let loc = locationManager.location {
            return loc.coordinate
        }
        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        locationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let cont = locationContinuation {
            locationContinuation = nil
            cont.resume(returning: locations.last?.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let cont = locationContinuation {
            locationContinuation = nil
            cont.resume(returning: nil)
        }
    }
}
