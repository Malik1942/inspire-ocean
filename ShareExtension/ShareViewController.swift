import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// What was shared into Ocean from another app.
struct SharePayload {
    var text: String?
    var urlString: String?
    var imageData: Data?
}

/// Drift Capture entry point (§7): the iOS share sheet. Captures screenshots,
/// photos, selected text, and links from any app straight into the Ocean's
/// shared store (App Group), so they appear alongside in-app captures.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadPayload { [weak self] payload in
            self?.present(payload: payload)
        }
    }

    private func present(payload: SharePayload) {
        let root = ShareCaptureView(
            payload: payload,
            onSave: { [weak self] note in self?.save(payload: payload, note: note) },
            onCancel: { [weak self] in self?.complete() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    // MARK: Extract shared content

    private func loadPayload(completion: @escaping (SharePayload) -> Void) {
        var payload = SharePayload()
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else {
            completion(payload); return
        }

        let group = DispatchGroup()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data { payload.imageData = data }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                    if let url = value as? URL { payload.urlString = url.absoluteString }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
                    if let text = value as? String { payload.text = text }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion(payload) }
    }

    // MARK: Save into the shared Ocean

    private func save(payload: SharePayload, note: String) {
        let container = Persistence.makeContainer()
        let context = ModelContext(container)

        let kind: NodeKind
        if payload.imageData != nil { kind = .image }
        else if payload.urlString != nil { kind = .link }
        else { kind = .text }

        let body = [note, payload.text ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let node = NodeComposer.make(
            kind: kind,
            text: body,
            linkURLString: payload.urlString,
            imageData: payload.imageData
        )
        context.insert(node)
        try? context.save()
        complete()
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
