import AVFoundation
import CoreLocation
import UIKit
import UserNotifications

final class MediaPermissionHandler: NSObject, CLLocationManagerDelegate {
    static let shared = MediaPermissionHandler()

    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func configureAudioSessionForCall() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[KinnectAudio] AudioSession configuration error: \(error)")
        }
    }

    func configureAudioSessionForMedia() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            print("[KinnectAudio] Playback session error: \(error)")
        }
    }

    func requestCameraAndMicrophoneIfNeeded(completion: ((Bool) -> Void)? = nil) {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        let checkAudio: (Bool) -> Void = { videoGranted in
            switch audioStatus {
            case .authorized:
                DispatchQueue.main.async { completion?(videoGranted) }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                    DispatchQueue.main.async { completion?(videoGranted && audioGranted) }
                }
            default:
                DispatchQueue.main.async { completion?(false) }
            }
        }

        switch videoStatus {
        case .authorized:
            checkAudio(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                checkAudio(granted)
            }
        default:
            checkAudio(false)
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[KinnectNotify] Notification auth error: \(error)")
            } else if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func requestLocationIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
}
