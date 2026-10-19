import SwiftUI
#if DEBUG
import OSLog
#endif

/// Lazy column masonry. Nodes are distributed across `columns` by an estimated
/// height (shortest column first), and each column is a `LazyVStack`, so only
/// the cells on screen are ever realized or measured.
///
/// Why not a custom `Layout`: a SwiftUI `Layout` must measure every subview
/// synchronously in one pass. Measured at `OCEAN_SIM_COUNT=200`, that pass cost
/// 213ms for a 176-cell group and 112ms for the 200-cell Related ribbon: a
/// visible scroll hitch (well over the 17ms frame budget) and an arrangement
/// switch over the 100ms budget. Wrapping the Layout in a `LazyVStack` does not
/// help, because realizing the group realizes the whole eager Layout inside it.
/// N columns of `LazyVStack` keep the masonry look while realizing cells
/// incrementally, which is the fallback the plan named for this exact scale.
///
/// Column balance uses an estimate, not measured heights (measuring every cell
/// up front is the cost we are avoiding); slight unevenness at the column feet
/// is the accepted trade for lazy realization. `columns` is the single density
/// value Handoffs 2 and 3 drive.
struct MasonryColumns<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    var columns: Int
    var spacing: CGFloat = 12
    let estimatedHeight: (Item) -> CGFloat
    /// Handoff 2 focus ordering. Items with a non-nil rank are pulled to the top
    /// of their column, ordered by ascending rank (0 = the focused anchor); nil
    /// keeps base order below them. Column ASSIGNMENT is always computed from the
    /// passed (base) order regardless of rank, so a focused card keeps its column
    /// and only moves vertically: an in-column glide, never a cross-column snap
    /// (which lazy columns cannot render). Default: no focus, plain base order.
    var frontRank: (Item) -> Int? = { _ in nil }
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(distribute()) { column in
                LazyVStack(alignment: .leading, spacing: spacing) {
                    ForEach(column.items) { item in cell(item) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        #if DEBUG
        .onAppear { LibraryPerf.endColdOpen(cells: items.count) }
        #endif
    }

    private struct Column: Identifiable {
        let index: Int
        let items: [Item]
        var id: Int { index }
    }

    /// Greedy shortest-column packing on estimated heights. O(n * columns), and
    /// recomputed only when `items` or `columns` change, not per scroll frame
    /// (scrolling a `ScrollView` does not re-evaluate this view's body).
    private func distribute() -> [Column] {
        let count = max(1, columns)
        // 1. Stable column assignment from the base (passed) order, so a card
        //    keeps its column across a focus reorder.
        var buckets = Array(repeating: [(base: Int, item: Item)](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)
        for (base, item) in items.enumerated() {
            var shortest = 0
            for column in 1..<count where heights[column] < heights[shortest] { shortest = column }
            buckets[shortest].append((base, item))
            heights[shortest] += estimatedHeight(item) + spacing
        }
        // 2. Within each column, pull ranked (front) items to the top by ascending
        //    rank, keeping unranked items in base order below (base index is the
        //    stable tie-break). Reordering within a column does not change its
        //    total height, so the base assignment's balance is preserved.
        for column in buckets.indices {
            buckets[column].sort { lhs, rhs in
                let rankL = frontRank(lhs.item) ?? Int.max
                let rankR = frontRank(rhs.item) ?? Int.max
                if rankL != rankR { return rankL < rankR }
                return lhs.base < rhs.base
            }
        }
        return buckets.enumerated().map { entry in
            Column(index: entry.offset, items: entry.element.map(\.item))
        }
    }
}

#if DEBUG
/// DEBUG-only performance signposts for the Library grid. It lives in this file
/// (one of the Handoff 1 write-set files) rather than a new file, so the change
/// stays inside the approved write set. Read the numbers from the simulator log
/// (subsystem `com.oryne.perf`) or correlate the intervals in Instruments.
enum LibraryPerf {
    static let signposter = OSSignposter(subsystem: "com.oryne.perf", category: "library")
    static let log = Logger(subsystem: "com.oryne.perf", category: "library")

    // Cold open: begun on Library's first appear, ended when the first grid
    // content (a masonry column container) appears.
    private static var coldOpenStart: CFAbsoluteTime?
    private static var coldOpenState: OSSignpostIntervalState?
    private static var coldOpenDone = false

    static func beginColdOpen() {
        guard !coldOpenDone, coldOpenStart == nil else { return }
        coldOpenStart = CFAbsoluteTimeGetCurrent()
        coldOpenState = signposter.beginInterval("coldOpen")
    }

    static func endColdOpen(cells: Int) {
        guard !coldOpenDone, let start = coldOpenStart, let state = coldOpenState else { return }
        signposter.endInterval("coldOpen", state)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log.notice("coldOpen \(ms, format: .fixed(precision: 1))ms firstContent cells=\(cells) budget=500")
        coldOpenDone = true
    }

    static func arrangeSwitch(snapshotMs: Double, offMainMs: Double, applyMs: Double, cells: Int) {
        let mainMs = snapshotMs + applyMs
        log.notice("arrange.mainThread \(mainMs, format: .fixed(precision: 1))ms (snapshot \(snapshotMs, format: .fixed(precision: 1)) + apply \(applyMs, format: .fixed(precision: 1))), offMain \(offMainMs, format: .fixed(precision: 1))ms cells=\(cells) budget=100")
    }
}
#endif
