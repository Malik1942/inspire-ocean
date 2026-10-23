import Foundation
import Vision

/// Reads a thought's pictures into words on the device, so what a picture
/// holds can enter the understanding layer: the text in it (Vision text
/// recognition, Chinese and English) and what it shows (Vision scene
/// classification). No model, no network, every device.
///
/// This is the picture path for iOS 26, where the on-device language model
/// takes no images. When the model can look at a picture itself (iOS 27),
/// `read` gains that path behind the same `Reading`, `PictureReading.version`
/// bumps, and the pictures are read again on the next Library open; the
/// labels give way to a line the model writes.
enum PictureReader {

    struct Reading: Sendable {
        var text: String?
        var labels: [String]
        var isEmpty: Bool { text == nil && labels.isEmpty }
    }

    /// The recognizer's language order: the person's own first, then the
    /// other one the app speaks. Measured 2026-10-22 on the Mac: with
    /// English first, the recognizer skips Chinese lines outright; with
    /// Chinese first it reads both scripts but English at half the
    /// confidence and with stray glyphs. So English-first readers get a
    /// second, Chinese-first pass whose Han lines are added.
    static var recognitionLanguages: [Locale.Language] {
        let chineseFirst = Locale.preferredLanguages.first.map { $0.hasPrefix("zh") } ?? false
        return (chineseFirst ? ["zh-Hans", "en-US"] : ["en-US", "zh-Hans"]).map { Locale.Language(identifier: $0) }
    }

    /// Reads every picture, in order, into one reading. Best-effort per
    /// picture: a picture Vision cannot read contributes nothing.
    static func read(_ datas: [Data]) async -> Reading {
        var lines: [String] = []
        var identifiers: [String] = []
        for data in datas {
            lines += await recognizeText(in: data)
            identifiers += await classify(data)
        }
        return Reading(
            text: PictureReading.tidyText(lines),
            labels: PictureReading.tidyLabels(identifiers)
        )
    }

    // MARK: Text

    /// Lines of text in the picture, in reading order. An English-first
    /// pass misses Chinese, so when the person's order is English first a
    /// Chinese-first pass follows and its Han lines join the end.
    private static func recognizeText(in data: Data) async -> [String] {
        let languages = recognitionLanguages
        var lines = await recognizeText(in: data, languages: languages)
        if languages.first?.languageCode?.identifier != "zh" {
            let chinese = await recognizeText(in: data, languages: languages.reversed())
            lines += chinese.filter { $0.unicodeScalars.contains { $0.properties.isIdeographic } }
        }
        return lines
    }

    private static func recognizeText(in data: Data, languages: [Locale.Language]) async -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: data)
        } catch {
            #if DEBUG
            print("🖼 PictureReading: text recognition failed: \(error)")
            #endif
            return []
        }
        // Reading order: top to bottom, then left to right. Vision's
        // coordinates have the origin at the bottom left.
        let ordered = observations.sorted { a, b in
            let ya = a.boundingBox.origin.y, yb = b.boundingBox.origin.y
            if abs(ya - yb) > 0.02 { return ya > yb }
            return a.boundingBox.origin.x < b.boundingBox.origin.x
        }
        return ordered.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
            return candidate.string
        }
    }

    // MARK: Scene

    /// Labels the classifier is confident of, most confident first.
    /// Measured 2026-10-22: Apple's precision gate
    /// (`hasMinimumRecall(0.01, forPrecision: 0.9)`) kept nothing for a
    /// receipt (document 0.64) or a waterfall photo (waterfall 0.81), so
    /// the gate is confidence: 0.3 and up, else the single best label when
    /// it clears 0.15 (a sunset gradient read as "moon" at 0.16).
    private static func classify(_ data: Data) async -> [String] {
        let request = ClassifyImageRequest()
        let observations: [ClassificationObservation]
        do {
            observations = try await request.perform(on: data)
        } catch {
            #if DEBUG
            print("🖼 PictureReading: classification failed: \(error)")
            #endif
            return []
        }
        let sorted = observations.sorted { $0.confidence > $1.confidence }
        let confident = sorted.filter { $0.confidence >= 0.3 }
        if !confident.isEmpty { return confident.map(\.identifier) }
        return sorted.first.flatMap { $0.confidence >= 0.15 ? [$0.identifier] : nil } ?? []
    }
}
