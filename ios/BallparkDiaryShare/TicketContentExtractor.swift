import Foundation
import UniformTypeIdentifiers
import Vision
import PDFKit
import UIKit

/// Pulls plain text out of whatever the user shared — a ticket screenshot
/// (on-device OCR), a PDF receipt (embedded text, OCR fallback), or forwarded
/// email text / a URL. Everything runs locally; nothing is uploaded.
nonisolated enum TicketContentExtractor {

    struct Extracted: Sendable {
        let text: String
        let sourceHint: String
    }

    /// Process every attachment in the extension context into text payloads.
    static func extract(from context: NSExtensionContext?) async -> [Extracted] {
        guard let items = context?.inputItems as? [NSExtensionItem] else { return [] }
        var results: [Extracted] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if let extracted = await extract(from: provider) {
                    results.append(extracted)
                }
            }
        }
        return results
    }

    private static func extract(from provider: NSItemProvider) async -> Extracted? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let image = await loadImage(provider), let text = await recognizeText(in: image) {
                return Extracted(text: text, sourceHint: hint(for: text))
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            if let url = await loadFileURL(provider, type: .pdf), let text = pdfText(at: url) {
                return Extracted(text: text, sourceHint: hint(for: text))
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await loadText(provider) {
                return Extracted(text: text, sourceHint: hint(for: text))
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(provider) {
                return Extracted(text: url.absoluteString, sourceHint: hint(for: url.absoluteString))
            }
        }
        return nil
    }

    // MARK: - Loaders

    private static func loadImage(_ provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                if let image = item as? UIImage {
                    continuation.resume(returning: image)
                } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: UIImage(data: data))
                } else if let data = item as? Data {
                    continuation.resume(returning: UIImage(data: data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadFileURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                // Copy into a temp location we control before the system reclaims it.
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                try? FileManager.default.copyItem(at: url, to: dest)
                continuation.resume(returning: dest)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    // MARK: - OCR

    private static func recognizeText(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.isEmpty ? nil : lines.joined(separator: " "))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - PDF

    private static func pdfText(at url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        if let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        // Scanned PDF with no embedded text: render the first pages and OCR them.
        var ocr: [String] = []
        for index in 0..<min(document.pageCount, 3) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: bounds.size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(bounds)
                ctx.cgContext.translateBy(x: 0, y: bounds.size.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            if let cg = image.cgImage {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                try? handler.perform([request])
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                ocr.append(contentsOf: observations.compactMap { $0.topCandidates(1).first?.string })
            }
        }
        return ocr.isEmpty ? nil : ocr.joined(separator: " ")
    }

    // MARK: - Source hint

    private static func hint(for text: String) -> String {
        let blob = text.lowercased()
        let labels: [(String, String)] = [
            ("ticketmaster", "Ticketmaster"), ("seatgeek", "SeatGeek"),
            ("stubhub", "StubHub"), ("axs", "AXS"), ("vivid", "Vivid Seats"),
            ("gametime", "Gametime"), ("tickpick", "TickPick"),
            ("ballpark", "MLB Ballpark"), ("mlb.com", "MLB.com")
        ]
        for (needle, label) in labels where blob.contains(needle) { return label }
        return "Shared ticket"
    }
}
