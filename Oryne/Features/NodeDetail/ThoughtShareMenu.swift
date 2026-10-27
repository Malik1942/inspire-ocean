import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

/// Hands one thought to the system share sheet.
///
/// The button shares immediately. The sheet rises from the bottom on the
/// phone and receives the thought's text and its pictures. It does not
/// write to the thought, and closing it is not treated as delivery.
struct ThoughtShareMenu: View {
    let node: Node

    @State private var preparing = false
    @State private var anchor: UIView?
    @State private var showBlocked = false
    @State private var generation = 0

    var body: some View {
        Button {
            share()
        } label: {
            if preparing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .accessibilityLabel("Share")
        .disabled(preparing)
        .background(ShareAnchor { anchor = $0 })
        .alert("Couldn't prepare the pictures", isPresented: $showBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("These pictures can't be shared.")
        }
    }

    /// Reads the thought on the main thread, then prepares pictures off it.
    private func share() {
        guard let content = ThoughtShareContent.make(from: node) else { return }
        let text = content.plainText
        let subject = mailSubject(for: content)
        if content.images.isEmpty {
            present(text: text, subject: subject, images: [])
            return
        }

        generation += 1
        let token = generation
        let images = content.images
        preparing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let prepared = ShareImage.preparedAll(images, maxPixel: ShareImage.maxPixel)
            DispatchQueue.main.async {
                guard token == generation else { return }
                preparing = false
                guard prepared.skipped > 0 else {
                    present(text: text, subject: subject, images: prepared.images)
                    return
                }
                if text.isEmpty, prepared.images.isEmpty {
                    showBlocked = true
                } else {
                    confirmSkip(
                        skipped: prepared.skipped,
                        text: text,
                        subject: subject,
                        images: prepared.images
                    )
                }
            }
        }
    }

    /// A mail subject from the user's title, else the first line they wrote.
    private func mailSubject(for content: ThoughtShareContent) -> String {
        if let title = content.title, !title.isEmpty { return title }
        let line = content.words.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
        return String(localized: "Thought")
    }

    /// The share sheet presents from this alert's action, which runs only
    /// after the alert has closed.
    private func confirmSkip(skipped: Int, text: String, subject: String, images: [Data]) {
        let alert = UIAlertController(
            title: String(localized: "Some pictures couldn't be prepared"),
            message: leftOut(skipped),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: String(localized: "Share without them"),
            style: .default
        ) { _ in
            present(text: text, subject: subject, images: images)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        guard let host = topViewController() else { return }
        host.present(alert, animated: true)
    }

    private func leftOut(_ skipped: Int) -> String {
        if skipped == 1 {
            return String(localized: "1 picture couldn't be prepared.")
        }
        return String(localized: "\(skipped) pictures couldn't be prepared.")
    }

    private func present(text: String, subject: String, images: [Data]) {
        guard !text.isEmpty || !images.isEmpty else { return }
        let controller = UIActivityViewController(
            activityItems: activityItems(text: text, subject: subject, images: images),
            applicationActivities: nil
        )
        guard let host = topViewController() else { return }
        // A phone presents this from the bottom. The anchor is only the
        // iPad popover's source, which crashes without one.
        if host.traitCollection.horizontalSizeClass == .regular,
           let popover = controller.popoverPresentationController {
            let source = (anchor?.window == nil ? nil : anchor) ?? keyWindow
            if let source {
                popover.sourceView = source
                popover.sourceRect = source.bounds
            }
        }
        // The sheet closing is not delivery. There is nothing to report.
        controller.completionWithItemsHandler = { _, _, _, _ in }
        host.present(controller, animated: true)
    }

    private func activityItems(text: String, subject: String, images: [Data]) -> [Any] {
        var items: [Any] = []
        if !text.isEmpty {
            items.append(ThoughtTextItem(text: text, subject: subject, preview: images.first))
        }
        items.append(contentsOf: images.map(jpegProvider))
        return items
    }

    private func jpegProvider(_ data: Data) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.jpeg.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private func topViewController() -> UIViewController? {
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

/// The view the share sheet anchors to, so the iPad popover has a source.
private struct ShareAnchor: UIViewRepresentable {
    var onView: (UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.backgroundColor = .clear
        DispatchQueue.main.async { onView(view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// The text half of a share: the words, a mail subject, and a preview.
private final class ThoughtTextItem: NSObject, UIActivityItemSource {
    let text: String
    let subject: String
    let preview: Data?

    init(text: String, subject: String, preview: Data?) {
        self.text = text
        self.subject = subject
        self.preview = preview
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = subject
        if let preview {
            metadata.imageProvider = NSItemProvider(
                item: preview as NSData,
                typeIdentifier: UTType.jpeg.identifier
            )
        }
        return metadata
    }
}
