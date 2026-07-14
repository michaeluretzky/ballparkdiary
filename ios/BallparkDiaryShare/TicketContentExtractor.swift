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

    /// A single recognized text fragment with its normalized position on screen
    /// (Vision coordinates: origin bottom-left, values 0–1).
    private struct OCRFragment {
        let text: String
        let box: CGRect
    }

    private static func recognizeText(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let fragments: [OCRFragment] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let frags: [OCRFragment] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
                    return OCRFragment(text: candidate.string, box: obs.boundingBox)
                }
                continuation.resume(returning: frags)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
        guard !fragments.isEmpty else { return nil }
        return assembleText(from: fragments)
    }

    /// Rebuild reading order from OCR fragments and preserve line structure.
    /// Fragments are grouped into visual rows (top→bottom, left→right) so the
    /// downstream parser can scan line-by-line. Additionally, stacked
    /// value/label seat layouts (e.g. SeatGeek's order screen where "BOX537"
    /// sits ABOVE the small "SECTION" caption) are detected geometrically and
    /// emitted as canonical "Section:" / "Row:" / "Seat:" lines at the top of
    /// the text — those win over any looser keyword match downstream.
    private static func assembleText(from fragments: [OCRFragment]) -> String {
        // Group into visual rows. Vision's Y axis points up, so higher midY = higher on screen.
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }
        var rows: [[OCRFragment]] = []
        for frag in sorted {
            if let lastRow = rows.last, let anchor = lastRow.first,
               abs(anchor.box.midY - frag.box.midY) < max(anchor.box.height, frag.box.height) * 0.6 {
                rows[rows.count - 1].append(frag)
            } else {
                rows.append([frag])
            }
        }
        var lines: [String] = rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "   ")
        }

        let seatLines = stackedSeatLines(from: fragments)
        if !seatLines.isEmpty {
            lines.insert(contentsOf: seatLines, at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// Detect column-style seat blocks where the value and its caption are
    /// separate OCR fragments stacked vertically (value above OR below the
    /// label). Returns canonical lines like "Section: BOX537".
    private static func stackedSeatLines(from fragments: [OCRFragment]) -> [String] {
        struct LabelSpec {
            let names: Set<String>
            let canonical: String
        }
        let specs: [LabelSpec] = [
            LabelSpec(names: ["SECTION", "SEC", "SECT"], canonical: "Section"),
            LabelSpec(names: ["ROW"], canonical: "Row"),
            LabelSpec(names: ["SEAT", "SEATS"], canonical: "Seat"),
        ]
        // Any caption word — a fragment matching these can never be a value.
        let labelWords: Set<String> = [
            "SECTION", "SEC", "SECT", "ROW", "SEAT", "SEATS", "QTY", "QUANTITY",
            "GATE", "ENTRY", "AISLE", "LEVEL", "TICKET", "INFO"
        ]

        func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).uppercased()
        }

        /// A short alphanumeric token that plausibly names a section/row/seat
        /// ("BOX537", "160", "7", "AA", "11-12") — never a caption or a word.
        func isPlausibleValue(_ text: String) -> Bool {
            let token = normalized(text)
            guard !token.isEmpty, token.count <= 10, !token.contains(" ") else { return false }
            guard !labelWords.contains(token) else { return false }
            let allowed = token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "/" }
            guard allowed else { return false }
            if token.contains(where: { $0.isNumber }) { return true }
            return token.count <= 3 // letter rows/sections like "A", "AA", "GA"
        }

        var result: [String] = []
        for spec in specs {
            guard let label = fragments.first(where: { spec.names.contains(normalized($0.text)) }) else { continue }

            var best: (fragment: OCRFragment, distance: CGFloat)?
            for candidate in fragments {
                // Must overlap horizontally with the caption's column.
                guard candidate.box.minX < label.box.maxX, candidate.box.maxX > label.box.minX else { continue }
                let distance = abs(candidate.box.midY - label.box.midY)
                // Different visual row, but vertically adjacent.
                guard distance > label.box.height * 0.5, distance < label.box.height * 4 else { continue }
                guard isPlausibleValue(candidate.text) else { continue }
                if best == nil || distance < best!.distance {
                    best = (candidate, distance)
                }
            }
            if let best {
                result.append("\(spec.canonical): \(normalized(best.fragment.text))")
            }
        }
        return result
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
        return ocr.isEmpty ? nil : ocr.joined(separator: "\n")
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
