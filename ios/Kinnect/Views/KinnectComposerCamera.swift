import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct KinnectComposerCamera: UIViewControllerRepresentable {
    let onResult: (UIImage?, URL?) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        let supported = UIImagePickerController.availableMediaTypes(for: .camera) ?? [UTType.image.identifier]
        picker.mediaTypes = supported.filter { $0 == UTType.image.identifier || $0 == UTType.movie.identifier }
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: KinnectComposerCamera
        init(_ parent: KinnectComposerCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let source = info[.mediaURL] as? URL {
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Kinnect-Capture-\(UUID().uuidString).mov")
                do { try FileManager.default.copyItem(at: source, to: destination); parent.onResult(nil, destination) }
                catch { AppState.shared.showToast(error.localizedDescription); parent.dismiss() }
            } else { parent.onResult(info[.originalImage] as? UIImage, nil) }
        }
    }
}
