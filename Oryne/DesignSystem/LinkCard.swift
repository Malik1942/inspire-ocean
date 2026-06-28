import SwiftUI
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
    /// Detail/read view sets this to surface the device-made summary under the
    /// card — so the enrichment is visible, not only consumed by the AI.
    var showSummary: Bool = false
    /// Provided only in editors; renders a removal control.
    var onRemove: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @State private var showSafari = false

    private var state: LinkEnrichmentState { node.linkEnrichmentState }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if node.hasRichLink || state.isInProgress {
                richCard
            } else {
                plainRow
            }
            if showSummary, let summary = node.linkSummary, !summary.isEmpty {
                summaryBlock(summary)
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
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.linkTitle ?? node.linkURL?.absoluteString ?? "Link")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OceanTheme.foam)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        statusLine
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onRemove {
                removeButton(onRemove)
                    .padding(.trailing, 8)
            }
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(OceanTheme.color(forHue: node.hue).opacity(0.18))
            if let data = node.linkImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
            } else {
                Image(systemName: "link")
                    .font(.title3)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The quiet, progressive line under the title: domain + where enrichment is.
    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            if let domain = node.linkDomain {
                Text(domain).font(.caption2).foregroundStyle(OceanTheme.mist).lineLimit(1)
            }
            switch state {
            case .fetchingMeta, .fetchingContent:
                progressTag("Reading…")
            case .summarizing:
                progressTag("Summarizing…")
            case .enriched:
                if node.linkSummary?.isEmpty == false {
                    Label("Summary", systemImage: "sparkles")
                        .font(.caption2).labelStyle(.titleAndIcon)
                        .foregroundStyle(OceanTheme.faint)
                }
            case .failed(let reason):
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(OceanTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityHint(reason)
            case .notStarted:
                EmptyView()
            }
        }
    }

    private func progressTag(_ text: String) -> some View {
        HStack(spacing: 4) {
            ProgressView().controlSize(.mini).tint(OceanTheme.mist)
            Text(text).font(.caption2).foregroundStyle(OceanTheme.faint)
        }
    }

    // MARK: Plain row (no metadata — never broken)

    private var plainRow: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: "link").font(.callout).foregroundStyle(OceanTheme.mist)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.linkURL?.absoluteString ?? "Link")
                            .font(.callout).foregroundStyle(OceanTheme.foam).lineLimit(1)
                        if case .failed(let reason) = state {
                            Text(reason).font(.caption2).foregroundStyle(OceanTheme.faint).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if case .failed = state {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold)).foregroundStyle(OceanTheme.accent)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry enrichment")
            }
            if let onRemove { removeButton(onRemove).padding(.trailing, 6) }
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Summary surface (detail view)

    private func summaryBlock(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("What this link is about", systemImage: "sparkles")
                .font(.caption2.weight(.medium)).foregroundStyle(OceanTheme.mist)
            Text(summary)
                .font(.footnote).foregroundStyle(OceanTheme.foam.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .foregroundStyle(OceanTheme.mist)
        }
        .buttonStyle(.plain)
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
