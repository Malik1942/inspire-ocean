import Foundation
@preconcurrency import LinkPresentation
import Observation
import UIKit

/// The small icon a site shows for itself (its favicon), one per site, so a
/// link's row says where it is from at a glance. Kept on this device only,
/// in Caches: an icon can always be fetched again, so it needs no field on
/// the thought, nothing synced, and no CloudKit schema. Link enrichment
/// stores the icon LinkPresentation hands over with the preview; a link
/// saved before that fetches its site's icon once, when its row first
/// shows. A site without one keeps the link glyph and is asked again after
/// a week.
@MainActor
@Observable
final class SiteIcons {
    static let shared = SiteIcons()

    /// Decoded icons by site (a link's domain, as `Node.linkDomain` gives it).
    private(set) var icons: [String: UIImage] = [:]

    @ObservationIgnored private var asked: Set<String> = []
    /// One fetch at a time, so opening a long list never fires a burst.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = caches.appendingPathComponent("SiteIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// Long enough for a crisp 14 pt icon at 3x and then some.
    private static let pixelSize: CGFloat = 64
    private static let retryAfter: TimeInterval = 7 * 24 * 60 * 60

    private init() {}

    /// The site a link belongs to, the way `Node.linkDomain` reads it.
    static func site(of url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func icon(for site: String) -> UIImage? { icons[site] }

    /// Makes the site's icon available: from memory, then disk, then once
    /// per launch from the page itself.
    func load(site: String, pageURL: URL) {
        guard icons[site] == nil, !asked.contains(site) else { return }
        asked.insert(site)
        if let image = UIImage(contentsOfFile: file(for: site).path) {
            icons[site] = image
            return
        }
        if let checked = modified(missingMarker(for: site)), Date.now.timeIntervalSince(checked) < Self.retryAfter {
            return
        }
        let previous = queue
        queue = Task {
            await previous?.value
            let data = await Self.fetchIcon(pageURL)
            if let data {
                self.store(data, for: site)
            } else {
                FileManager.default.createFile(atPath: self.missingMarker(for: site).path, contents: nil)
            }
        }
    }

    /// Keeps an icon fetched elsewhere (link enrichment), shrunk to size.
    func store(_ data: Data, for site: String) {
        guard let image = UIImage(data: data), let small = Self.shrink(image) else { return }
        icons[site] = small
        asked.insert(site)
        if let png = small.pngData() {
            try? png.write(to: file(for: site), options: .atomic)
        }
        try? FileManager.default.removeItem(at: missingMarker(for: site))
    }

    // MARK: Files

    private func file(for site: String) -> URL {
        folder.appendingPathComponent(Self.fileName(site) + ".png")
    }

    private func missingMarker(for site: String) -> URL {
        folder.appendingPathComponent(Self.fileName(site) + ".none")
    }

    private func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// A host is already a safe file name, apart from a port's colon.
    private static func fileName(_ site: String) -> String {
        site.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
    }

    // MARK: Fetching

    /// Redraws the icon square at `pixelSize`, keeping its transparency (a
    /// JPEG would put many favicons on a black square).
    private static func shrink(_ image: UIImage) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let size = CGSize(width: pixelSize, height: pixelSize)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Lets the provider ride into its own completion handler, which is the
    /// only other place it is touched, so it lives until the fetch is done.
    private struct ProviderBox: @unchecked Sendable {
        let provider: LPMetadataProvider
    }

    /// The page's icon via LinkPresentation, the same path link enrichment
    /// takes for the preview. Nil on any failure.
    private static func fetchIcon(_ url: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            let box = ProviderBox(provider: LPMetadataProvider())
            box.provider.timeout = 10
            box.provider.startFetchingMetadata(for: url) { metadata, error in
                _ = box
                guard error == nil, let icon = metadata?.iconProvider,
                      icon.canLoadObject(ofClass: UIImage.self) else {
                    continuation.resume(returning: nil)
                    return
                }
                icon.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: (object as? UIImage)?.pngData())
                }
            }
        }
    }
}
