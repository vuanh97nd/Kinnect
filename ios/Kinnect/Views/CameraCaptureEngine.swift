import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Integrated AVFoundation Capture Controller & Preview
enum StudioLens: String, CaseIterable, Identifiable {
    case ultraWide
    case wide
    case tele

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ultraWide: return "0.5"
        case .wide: return "1x"
        case .tele: return "2x"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .tele: return .builtInTelephotoCamera
        }
    }
}

final class CameraCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    @Published var isRecordingVideo: Bool = false
    @Published var availableLenses: [StudioLens] = []
    @Published var activeLens: StudioLens = .wide
    @Published var exposureBias: Float = 0
    @Published var isPermissionDenied: Bool = false
    @Published var isPermissionAuthorized: Bool = false

    var onCapturedImage: ((UIImage) -> Void)?
    var onCapturedVideoData: ((Data, URL) -> Void)?
    private var isConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .back

    func configureIfAuthorized(initialPosition: AVCaptureDevice.Position = .back) {
        #if !targetEnvironment(simulator)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            DispatchQueue.main.async {
                self.isPermissionDenied = true
                self.isPermissionAuthorized = false
            }
            return
        }
        guard status == .authorized else { return }
        DispatchQueue.main.async {
            self.isPermissionDenied = false
            self.isPermissionAuthorized = true
        }
        if isConfigured {
            start()
            return
        }
        isConfigured = true
        currentPosition = initialPosition
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: initialPosition),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice), session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        applyStabilization()
        session.commitConfiguration()
        refreshLenses(position: initialPosition)
        NotificationCenter.default.addObserver(self, selector: #selector(stopForInterruption), name: UIApplication.willResignActiveNotification, object: nil)
        start()
        #endif
    }

    func start() {
        #if !targetEnvironment(simulator)
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
        #endif
    }

    func stop() {
        #if !targetEnvironment(simulator)
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        if session.isRunning {
            session.stopRunning()
        }
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        #endif
    }

    deinit {
        stop()
    }

    @objc private func stopForInterruption() {
        #if !targetEnvironment(simulator)
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        #endif
    }

    func refreshLenses(position: AVCaptureDevice.Position) {
        currentPosition = position
        let found = StudioLens.allCases.filter {
            AVCaptureDevice.default($0.deviceType, for: .video, position: position) != nil
        }
        availableLenses = found.isEmpty ? [.wide] : found
        if !availableLenses.contains(activeLens) {
            activeLens = availableLenses.contains(.wide) ? .wide : availableLenses[0]
        }
    }

    func selectLens(_ lens: StudioLens, position: AVCaptureDevice.Position) {
        #if !targetEnvironment(simulator)
        guard let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        for existing in session.inputs {
            if let devInput = existing as? AVCaptureDeviceInput, devInput.device.hasMediaType(.video) {
                session.removeInput(devInput)
            }
        }
        if session.canAddInput(input) {
            session.addInput(input)
            activeLens = lens
        }
        applyStabilization()
        session.commitConfiguration()
        #endif
    }

    func focus(at devicePoint: CGPoint) {
        #if !targetEnvironment(simulator)
        guard let device = currentVideoDevice() else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            return
        }
        #endif
    }

    func setExposureBias(_ bias: Float) {
        #if !targetEnvironment(simulator)
        guard let device = currentVideoDevice() else { return }
        let clamped = min(device.maxExposureTargetBias, max(device.minExposureTargetBias, bias))
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
            exposureBias = clamped
        } catch {
            return
        }
        #endif
    }

    private func currentVideoDevice() -> AVCaptureDevice? {
        session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(.video) }?.device
    }

    func applyStabilization() {
        guard let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported else { return }
        connection.preferredVideoStabilizationMode = .cinematic
    }

    func capturePhoto(flash: Bool) {
        #if !targetEnvironment(simulator)
        if session.isRunning && !photoOutput.connections.isEmpty {
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            if photoOutput.supportedFlashModes.contains(flash ? .on : .off) {
                settings.flashMode = flash ? .on : .off
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
            return
        }
        #endif
        let fallback = UIReviewFixture.samplePreviewImage()
        DispatchQueue.main.async { [weak self] in
            self?.onCapturedImage?(fallback)
        }
    }

    func toggleVideoRecording() {
        #if !targetEnvironment(simulator)
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            DispatchQueue.main.async { self.isRecordingVideo = false }
            return
        }
        if session.isRunning && !movieOutput.connections.isEmpty {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("kinnect_capture_\(UUID().uuidString).mp4")
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecordingVideo = true }
            return
        }
        #endif
        if isRecordingVideo {
            isRecordingVideo = false
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("kinnect_sim_\(UUID().uuidString).mp4")
            let dummyMP4 = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32, 0x00, 0x00, 0x00, 0x00, 0x6D, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6F, 0x6D])
            try? dummyMP4.write(to: tempURL)
            onCapturedVideoData?(dummyMP4, tempURL)
        } else {
            isRecordingVideo = true
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCapturedImage?(img)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecordingVideo = false
            guard error == nil, let data = try? Data(contentsOf: outputFileURL) else { return }
            self?.onCapturedVideoData?(data, outputFileURL)
        }
    }
}

struct LiveCameraPreviewView: UIViewControllerRepresentable {
    @ObservedObject var controller: CameraCaptureController
    @Binding var isFlashOn: Bool
    @Binding var isUsingFrontCamera: Bool
    var showGrid: Bool = true

    func makeUIViewController(context: Context) -> CameraPreviewViewController {
        let vc = CameraPreviewViewController()
        vc.controller = controller
        vc.showGrid = showGrid
        vc.initialPosition = isUsingFrontCamera ? .front : .back
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraPreviewViewController, context: Context) {
        uiViewController.showGrid = showGrid
        uiViewController.setCamera(front: isUsingFrontCamera)
        uiViewController.setFlash(on: isFlashOn)
    }
}

final class CameraPreviewViewController: UIViewController {
    var controller: CameraCaptureController?
    var showGrid: Bool = true {
        didSet {
            gridLayer.isHidden = !showGrid
        }
    }
    var initialPosition: AVCaptureDevice.Position = .back
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let backdropLayer = CAGradientLayer()
    private let gridLayer = CAShapeLayer()
    private var simulatedImageView: UIImageView?
    private var lastConfiguredPosition: AVCaptureDevice.Position? = nil
    private var lastFlashState: Bool? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KinnectTheme.studioPreviewUIColor
        setupViewfinderBackdrop()
        setupSessionIfAuthorized()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupSessionIfAuthorized()
        controller?.configureIfAuthorized(initialPosition: initialPosition)
        controller?.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdropLayer.frame = view.bounds
        simulatedImageView?.frame = view.bounds
        updateGridPath()
        if let previewLayer {
            previewLayer.frame = view.bounds
            if let conn = previewLayer.connection, conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }
    }

    private func setupViewfinderBackdrop() {
        backdropLayer.colors = KinnectTheme.studioViewfinderCGColors
        backdropLayer.locations = [0.0, 0.55, 1.0]
        view.layer.addSublayer(backdropLayer)

        #if targetEnvironment(simulator)
        let sim = UIImageView(image: UIReviewFixture.samplePreviewImage())
        sim.contentMode = .scaleAspectFill
        sim.clipsToBounds = true
        sim.frame = view.bounds
        view.addSubview(sim)
        simulatedImageView = sim
        #endif

        // Grid & Crosshair overlay matching Google Camera in Android StudioActivity
        gridLayer.strokeColor = KinnectTheme.studioGridGuideCGColor
        gridLayer.lineWidth = 1.0
        gridLayer.fillColor = UIColor.clear.cgColor
        gridLayer.isHidden = !showGrid
        view.layer.addSublayer(gridLayer)
    }

    private func updateGridPath() {
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }
        let path = UIBezierPath()

        // 3x3 Grid
        path.move(to: CGPoint(x: w / 3, y: 0))
        path.addLine(to: CGPoint(x: w / 3, y: h))
        path.move(to: CGPoint(x: 2 * w / 3, y: 0))
        path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
        path.move(to: CGPoint(x: 0, y: h / 3))
        path.addLine(to: CGPoint(x: w, y: h / 3))
        path.move(to: CGPoint(x: 0, y: 2 * h / 3))
        path.addLine(to: CGPoint(x: w, y: 2 * h / 3))

        // Amber balance center crosshair (+) matching Android StudioActivity lines 1795-1803
        let cx = w / 2
        let cy = h / 2
        let cross: CGFloat = 12
        path.move(to: CGPoint(x: cx - cross, y: cy))
        path.addLine(to: CGPoint(x: cx + cross, y: cy))
        path.move(to: CGPoint(x: cx, y: cy - cross))
        path.addLine(to: CGPoint(x: cx, y: cy + cross))

        // Center balance ring
        path.addArc(withCenter: CGPoint(x: cx, y: cy), radius: 18, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        gridLayer.path = path.cgPath
    }

    private func setupSessionIfAuthorized() {
        #if !targetEnvironment(simulator)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            if previewLayer == nil {
                attachHardwarePreview()
            }
        } else if status == .notDetermined && !UIReviewFixture.isEnabled {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.attachHardwarePreview()
                }
            }
        }
        #endif
    }

    private func attachHardwarePreview() {
        #if !targetEnvironment(simulator)
        guard let ctrl = controller else { return }
        ctrl.configureIfAuthorized(initialPosition: initialPosition)
        lastConfiguredPosition = initialPosition
        if previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer(session: ctrl.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            if let conn = layer.connection, conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
            backdropLayer.isHidden = true
            simulatedImageView?.removeFromSuperview()
            simulatedImageView = nil
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
            view.addGestureRecognizer(tap)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleExposurePan(_:)))
            view.addGestureRecognizer(pan)
        } else {
            previewLayer?.frame = view.bounds
            backdropLayer.isHidden = true
        }
        ctrl.start()
        #endif
    }

    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        guard let previewLayer else { return }
        let point = previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: view))
        controller?.focus(at: point)
    }

    @objc private func handleExposurePan(_ gesture: UIPanGestureRecognizer) {
        let delta = Float(-gesture.translation(in: view).y / 120)
        controller?.setExposureBias((controller?.exposureBias ?? 0) + delta)
        gesture.setTranslation(.zero, in: view)
    }

    func setCamera(front: Bool) {
        #if !targetEnvironment(simulator)
        let pos: AVCaptureDevice.Position = front ? .front : .back
        guard pos != lastConfiguredPosition else { return }
        lastConfiguredPosition = pos
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let session = controller?.session else { return }
        session.beginConfiguration()
        for input in session.inputs {
            if let devInput = input as? AVCaptureDeviceInput, devInput.device.hasMediaType(.video) {
                session.removeInput(devInput)
            }
        }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        controller?.applyStabilization()
        session.commitConfiguration()
        controller?.refreshLenses(position: pos)
        controller?.activeLens = .wide
        #endif
    }

    func setFlash(on: Bool) {
        #if !targetEnvironment(simulator)
        guard on != lastFlashState else { return }
        lastFlashState = on
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        #if !targetEnvironment(simulator)
        if let session = controller?.session, session.isRunning {
            session.stopRunning()
        }
        #endif
    }
}

final class PhotoSaveCoordinator: NSObject {
    static let shared = PhotoSaveCoordinator()
    var onComplete: ((Bool, Error?) -> Void)?

    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async { [weak self] in
            if let error {
                self?.onComplete?(false, error)
            } else {
                self?.onComplete?(true, nil)
            }
        }
    }

    @objc func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async { [weak self] in
            if let error {
                self?.onComplete?(false, error)
            } else {
                self?.onComplete?(true, nil)
            }
        }
    }
}

// MARK: - Dedicated Native Video Player with AVPlayer & Integrated Controls
struct StudioVideoPlayerView: View {
    let videoURL: URL
    var videoProject: StudioVideoProject? = nil
    var revisionId: String = ""
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isMuted: Bool = false
    @State private var timeObserverToken: Any?
    @State private var endObserverToken: (any NSObjectProtocol)? = nil
    @State private var playbackObserver: NSKeyValueObservation?
    @State private var metadataTask: Task<Void, Never>? = nil
    @State private var videoResolution: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // Native AVPlayer Rendering Layer
            if let p = player {
                VideoPlayer(player: p)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(KinnectTheme.border, lineWidth: 1)
                    )
            } else {
                Color.black
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(ProgressView().tint(.white))
            }

            // Integrated Interactive Controls
            VStack(spacing: 8) {
                // Top Metadata Bar (Derived from Asset Tracks)
                HStack {
                    if !videoResolution.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "film.fill")
                                .font(.system(size: 10))
                            Text(videoResolution)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .foregroundColor(.white)
                    }

                    Spacer()

                    Button {
                        isMuted.toggle()
                        player?.isMuted = isMuted
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(KinnectTheme.scaled(12))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.65)))
                    }
                    .accessibilityLabel(isMuted ? "Bật âm thanh" : "Tắt âm thanh")
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer()

                // Center Play/Pause Toggle
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50, weight: .light))
                        .foregroundColor(.white.opacity(isPlaying ? 0.85 : 0.95))
                        .shadow(color: .black.opacity(0.6), radius: 8)
                }
                .accessibilityLabel(isPlaying ? "Tạm dừng video" : "Phát video")

                Spacer()

                // Bottom Timeline Scrubber & Counter
                VStack(spacing: 6) {
                    // Scrubber Bar
                    GeometryReader { geo in
                        let progress = duration > 0 ? (currentTime / duration) : 0
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 5)

                            Capsule()
                                .fill(KinnectTheme.primaryGradient)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(progress))), height: 5)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let fraction = max(0, min(1, val.location.x / geo.size.width))
                                    let targetTime = fraction * duration
                                    seek(to: targetTime)
                                }
                        )
                    }
                    .frame(height: 5)

                    HStack {
                        Text(formatDuration(currentTime))
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundColor(.white)

                        Spacer()

                        Text(formatDuration(duration))
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 320)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: videoURL) { _ in
            teardownPlayer()
            setupPlayer()
        }
        .onChange(of: revisionId) { _ in
            guard let curItem = player?.currentItem else { return }
            if let vp = videoProject, vp.hasEdits {
                curItem.videoComposition = vp.makeVideoComposition(for: curItem.asset)
            } else {
                curItem.videoComposition = nil
            }
        }
    }

    private func setupPlayer() {
        let asset = AVURLAsset(url: videoURL)
        let item = AVPlayerItem(asset: asset)
        if let vp = videoProject, vp.hasEdits {
            item.videoComposition = vp.makeVideoComposition(for: asset)
        }
        let p = AVPlayer(playerItem: item)
        p.isMuted = isMuted
        self.player = p

        // Load asset tracks metadata asynchronously
        metadataTask = Task {
            let asset = AVURLAsset(url: videoURL)
            if let d = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(d)
                if sec.isFinite && sec > 0 && !Task.isCancelled {
                    await MainActor.run { self.duration = sec }
                }
            }
            if let tracks = try? await asset.loadTracks(withMediaType: .video), let firstTrack = tracks.first {
                var labels: [String] = []
                if let size = try? await firstTrack.load(.naturalSize) {
                    let w = Int(size.width)
                    let h = Int(size.height)
                    if w > 0 && h > 0 {
                        labels.append("\(min(w, h))p")
                    }
                }
                if let fps = try? await firstTrack.load(.nominalFrameRate), fps > 0 {
                    labels.append(String(format: "%.0ffps", fps))
                }
                if !labels.isEmpty && !Task.isCancelled {
                    let fullLabel = labels.joined(separator: " • ")
                    await MainActor.run { self.videoResolution = fullLabel }
                }
            }
        }

        // Add periodic time observer (10Hz)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard p != nil else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite {
                self.currentTime = sec
            }
        }

        // Observe end of playback using retained token to prevent memory leak
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
            self.isPlaying = true
        }

        playbackObserver?.invalidate()
        playbackObserver = p.observe(\.timeControlStatus, options: [.initial, .new]) { observed, _ in
            let playing = observed.timeControlStatus == .playing
            DispatchQueue.main.async { self.isPlaying = playing }
        }
        p.play()
    }

    private func teardownPlayer() {
        metadataTask?.cancel()
        metadataTask = nil
        playbackObserver?.invalidate()
        playbackObserver = nil

        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    private func togglePlayPause() {
        guard let p = player else { return }
        if p.timeControlStatus == .paused {
            p.play()
        } else {
            p.pause()
        }
    }

    private func seek(to seconds: Double) {
        guard let p = player, seconds.isFinite else { return }
        let targetCM = CMTime(seconds: seconds, preferredTimescale: 600)
        p.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    private func formatDuration(_ sec: Double) -> String {
        guard sec.isFinite && sec >= 0 else { return "00:00" }
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
