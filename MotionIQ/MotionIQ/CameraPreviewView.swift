import AVFoundation
import SwiftUI

/// Wraps AVCaptureVideoPreviewLayer in a SwiftUI view.
/// UIViewRepresentable is required because SwiftUI has no native camera preview —
/// we bridge to UIKit where AVFoundation lives.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    // Custom UIView subclass that uses AVCaptureVideoPreviewLayer as its backing layer.
    // This is the standard Apple-recommended pattern for showing a camera feed.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
