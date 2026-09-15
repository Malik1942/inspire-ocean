#if DEBUG
import Foundation
import SwiftData
import UIKit

/// DEBUG-only library used to recapture marketing screens (Show Related, etc.).
/// Activated with `OCEAN_SCREENSHOT_SEED=1` (or `SIMCTL_CHILD_OCEAN_SCREENSHOT_SEED`
/// via simctl). Replaces whatever is in the store so the ranking has real
/// neighbors — a lone sunset card next to Apple HIG cannot demonstrate kinship.
enum SeedScreenshot {

    @MainActor
    static func replaceLibrary(in context: ModelContext) {
        if let nodes = try? context.fetch(FetchDescriptor<Node>()) {
            for node in nodes { context.delete(node) }
        }

        let now = Date()
        func days(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        func hours(_ h: Double) -> Date { now.addingTimeInterval(-h * 3_600) }

        // Color / light cluster — Show Related on the sunset must surface these.
        let light = "light and color"
        insert(
            context,
            kind: .image,
            title: "Sunset gradient study",
            text: "The orange does not end. It cools into violet before the horizon eats it. Sample this before picking any dusk palette.",
            themes: [light, "visual study"],
            at: days(18),
            image: sunsetStudy()
        )
        insert(
            context,
            kind: .image,
            title: "Golden hour on the walk home",
            text: "Streetlights coming on while the sky is still warm. Same sunset gradient, just in the city — peach on brick, then slate.",
            themes: [light, "visual study"],
            at: days(16),
            image: goldenHour()
        )
        insert(
            context,
            kind: .text,
            title: "Warm to cool, not a filter",
            text: "Stop adding an orange overlay. The sunset is already a temperature shift: 3500K down into blue. Match that, don't fake it.",
            themes: [light],
            at: days(12)
        )
        insert(
            context,
            kind: .image,
            title: "Desk at 6pm",
            text: "The wall goes peach then slate as the sun drops. Worth sampling before I pick the app background.",
            themes: [light, "interior"],
            at: days(9),
            image: windowDusk()
        )

        // Product / reading / everyday — realistic captures, different meaning.
        insertLink(
            context,
            title: "Apple Design Principles",
            text: "The HIG contains guidance and best practices that keep an interface feeling like it belongs on the phone.",
            url: "https://developer.apple.com/design/human-interface-guidelines",
            linkTitle: "Human Interface Guidelines",
            linkDescription: "Guidance and best practices for designing great app experiences.",
            themes: ["user experience", "interface design"],
            at: days(20),
            image: higPreview()
        )
        insert(
            context,
            kind: .text,
            title: "A button that doesn't need a label",
            text: "If the icon is the action, the word next to it is noise. Cut the word first.",
            themes: ["interface design"],
            at: days(7)
        )
        insertLink(
            context,
            title: "Are.na Editorial",
            text: "Notes on attention, collecting, and slow software. A reminder that saving is not the same as seeing.",
            url: "https://www.are.na/editorial",
            linkTitle: "Are.na Editorial",
            linkDescription: "Notes on attention, collecting, and slow software.",
            themes: ["reading", "collecting"],
            at: days(19),
            image: arenaPreview()
        )
        insert(
            context,
            kind: .text,
            title: "Half a sentence from the train",
            text: "What if the home screen was just one thought, not a grid.",
            themes: ["product ideas"],
            at: hours(5)
        )
        insert(
            context,
            kind: .text,
            title: "Weeknight noodles",
            text: "Chili oil, garlic, leftover greens. Ten minutes. Don't lose this one.",
            themes: ["cooking"],
            at: hours(8)
        )
        insert(
            context,
            kind: .text,
            title: "Four notes in the cafe",
            text: "A melody I couldn't hum later. Fell between conversation and the espresso machine.",
            themes: ["sound & music"],
            at: days(2)
        )

        try? context.save()
    }

    @MainActor
    private static func insert(
        _ context: ModelContext,
        kind: NodeKind,
        title: String,
        text: String,
        themes: [String],
        at: Date,
        image: Data? = nil
    ) {
        let node = NodeComposer.make(
            kind: kind,
            title: title,
            text: text,
            imageData: image,
            detectThemes: false
        )
        node.themes = themes
        node.hue = NodeComposer.hue(for: themes.first ?? title)
        node.createdAt = at
        node.updatedAt = at
        context.insert(node)
    }

    @MainActor
    private static func insertLink(
        _ context: ModelContext,
        title: String,
        text: String,
        url: String,
        linkTitle: String,
        linkDescription: String,
        themes: [String],
        at: Date,
        image: Data
    ) {
        let node = NodeComposer.make(
            kind: .link,
            title: title,
            text: text,
            linkURLString: url,
            detectThemes: false
        )
        node.themes = themes
        node.hue = NodeComposer.hue(for: themes.first ?? title)
        node.linkTitle = linkTitle
        node.linkDescription = linkDescription
        node.linkImageData = image
        node.linkEnrichmentState = .enriched
        node.linkEnrichmentNote = "Seeded for screenshots."
        node.createdAt = at
        node.updatedAt = at
        context.insert(node)
    }

    // MARK: Tiny generated banners — enough to read as a photo or a link card.

    private static func sunsetStudy() -> Data {
        draw(width: 800, height: 520) { ctx, rect in
            fillGradient(ctx, rect, [
                (0, UIColor(red: 0.12, green: 0.10, blue: 0.28, alpha: 1)),
                (0.45, UIColor(red: 0.72, green: 0.32, blue: 0.28, alpha: 1)),
                (0.72, UIColor(red: 0.96, green: 0.62, blue: 0.28, alpha: 1)),
                (1, UIColor(red: 0.08, green: 0.09, blue: 0.16, alpha: 1))
            ])
            let sunR: CGFloat = 54
            let sun = CGRect(x: rect.midX - sunR, y: rect.height * 0.58 - sunR, width: sunR * 2, height: sunR * 2)
            ctx.setFillColor(UIColor(red: 1, green: 0.92, blue: 0.55, alpha: 1).cgColor)
            ctx.fillEllipse(in: sun)
            ctx.setFillColor(UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: rect.height * 0.68, width: rect.width, height: rect.height * 0.32))
        }
    }

    private static func goldenHour() -> Data {
        draw(width: 800, height: 520) { ctx, rect in
            fillGradient(ctx, rect, [
                (0, UIColor(red: 0.95, green: 0.55, blue: 0.28, alpha: 1)),
                (0.4, UIColor(red: 0.78, green: 0.28, blue: 0.32, alpha: 1)),
                (0.75, UIColor(red: 0.22, green: 0.12, blue: 0.22, alpha: 1)),
                (1, UIColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1))
            ])
            ctx.setFillColor(UIColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 0.85).cgColor)
            ctx.fill(CGRect(x: 0, y: rect.height * 0.62, width: rect.width, height: rect.height * 0.38))
            ctx.setFillColor(UIColor(red: 1, green: 0.82, blue: 0.45, alpha: 0.55).cgColor)
            for i in 0..<6 {
                let x = 40 + CGFloat(i) * 120
                let h = 18 + CGFloat((i * 17) % 28)
                ctx.fill(CGRect(x: x, y: rect.height * 0.70, width: 10, height: h))
            }
        }
    }

    private static func windowDusk() -> Data {
        draw(width: 800, height: 520) { ctx, rect in
            fillGradient(ctx, rect, [
                (0, UIColor(red: 0.98, green: 0.72, blue: 0.48, alpha: 1)),
                (0.55, UIColor(red: 0.62, green: 0.42, blue: 0.48, alpha: 1)),
                (1, UIColor(red: 0.22, green: 0.26, blue: 0.38, alpha: 1))
            ])
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.28).cgColor)
            ctx.setLineWidth(10)
            let inset = rect.insetBy(dx: 90, dy: 50)
            ctx.stroke(inset)
            ctx.move(to: CGPoint(x: inset.midX, y: inset.minY))
            ctx.addLine(to: CGPoint(x: inset.midX, y: inset.maxY))
            ctx.move(to: CGPoint(x: inset.minX, y: inset.midY))
            ctx.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
            ctx.strokePath()
        }
    }

    private static func higPreview() -> Data {
        draw(width: 800, height: 420) { ctx, rect in
            ctx.setFillColor(UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1).cgColor)
            ctx.fill(rect)
            let blobs: [(CGFloat, CGFloat, CGFloat, UIColor)] = [
                (180, 140, 160, UIColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 0.85)),
                (520, 90, 140, UIColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 0.75)),
                (400, 260, 180, UIColor(red: 0.45, green: 0.85, blue: 0.70, alpha: 0.70)),
                (120, 300, 110, UIColor(red: 0.95, green: 0.80, blue: 0.35, alpha: 0.65))
            ]
            for (x, y, r, color) in blobs {
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    private static func arenaPreview() -> Data {
        draw(width: 800, height: 420) { ctx, rect in
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(rect)
            ctx.setFillColor(UIColor.black.cgColor)
            star(ctx, at: CGPoint(x: rect.midX - 70, y: rect.midY), r: 36)
            star(ctx, at: CGPoint(x: rect.midX + 70, y: rect.midY), r: 36)
        }
    }

    private static func star(_ ctx: CGContext, at c: CGPoint, r: CGFloat) {
        let path = CGMutablePath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let rad = i.isMultiple(of: 2) ? r : r * 0.38
            let p = CGPoint(x: c.x + cos(angle) * rad, y: c.y + sin(angle) * rad)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }

    private static func fillGradient(_ ctx: CGContext, _ rect: CGRect, _ stops: [(CGFloat, UIColor)]) {
        let colors = stops.map { $0.1.cgColor } as CFArray
        let locations = stops.map { $0.0 }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: 0), end: CGPoint(x: rect.midX, y: rect.height), options: [])
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext, CGRect) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { ctx in
            body(ctx.cgContext, CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.86) ?? Data()
    }
}
#endif
