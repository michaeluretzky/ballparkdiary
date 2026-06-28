import SwiftUI
import PhotosUI
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// The result of picking a photo, carrying its embedded EXIF metadata.
/// All fields are value types so the payload is `Sendable` and can cross the
/// PhotoKit background callback boundary back to the main actor safely.
struct PhotoPickResult: Sendable {
    let imageData: Data?
    let latitude: Double?
    let longitude: Double?
    let captureDate: Date?
    /// GPS image direction (compass degrees the camera faced), when present.
    let heading: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A photo picker that recovers GPS + capture-date metadata from the chosen
/// image. Standard `PhotosPicker` data strips location for privacy, so this
/// resolves the underlying `PHAsset` (with the user's permission) to read the
/// real coordinates, then reads the EXIF for compass heading.
struct PhotoMetadataPicker: UIViewControllerRepresentable {
    let onPick: (PhotoPickResult?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (PhotoPickResult?) -> Void

        init(onPick: @escaping (PhotoPickResult?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else {
                deliver(nil)
                return
            }

            let provider = result.itemProvider
            let assetId = result.assetIdentifier

            // Load the raw image bytes for a preview (works without permission).
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] previewData, _ in
                guard let self else { return }

                // Prefer the PHAsset path for trustworthy GPS + capture date.
                if let assetId {
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                        guard
                            status == .authorized || status == .limited,
                            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
                        else {
                            self.deliverParsed(previewData)
                            return
                        }
                        let assetCoord = asset.location?.coordinate
                        let creation = asset.creationDate
                        // Read the full-size image's EXIF for the compass heading
                        // (and as a fallback for coordinates / date).
                        let editOptions = PHContentEditingInputRequestOptions()
                        editOptions.isNetworkAccessAllowed = true
                        asset.requestContentEditingInput(with: editOptions) { input, _ in
                            let parsed = Self.parseMetadata(fromURL: input?.fullSizeImageURL)
                                ?? Self.parseMetadata(from: previewData)
                                ?? Self.empty
                            let lat = assetCoord?.latitude ?? parsed.lat
                            let lon = assetCoord?.longitude ?? parsed.lon
                            let date = creation ?? parsed.date
                            self.deliver(PhotoPickResult(
                                imageData: previewData,
                                latitude: lat, longitude: lon,
                                captureDate: date, heading: parsed.heading
                            ))
                        }
                    }
                } else {
                    self.deliverParsed(previewData)
                }
            }
        }

        /// Build a result purely from parsed EXIF (fallback when no asset access).
        nonisolated private func deliverParsed(_ data: Data?) {
            let parsed = Self.parseMetadata(from: data) ?? Self.empty
            deliver(PhotoPickResult(
                imageData: data,
                latitude: parsed.lat, longitude: parsed.lon,
                captureDate: parsed.date, heading: parsed.heading
            ))
        }

        nonisolated private func deliver(_ result: PhotoPickResult?) {
            Task { @MainActor in self.onPick(result) }
        }

        // MARK: - EXIF parsing

        private typealias Metadata = (lat: Double?, lon: Double?, date: Date?, heading: Double?)
        nonisolated private static let empty: Metadata = (nil, nil, nil, nil)

        nonisolated private static func parseMetadata(fromURL url: URL?) -> Metadata? {
            guard
                let url,
                let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { return nil }
            return parseProperties(props)
        }

        nonisolated private static func parseMetadata(from data: Data?) -> Metadata? {
            guard
                let data,
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { return nil }
            return parseProperties(props)
        }

        nonisolated private static func parseProperties(_ props: [CFString: Any]) -> Metadata {

            var lat: Double?
            var lon: Double?
            var date: Date?
            var heading: Double?

            if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
                if let value = gps[kCGImagePropertyGPSLatitude] as? Double,
                   let ref = gps[kCGImagePropertyGPSLatitudeRef] as? String {
                    lat = ref.uppercased() == "S" ? -value : value
                }
                if let value = gps[kCGImagePropertyGPSLongitude] as? Double,
                   let ref = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                    lon = ref.uppercased() == "W" ? -value : value
                }
                heading = gps[kCGImagePropertyGPSImgDirection] as? Double
            }

            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let stamp = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
                ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                date = formatter.date(from: stamp)
            }

            return (lat, lon, date, heading)
        }
    }
}

