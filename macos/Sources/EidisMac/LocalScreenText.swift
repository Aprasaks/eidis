import CoreGraphics
import Foundation
import Vision

/// Reads text from a screenshot entirely on this Mac.
/// No persistent image, network, external model, or automatic screen capture.
enum LocalScreenText {
    struct Result {
        let text: String
        let lineCount: Int
    }

    static func recognize(in image: CGImage) throws -> Result {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Bound UI rendering; don't persist the OCR data to disk or logs.
        return Result(text: String(lines.joined(separator: "\n").prefix(12_000)),
                      lineCount: lines.count)
    }
}
