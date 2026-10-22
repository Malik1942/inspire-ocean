import XCTest
import Foundation

/// Unit tests for `Resurfacing.pick`: once a thought rises today, it holds
/// all day, whatever else is captured, archived or deleted.
///
/// The observed bug (2026-10-22): archiving "A button that doesn't need a
/// label" from Tide's "Drifted in" moved today's pick from "Warm to cool,
/// not a filter" to "Are.na Editorial". The echo lift reads the themes of
/// the five newest thoughts, so any change among them re-scored the day.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class ResurfacingTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "ResurfacingTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func hoursAgo(_ hours: Double) -> Date {
        now.addingTimeInterval(-hours * 3_600)
    }

    private struct Ocean {
        let warm: Node
        let arena: Node
        let button: Node
        let all: [Node]
    }

    /// Two forgotten thoughts, equally old, below six fresh ones. "Warm to
    /// cool" shares a theme with the newest capture, the button; "Are.na
    /// Editorial" shares one with the sixth newest, just past the five the
    /// echo reads. Without the button, the echo moves from one to the other.
    private func makeOcean() -> Ocean {
        let warm = Node(createdAt: hoursAgo(30 * 24), title: "Warm to cool, not a filter", themes: ["color"])
        let arena = Node(createdAt: hoursAgo(30 * 24), title: "Are.na Editorial", themes: ["editorial"])
        let button = Node(createdAt: hoursAgo(1), title: "A button that doesn't need a label", themes: ["interface", "color"])
        let errands = (2...5).map { Node(createdAt: hoursAgo(Double($0)), title: "Errand \($0)", themes: ["errands"]) }
        let grids = Node(createdAt: hoursAgo(6), title: "Magazine grids", themes: ["editorial"])
        return Ocean(warm: warm, arena: arena, button: button, all: [warm, arena, button] + errands + [grids])
    }

    private func pick(_ nodes: [Node], on day: Date? = nil) -> Node? {
        Resurfacing.pick(from: nodes, now: day ?? now, defaults: defaults)
    }

    /// The scoring alone, with nothing held from earlier in the day.
    private func scored(_ nodes: [Node]) throws -> Node? {
        let suite = "ResurfacingTests-scored-\(UUID().uuidString)"
        let fresh = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { fresh.removePersistentDomain(forName: suite) }
        return Resurfacing.pick(from: nodes, now: now, defaults: fresh)
    }

    // MARK: - The fixture

    /// The tests below rest on this: scored afresh, the pick would move
    /// when the button goes.
    func test_scoring_followsTheEchoOfTheFiveNewest() throws {
        let ocean = makeOcean()
        XCTAssertEqual(try scored(ocean.all)?.title, ocean.warm.title)
        XCTAssertEqual(try scored(ocean.all.filter { $0 !== ocean.button })?.title, ocean.arena.title)
    }

    // MARK: - Holds

    func test_archivingAnotherThought_keepsTodaysPick() {
        let ocean = makeOcean()
        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)

        ocean.button.isArchived = true

        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)
    }

    func test_deletingAnotherThought_keepsTodaysPick() {
        let ocean = makeOcean()
        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)

        let remaining = ocean.all.filter { $0 !== ocean.button }

        XCTAssertEqual(pick(remaining)?.title, ocean.warm.title)
    }

    func test_capturingANewThought_keepsTodaysPick() {
        let ocean = makeOcean()
        let before = ocean.all.filter { $0 !== ocean.button }
        XCTAssertEqual(pick(before)?.title, ocean.arena.title)

        let captured = Node(createdAt: now, title: "Cool blue at dusk", themes: ["color"])

        XCTAssertEqual(pick(before + [captured])?.title, ocean.arena.title)
    }

    // MARK: - Moves

    func test_archivingTodaysPick_raisesAnother() {
        let ocean = makeOcean()
        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)

        ocean.warm.isArchived = true

        XCTAssertEqual(pick(ocean.all)?.title, ocean.arena.title)
    }

    func test_restingTodaysPick_raisesAnother() {
        let ocean = makeOcean()
        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)

        Resurfacing.Rest.rest(ocean.warm.id, now: now, defaults: defaults)

        XCTAssertEqual(pick(ocean.all)?.title, ocean.arena.title)
    }

    /// A new day scores afresh: the echo moved yesterday, so now the pick does.
    func test_nextDay_choosesAgain() throws {
        let ocean = makeOcean()
        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)
        ocean.button.isArchived = true
        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)

        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: now))

        XCTAssertEqual(pick(ocean.all, on: tomorrow)?.title, ocean.arena.title)
    }

    /// Undo puts the thought back exactly, so today's pick comes back too.
    func test_undoingTheArchiveOfTodaysPick_bringsItBack() {
        let ocean = makeOcean()
        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)
        ocean.warm.isArchived = true
        XCTAssertEqual(pick(ocean.all)?.title, ocean.arena.title)

        ocean.warm.isArchived = false

        XCTAssertEqual(pick(ocean.all)?.title, ocean.warm.title)
    }
}
