import SwiftUI

/// What a half opens beside a split page (iPhone Duo's inner display,
/// turned): it stands in the half across from the one that opened it,
/// where a sheet would rise as a card over both. The halves read as two
/// screens, so whatever one of them opens lands on the other (Malik,
/// 2026-11-10): a thought's branch, its edit, its move, a theme's current,
/// a current's capture.
///
/// The pages are one chain out from the page's own pane, each across from
/// the one before it. Opening from a page puts away whatever was opened
/// after it; closing a page puts away what it opened too. The newest page
/// in a half covers the ones beneath until it closes.
@MainActor @Observable
final class BesidePages {
    /// One page opened beside: what it shows, the half it stands in, and
    /// what closing it tells whoever opened it.
    struct Page: Identifiable {
        let id = UUID()
        let side: BigScreen.Side
        let content: AnyView
        let onClose: @MainActor () -> Void
    }

    /// How a page opens one across from itself, and closes it again.
    struct Opener {
        let open: @MainActor (AnyView, @escaping @MainActor () -> Void) -> Page.ID?
        let close: @MainActor (Page.ID) -> Void
    }

    private(set) var pages: [Page] = []

    /// Whether a page stands in this half.
    func covers(_ side: BigScreen.Side) -> Bool {
        pages.contains { $0.side == side }
    }

    /// The opener for a page `depth` pages along the chain (the page's own
    /// pane is 0), standing in `side`.
    func opener(depth: Int, on side: BigScreen.Side) -> Opener {
        Opener(
            open: { [weak self] content, onClose in
                guard let self else { return nil }
                close(from: depth)
                let page = Page(side: side.across, content: content, onClose: onClose)
                pages.append(page)
                return page.id
            },
            close: { [weak self] id in self?.close(id) }
        )
    }

    /// Closes one page and whatever it opened.
    func close(_ id: Page.ID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        close(from: index)
    }

    /// Closes every page: the pane they grew from has gone.
    func closeAll() { close(from: 0) }

    private func close(from index: Int) {
        guard index < pages.count else { return }
        let closed = pages[index...]
        pages.removeSubrange(index...)
        for page in closed.reversed() { page.onClose() }
    }
}

extension View {
    /// The pages opened beside this split page, each `half` wide over the
    /// half it stands in.
    func besidePages(_ pages: BesidePages, half: CGFloat) -> some View {
        overlay(alignment: .leading) { BesidePageLayer(pages: pages, side: .leading, half: half) }
            .overlay(alignment: .trailing) { BesidePageLayer(pages: pages, side: .trailing, half: half) }
    }

    /// A sheet, or beside a split page the half across from this one
    /// (`BesidePages`). Phones, and pages that don't split, keep the sheet.
    func besideSheet<Sheet: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        modifier(BesideSheet(isPresented: isPresented, onDismiss: onDismiss, sheet: content))
    }

    /// `besideSheet(isPresented:)` for a sheet shown for an item.
    func besideSheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        modifier(BesideItemSheet(item: item, onDismiss: onDismiss, sheet: content))
    }
}

/// The newest page in one half, with the half's close, side and opener.
/// It fades in and out as a pane does.
private struct BesidePageLayer: View {
    let pages: BesidePages
    let side: BigScreen.Side
    let half: CGFloat

    var body: some View {
        let depth = pages.pages.lastIndex { $0.side == side }
        Group {
            if let depth {
                let page = pages.pages[depth]
                page.content
                    .id(page.id)
                    .environment(\.closePane) { pages.close(page.id) }
                    .environment(\.paneSide, side)
                    .environment(\.openBeside, pages.opener(depth: depth + 1, on: side))
                    .frame(width: half)
                    .transition(.opacity)
            }
        }
        .animation(OceanMotion.standard, value: depth.map { pages.pages[$0].id })
    }
}

/// While shown beside, `isPresented` stays true; closing the page sets it
/// back, and setting it back closes the page.
private struct BesideSheet<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let sheet: () -> Sheet

    @Environment(\.openBeside) private var openBeside
    @State private var page: BesidePages.Page.ID?

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(get: { openBeside == nil && isPresented }, set: { isPresented = $0 }),
                onDismiss: onDismiss,
                content: sheet
            )
            .onChange(of: isPresented) { _, shown in
                guard let openBeside else { return }
                if shown {
                    page = openBeside.open(AnyView(sheet())) {
                        page = nil
                        isPresented = false
                        onDismiss?()
                    }
                } else if let page {
                    openBeside.close(page)
                }
            }
    }
}

/// While shown beside, `item` stays set; closing the page clears it, and
/// clearing it closes the page. Another item takes the page's place.
private struct BesideItemSheet<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let sheet: (Item) -> Sheet

    @Environment(\.openBeside) private var openBeside
    @State private var page: BesidePages.Page.ID?

    func body(content: Content) -> some View {
        content
            .sheet(
                item: Binding(get: { openBeside == nil ? item : nil }, set: { item = $0 }),
                onDismiss: onDismiss,
                content: sheet
            )
            .onChange(of: item?.id) { _, id in
                guard let openBeside else { return }
                if let id, let shown = item {
                    page = openBeside.open(AnyView(sheet(shown))) {
                        page = nil
                        if item?.id == id { item = nil }
                        onDismiss?()
                    }
                } else if let page {
                    openBeside.close(page)
                }
            }
    }
}
