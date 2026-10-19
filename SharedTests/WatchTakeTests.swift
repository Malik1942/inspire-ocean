import XCTest
import Foundation

/// The wire format both ends of WatchConnectivity share. No app-module
/// import: SharedTests compiles `Shared/` directly.
final class WatchTakeTests: XCTestCase {

    private let take = WatchTake(
        id: UUID(uuidString: "6F1C3C1E-2B7A-4C55-9D0E-0B6B9C2E7A11")!,
        createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
        duration: 12.5
    )

    func test_metadataRoundTrip_keepsEveryField() {
        XCTAssertEqual(WatchWire.take(fromMetadata: WatchWire.metadata(for: take)), take)
    }

    func test_metadata_isPropertyListSafe() {
        // WatchConnectivity carries property-list values only.
        XCTAssertTrue(PropertyListSerialization.propertyList(WatchWire.metadata(for: take), isValidFor: .binary))
    }

    func test_takeFromMissingOrForeignMetadata_isNil() {
        XCTAssertNil(WatchWire.take(fromMetadata: nil))
        XCTAssertNil(WatchWire.take(fromMetadata: ["other": 1]))
        XCTAssertNil(WatchWire.take(fromMetadata: [WatchWire.takeKey: Data("not json".utf8)]))
    }

    func test_newTake_carriesCurrentVersion() {
        XCTAssertEqual(take.version, WatchTake.currentVersion)
    }

    func test_encodeDecode_roundTrips() throws {
        let data = try XCTUnwrap(WatchWire.encode(take))
        XCTAssertEqual(WatchWire.decodeTake(data), take)
    }

    func test_contextRoundTrip_keepsOrderAndMissingTitles() {
        let list = [
            WatchConfirmation(id: UUID(), title: "Lighthouse café"),
            WatchConfirmation(id: UUID(), title: nil),
        ]
        let context = WatchWire.context(for: list)
        XCTAssertTrue(PropertyListSerialization.propertyList(context, isValidFor: .binary))
        XCTAssertEqual(WatchWire.confirmations(fromContext: context), list)
    }

    func test_confirmationsFromEmptyContext_isEmpty() {
        XCTAssertEqual(WatchWire.confirmations(fromContext: [:]), [])
    }

    func test_deepLink_matchesOnlyTheCatchURL() {
        XCTAssertTrue(WatchDeepLink.isCatch(WatchDeepLink.catchURL))
        XCTAssertFalse(WatchDeepLink.isCatch(URL(string: "oryne://capture/whisper")!))
        XCTAssertFalse(WatchDeepLink.isCatch(URL(string: "oryne://watch/other")!))
        XCTAssertFalse(WatchDeepLink.isCatch(URL(string: "https://watch/catch")!))
    }
}
