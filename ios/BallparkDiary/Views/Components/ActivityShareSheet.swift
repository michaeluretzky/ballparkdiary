import SwiftUI
import UIKit

/// UIActivityViewController wrapper for sharing rendered images and files.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Identifiable UIImage wrapper so share sheets can use `.sheet(item:)`,
/// which guarantees the image exists when the sheet is presented.
struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
