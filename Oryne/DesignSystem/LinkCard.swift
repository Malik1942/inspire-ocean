import SwiftUI
import SwiftData
import SafariServices

/// A link rendered the way Oryne renders everything else: dark, glassy, calm.
///
/// It reads the live `Node`, so it tracks enrichment as it lands — a bare URL
/// becomes a thumbnail + title + domain, with a quiet line that moves through
/// *reading → summarizing → enriched*. If nothing past the URL ever arrives the
/// card stays a plain, tappable link with a retry; the link is never broken by a
/// failed enrichment.
struct LinkCard: View {
    let node: Node
    /// Provided only in editors; renders a removal control.
    var onRemove: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @State private var showSafari = false

    private var state: LinkEnrichmentState { node.linkEnrichmentState }

    var body: some View {
        Group {
            if node.hasRichLink || state.isInProgress {
                richCard
            } else {
                plainRow
            }
        }
        .sheet(isPresented: $showSafari) {
            if let url = node.linkURL { SafariView(url: url).ignoresSafeArea() }
        }
    }

    // MARK: Rich card

    private var richCard: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: OceanSpacing.item) {
                    thumbnail
                    VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                        Text(node.linkTitle ?? node.linkURL?.absoluteString ?? String(localized: "Link"))
                            .oceanText(OceanType.tileTitle)
                            .foregroundStyle(OceanTheme.foam)
                            .multilineTextAlignment(.leading)
                            .oceanLineLimit(2)
                        statusLine
                    }
                    Spacer(minLength: 0)
                }
                .padding(OceanSpacing.insetCompact)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onRemove {
                removeButton(onRemove)
                    .padding(.trailing, OceanSpacing.gap)
            }
        }
        // Flat, like every tile; media radius, since it stands where a
        // picture would at the top of a thought.
        .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous)))
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OceanRadius.thumbnail, style: .continuous)
                .fill(OceanTheme.fill)
            if let data = node.linkImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
            } else {
                Image(systemName: "link")
                    .font(OceanType.glyphLarge)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
        .frame(width: OceanSize.pictureTile, height: OceanSize.pictureTile)
        .clipShape(RoundedRectangle(cornerRadius: OceanRadius.thumbnail, style: .continuous))
    }

    /// The quiet, progressive line under the title: domain + where enrichment is.
    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: OceanSpacing.snug) {
            if let domain = node.linkDomain {
                Text(domain).oceanText(OceanType.meta).foregroundStyle(OceanTheme.mist).lineLimit(1)
            }
            switch state {
            case .fetchingMeta, .fetchingContent:
                progressTag("Reading…")
            case .summarizing:
                progressTag("Summarizing…")
            case .enriched:
                // The summary itself sits under the title on the thought's
                // page, labelled there.
                EmptyView()
            case .failed(let reason):
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.oceanLink)
                .accessibilityHint(reason)
            case .notStarted:
                EmptyView()
            }
        }
    }

    private func progressTag(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: OceanSpacing.snug) {
            ProgressView().controlSize(.mini).tint(OceanTheme.mist)
            Text(text).oceanText(OceanType.meta).foregroundStyle(OceanTheme.mist)
        }
    }

    // MARK: Plain row (no metadata — never broken)

    private var plainRow: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: OceanSpacing.snug) {
                    Image(systemName: "link").oceanText(OceanType.tileTitle).foregroundStyle(OceanTheme.mist)
                    VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                        Text(node.linkURL?.absoluteString ?? String(localized: "Link"))
                            .oceanText(OceanType.tileTitle).foregroundStyle(OceanTheme.foam).oceanLineLimit(1)
                        if case .failed(let reason) = state {
                            // A sentence to act on, so secondary in text and
                            // never cut: the row's minimum height lets it grow.
                            Text(reason)
                                .oceanText(OceanType.secondary)
                                .foregroundStyle(OceanTheme.text)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, OceanSpacing.gap).padding(.horizontal, OceanSpacing.insetCompact)
                .frame(minHeight: OceanControlSize.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if case .failed = state {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .font(OceanType.glyphDisclosure)
                }
                .buttonStyle(.oceanLink)
                .accessibilityLabel("Retry enrichment")
            }
            if let onRemove { removeButton(onRemove).padding(.trailing, OceanSpacing.snug) }
        }
        .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous)))
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(OceanType.glyphLarge)
        }
        .buttonStyle(.oceanLink(.quiet))
        .accessibilityLabel("Remove link")
    }

    // MARK: Actions

    private func open() {
        guard let url = node.linkURL else { return }
        if url.scheme == "http" || url.scheme == "https" {
            showSafari = true
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func retry() {
        LinkEnrichmentService.shared.enrich(nodeID: node.id, context: context, ai: ai, force: true)
    }
}

/// In-app Safari for opening a saved link without leaving Oryne.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
