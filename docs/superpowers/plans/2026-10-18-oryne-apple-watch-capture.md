# Oryne Apple Watch Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A companion Apple Watch app that catches a spoken idea from the wrist and delivers it into the Ocean as an ordinary voice thought, over WatchConnectivity with a CloudKit inbox fallback, imported exactly once on the phone.

**Architecture:** Pure rules (wire format, the watch queue's states, the status line, the phone's import ledger, both file stores) live in `Shared/Watch/`, compiled into the iOS app, the watch app, and `SharedTests`. The watch app (`OryneWatch/`) records, keeps a durable queue, and sends; the phone (`Oryne/Services/`) stages every arrival in an App Group `WatchInbox/` folder and one importer drains it into SwiftData, then runs the same understanding pass in-app capture uses (extracted from `CaptureSession` into `VoiceUnderstanding`).

**Tech Stack:** Swift 5 mode, SwiftUI, SwiftData, AVFoundation, WatchConnectivity, CloudKit (private DB, custom zone), App Intents, WidgetKit, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-18-oryne-apple-watch-capture-design.md` (approved 2026-10-18).

## Global Constraints

- Floors: **watchOS 11.0**, **iOS 18.0** (unchanged).
- Frozen identifiers, never renamed: App Group `group.com.inspireocean.shared`; CloudKit container `iCloud.com.inspireocean.app`; phone `com.inspireocean.app`; watch app `com.inspireocean.app.watchkitapp`; watch widgets `com.inspireocean.app.watchkitapp.widgets`.
- CloudKit inbox: private database, zone **`WatchInbox`**, record type **`WatchTake`**, `recordName = id.uuidString`, fields `createdAt` (Date), `duration` (Double), `version` (Int64), `audio` (CKAsset). Subscription ID `watch-inbox`.
- Audio: AAC `.m4a`, mono, 12 kHz, `AVAudioQuality.medium` (identical to the phone recorder).
- Timings: Undo window **5 s**; minimum take **0.6 s**; cap **5 min**; iCloud fallback delay **120 s**; watch keeps the newest **20** confirmed takes; phone sends the newest **20** confirmations; ledger retention **90 days**.
- The watch target compiles only `OryneWatch/`, `Shared/Watch/`, and `Oryne/DesignSystem/OceanTheme.swift`. Never the rest of `Shared/` (no SwiftData, no `Node`, no `Persistence`).
- UI copy: no em or en dashes in any user-facing string; string catalogs are value-as-key (the English text is the key); every user-facing watch string ships with zh-Hans, flagged `needs_review`, using the glossary (`docs/localization-glossary.md`: Whisper 语音, Thought 灵感, Ocean 海洋).
- Visuals: OceanTheme tokens only; near monochrome and matte; the only circle is a flat control disc; no gloss, rim light, or hairline borders on watch screens.
- PHILOSOPHY: a caught take is never silently lost; every status line says only what is true.
- `SharedTests` compiles `Shared/` directly: test files never `@testable import Oryne`.
- Phase 1 (`feat/watchos-quick-capture`) is **never merged**. Only its asset catalog is copied, with `git checkout feat/watchos-quick-capture -- OryneWatch/Assets.xcassets`.
- Commits: message style `Watch: <summary>`; no attribution lines.
- After adding or removing any source file, run `xcodegen generate` before building. Generated `Info.plist` files are committed (as `Oryne/Info.plist` already is).

### Shell setup (every command in this plan assumes it)

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/oryne-apple-watch-app-177fc5
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PHONE=073A746A-297F-400B-A87E-2D30D0CCADCC   # iPhone 17 simulator, paired with $WATCH
WATCH=527E4569-1EB4-40DE-9F3E-62E2C6B4A46A   # Apple Watch Ultra 3 (49mm) simulator
DD=build/DerivedData
```

Standard commands:

```bash
# Unit tests (one class: append /ClassName to SharedTests)
xcodebuild -project Oryne.xcodeproj -scheme Oryne -destination "platform=iOS Simulator,id=$PHONE" -derivedDataPath $DD test -only-testing:SharedTests 2>&1 | tail -5
# Phone build
xcodebuild -project Oryne.xcodeproj -scheme Oryne -destination "platform=iOS Simulator,id=$PHONE" -derivedDataPath $DD build 2>&1 | tail -3
# Watch build
xcodebuild -project Oryne.xcodeproj -scheme OryneWatch -destination "platform=watchOS Simulator,id=$WATCH" -derivedDataPath $DD build 2>&1 | tail -3
```

### Deviations from the spec (deliberate)

- The watch keeps the **App Group entitlement** (the spec said it needs none). It is the codebase's only reliable signed-build proof (`Persistence` uses the same gate), and CloudKit traps uncatchably without the iCloud entitlement. `WatchInboxSchema.isSignedBuild` checks it.
- Siri phrases stay English only, like the phone's existing App Shortcuts. The shortcut title and description are localized.
- The phone setup row ships with the expected path (Settings on the watch › Action Button › Shortcut › Catch a thought); the hardware checklist item confirms it on a real Ultra.

## File map

| File | Responsibility |
|---|---|
| `Shared/Watch/WatchTake.swift` | `WatchTake`, `WatchConfirmation`, `WatchWire` payload codecs |
| `Shared/Watch/WatchDeepLink.swift` | `oryne://watch/catch` |
| `Shared/Watch/WatchInboxSchema.swift` | CloudKit identifiers, record mapping, signed-build gate |
| `Shared/Watch/TakeQueueState.swift` | Watch queue rules: what to send, upload, keep, delete |
| `Shared/Watch/WatchStatusLine.swift` | The honest status line and last title |
| `Shared/Watch/ImportLedger.swift` | Phone dedupe ledger and its persistence |
| `Shared/Watch/WatchInboxFolder.swift` | Phone staging folder (`WatchInbox/`) |
| `Shared/Watch/TakeQueueStore.swift` | Watch queue on disk (`Takes/`) |
| `SharedTests/Watch*Tests.swift`, `TakeQueue*Tests.swift`, `ImportLedgerTests.swift` | Unit tests for the above |
| `Oryne/Services/VoiceUnderstanding.swift` | Transcribe then understand one node (extracted) |
| `Oryne/Services/CaptureSession.swift` | Calls `VoiceUnderstanding` |
| `Oryne/Services/WatchTakeImporter.swift` | Inbox folder → Node, exactly once |
| `Oryne/Services/WatchBridge.swift` | Phone composition root |
| `Oryne/Services/WatchLink.swift` | Phone WCSession |
| `Oryne/Services/WatchInboxReader.swift` | Phone CloudKit inbox reader |
| `Oryne/App/OryneAppDelegate.swift` | Silent push for the inbox |
| `Oryne/App/OryneApp.swift` | Starts the bridge; refresh at launch and foreground |
| `Oryne/Features/FastCapture/FastCaptureSettingsView.swift` | Apple Watch setup card |
| `OryneWatch/OryneWatchApp.swift` | Watch composition root |
| `OryneWatch/Services/WatchRecorder.swift` | Recording, metering, finalization, cap, interruptions |
| `OryneWatch/Services/TakeQueue.swift` | Observable owner of the persisted queue |
| `OryneWatch/Services/PhoneLink.swift` | Watch WCSession |
| `OryneWatch/Services/CloudInbox.swift` | Watch CloudKit upload |
| `OryneWatch/Services/TakeSync.swift` | Sending policy, retries, background refresh |
| `OryneWatch/Features/Capture/WatchCaptureModel.swift` | Capture state machine |
| `OryneWatch/Features/Capture/WatchCaptureView.swift` | The wrist screens |
| `OryneWatch/Intents/CatchThoughtIntent.swift` | Action Button / Siri intent and App Shortcuts |
| `OryneWatch/Debug/WatchSelfTest.swift` | DEBUG simulator self-tests |
| `OryneWatch/Resources/Localizable.xcstrings`, `InfoPlist.xcstrings` | Watch strings |
| `OryneWatchWidgets/*` | Complication extension |
| `Scripts/xcstrings-add/add.py` | Adds keys to a catalog in Xcode's own format |
| `Scripts/watch-inbox-e2e/run.sh` | Phone import end-to-end on a simulator |
| `Scripts/watch-screens/run.sh` | Screenshots of every wrist screen |
| `project.yml` | `OryneWatch`, `OryneWatchWidgets` targets |
| `docs/HARDWARE_CHECKLIST.md`, `docs/KNOWN_ISSUES.md` | Device checks, status |

---

### Task 1: Shared wire format, deep link, and CloudKit schema

**Files:**
- Create: `Shared/Watch/WatchTake.swift`
- Create: `Shared/Watch/WatchDeepLink.swift`
- Create: `Shared/Watch/WatchInboxSchema.swift`
- Test: `SharedTests/WatchTakeTests.swift`, `SharedTests/WatchInboxSchemaTests.swift`

**Interfaces:**
- Consumes: `Persistence.cloudKitContainerID`, `Persistence.appGroupID` (tests only).
- Produces:
  - `struct WatchTake: Codable, Equatable, Identifiable { var id: UUID; var createdAt: Date; var duration: TimeInterval; var version: Int }`, `static let currentVersion = 1`
  - `struct WatchConfirmation: Codable, Equatable { var id: UUID; var title: String? }`
  - `enum WatchWire`: `takeKey`, `wakeKey`, `recentKey`; `metadata(for:) -> [String: Any]`; `take(fromMetadata:) -> WatchTake?`; `context(for:) -> [String: Any]`; `confirmations(fromContext:) -> [WatchConfirmation]`; `encode(_:) -> Data?`; `decodeTake(_:) -> WatchTake?`
  - `enum WatchDeepLink`: `catchURL: URL`; `isCatch(_ url: URL) -> Bool`
  - `enum WatchInboxSchema`: `containerID`, `appGroupID`, `zoneName`, `recordType`, `subscriptionID`, `Field.{createdAt,duration,version,audio}`, `zoneID`, `recordID(for:)`, `isSignedBuild`, `record(for:audioURL:) -> CKRecord`, `take(from:) -> WatchTake?`, `audioURL(in:) -> URL?`

- [ ] **Step 1: Write the failing tests**

`SharedTests/WatchTakeTests.swift`:

```swift
import XCTest
import Foundation

/// The wire format both ends of WatchConnectivity share. No app-module
/// import: SharedTests compiles Shared/ directly.
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
```

`SharedTests/WatchInboxSchemaTests.swift`:

```swift
import XCTest
import CloudKit

final class WatchInboxSchemaTests: XCTestCase {

    func test_frozenIdentifiers_matchPersistence() {
        XCTAssertEqual(WatchInboxSchema.containerID, Persistence.cloudKitContainerID)
        XCTAssertEqual(WatchInboxSchema.appGroupID, Persistence.appGroupID)
    }

    func test_inboxZone_isNotTheSwiftDataMirrorZone() {
        XCTAssertNotEqual(WatchInboxSchema.zoneName, "com.apple.coredata.cloudkit.zone")
    }

    func test_recordRoundTrip_keepsTakeAndAudio() throws {
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([1, 2, 3]).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }
        let take = WatchTake(id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), duration: 4.25)

        let record = WatchInboxSchema.record(for: take, audioURL: audio)

        XCTAssertEqual(record.recordType, WatchInboxSchema.recordType)
        XCTAssertEqual(record.recordID.recordName, take.id.uuidString)
        XCTAssertEqual(record.recordID.zoneID.zoneName, WatchInboxSchema.zoneName)
        XCTAssertEqual(WatchInboxSchema.take(from: record), take)
        XCTAssertEqual(WatchInboxSchema.audioURL(in: record), audio)
    }

    func test_takeFromForeignRecordType_isNil() {
        let record = CKRecord(recordType: "Something", recordID: WatchInboxSchema.recordID(for: UUID()))
        record[WatchInboxSchema.Field.createdAt] = Date()
        record[WatchInboxSchema.Field.duration] = 1.0
        XCTAssertNil(WatchInboxSchema.take(from: record))
    }

    func test_takeFromRecordWithBadName_isNil() {
        let id = CKRecord.ID(recordName: "not-a-uuid", zoneID: WatchInboxSchema.zoneID)
        let record = CKRecord(recordType: WatchInboxSchema.recordType, recordID: id)
        record[WatchInboxSchema.Field.createdAt] = Date()
        record[WatchInboxSchema.Field.duration] = 1.0
        XCTAssertNil(WatchInboxSchema.take(from: record))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate`, then the unit test command with `-only-testing:SharedTests/WatchTakeTests -only-testing:SharedTests/WatchInboxSchemaTests`.
Expected: build FAILS with `cannot find 'WatchTake' in scope` (and `WatchInboxSchema`, `WatchDeepLink`).

- [ ] **Step 3: Write the implementation**

`Shared/Watch/WatchTake.swift`:

```swift
import Foundation

/// One wrist take on its way from the watch to the Ocean.
///
/// The watch mints `id` when recording starts. It becomes the thought's
/// `Node.id`, the iCloud inbox record's name, and the key every dedupe check
/// uses, whichever path delivers the take.
struct WatchTake: Codable, Equatable, Identifiable {
    static let currentVersion = 1

    var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var version: Int = WatchTake.currentVersion
}

/// The phone's word back to the watch: this take is in the Ocean, with the
/// title it was given once understood (nil until then, or when the recording
/// held no words to name it by).
struct WatchConfirmation: Codable, Equatable {
    var id: UUID
    var title: String?
}

/// WatchConnectivity payload keys and codecs: one definition for both ends.
/// Payloads travel as JSON `Data`, which is property-list safe.
enum WatchWire {
    /// `transferFile` metadata: the encoded `WatchTake`.
    static let takeKey = "take"
    /// `sendMessage` ping that wakes the phone app so a queued file lands now.
    static let wakeKey = "wake"
    /// Application context: the encoded recent `[WatchConfirmation]`.
    static let recentKey = "recent"

    static func encode(_ take: WatchTake) -> Data? {
        try? JSONEncoder().encode(take)
    }

    static func decodeTake(_ data: Data) -> WatchTake? {
        try? JSONDecoder().decode(WatchTake.self, from: data)
    }

    static func metadata(for take: WatchTake) -> [String: Any] {
        guard let data = encode(take) else { return [:] }
        return [takeKey: data]
    }

    static func take(fromMetadata metadata: [String: Any]?) -> WatchTake? {
        guard let data = metadata?[takeKey] as? Data else { return nil }
        return decodeTake(data)
    }

    static func context(for confirmations: [WatchConfirmation]) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(confirmations) else { return [:] }
        return [recentKey: data]
    }

    static func confirmations(fromContext context: [String: Any]) -> [WatchConfirmation] {
        guard let data = context[recentKey] as? Data,
              let list = try? JSONDecoder().decode([WatchConfirmation].self, from: data)
        else { return [] }
        return list
    }
}
```

`Shared/Watch/WatchDeepLink.swift`:

```swift
import Foundation

/// `oryne://watch/catch`: the complication's way into a hot mic. The phone's
/// `AppState.handleDeepLink` ignores the `watch` host.
enum WatchDeepLink {
    static let catchURL = URL(string: "oryne://watch/catch")!

    static func isCatch(_ url: URL) -> Bool {
        url.scheme == "oryne" && url.host == "watch" && url.path == "/catch"
    }
}
```

`Shared/Watch/WatchInboxSchema.swift`:

```swift
import Foundation
import CloudKit

/// The iCloud inbox a wrist take falls back to when the phone is out of
/// reach: a dedicated zone in the user's private database, apart from the
/// zone the SwiftData mirror owns, so the two never touch.
///
/// The watch compiles only `Shared/Watch`, so the frozen identifiers are
/// restated here; `WatchInboxSchemaTests` holds them equal to `Persistence`.
enum WatchInboxSchema {
    static let containerID = "iCloud.com.inspireocean.app"
    static let appGroupID = "group.com.inspireocean.shared"
    static let zoneName = "WatchInbox"
    static let recordType = "WatchTake"
    static let subscriptionID = "watch-inbox"

    enum Field {
        static let createdAt = "createdAt"
        static let duration = "duration"
        static let version = "version"
        static let audio = "audio"
    }

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Whether this process is a signed build carrying the App Group, which
    /// ships together with the iCloud entitlement. CloudKit traps (on a
    /// background queue, uncatchably) without the entitlement, so every
    /// CloudKit path checks this first: the same gate `Persistence` uses.
    static var isSignedBuild: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static func record(for take: WatchTake, audioURL: URL) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(for: take.id))
        record[Field.createdAt] = take.createdAt
        record[Field.duration] = take.duration
        record[Field.version] = Int64(take.version)
        record[Field.audio] = CKAsset(fileURL: audioURL)
        return record
    }

    static func take(from record: CKRecord) -> WatchTake? {
        guard record.recordType == recordType,
              let id = UUID(uuidString: record.recordID.recordName),
              let createdAt = record[Field.createdAt] as? Date,
              let duration = record[Field.duration] as? Double
        else { return nil }
        let version = (record[Field.version] as? Int64).map(Int.init) ?? WatchTake.currentVersion
        return WatchTake(id: id, createdAt: createdAt, duration: duration, version: version)
    }

    static func audioURL(in record: CKRecord) -> URL? {
        (record[Field.audio] as? CKAsset)?.fileURL
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodegen generate`, then the same test command.
Expected: `** TEST SUCCEEDED **`, 13 tests passed.

- [ ] **Step 5: Run the full SharedTests suite**

Run: the unit test command (all of SharedTests).
Expected: `** TEST SUCCEEDED **` (Shared/ also compiles into ShareExtension and OceanWidgets; the phone build inside the test action proves they still link).

- [ ] **Step 6: Commit**

```bash
git add Shared/Watch SharedTests/WatchTakeTests.swift SharedTests/WatchInboxSchemaTests.swift
git commit -m "Watch: shared wire format, deep link, and iCloud inbox schema"
```

---

### Task 2: Watch queue rules and the status line

**Files:**
- Create: `Shared/Watch/TakeQueueState.swift`
- Create: `Shared/Watch/WatchStatusLine.swift`
- Test: `SharedTests/TakeQueueStateTests.swift`, `SharedTests/WatchStatusLineTests.swift`

**Interfaces:**
- Consumes: `WatchTake`, `WatchConfirmation` (Task 1).
- Produces:
  - `enum TakeStatus: String, Codable { case onWatch, inICloud, confirmed }`
  - `enum PhoneTransfer: String, Codable { case notSent, pending, delivered }`
  - `struct QueuedTake: Codable, Equatable, Identifiable { var take; var status; var phoneTransfer; var phoneReachableAtStop: Bool; var title: String?; var id: UUID }`
  - `struct TakeQueueState: Codable, Equatable`: `confirmedKept = 20`, `cloudFallbackDelay = 120`, `takes: [QueuedTake]` (read-only, oldest first), `init(takes:)`, `item(_:)`, `add(_:phoneReachableAtStop:)`, `remove(_:)`, `markPhoneTransfer(_:_:)`, `markInICloud(_:)`, `apply(_:)`, `needingPhoneSend()`, `needingCloudUpload(now:)`, `audioDisposable(_:)`, `prune()`
  - `enum WatchStatusLine: Equatable { case empty, waiting(count: Int), onItsWay, inOcean }`, `derive(from:)`, `lastTitle(from:) -> String?`

- [ ] **Step 1: Write the failing tests**

`SharedTests/TakeQueueStateTests.swift`:

```swift
import XCTest
import Foundation

final class TakeQueueStateTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func take(_ offset: TimeInterval = 0) -> WatchTake {
        WatchTake(id: UUID(), createdAt: t0.addingTimeInterval(offset), duration: 3)
    }

    func test_add_queuesOnWatchAndIgnoresDuplicates() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.add(a, phoneReachableAtStop: false)
        XCTAssertEqual(state.takes.count, 1)
        XCTAssertEqual(state.item(a.id)?.status, .onWatch)
        XCTAssertEqual(state.item(a.id)?.phoneTransfer, .notSent)
        XCTAssertEqual(state.item(a.id)?.phoneReachableAtStop, true)
    }

    func test_remove_dropsTheTake() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.remove(a.id)
        XCTAssertTrue(state.takes.isEmpty)
    }

    func test_needingPhoneSend_onlyOnWatchAndNotHandedOver() {
        var state = TakeQueueState()
        let fresh = take(), handed = take(1), clouded = take(2)
        [fresh, handed, clouded].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markPhoneTransfer(handed.id, .pending)
        state.markInICloud(clouded.id)
        XCTAssertEqual(state.needingPhoneSend().map(\.id), [fresh.id])
    }

    func test_failedTransfer_isSentAgain() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.markPhoneTransfer(a.id, .pending)
        state.markPhoneTransfer(a.id, .notSent)
        XCTAssertEqual(state.needingPhoneSend().map(\.id), [a.id])
    }

    func test_needingCloudUpload_unreachableAtStop_goesAtOnce() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: false)
        XCTAssertEqual(state.needingCloudUpload(now: t0).map(\.id), [a.id])
    }

    func test_needingCloudUpload_reachableAtStop_waitsForTheDelayAfterStop() {
        var state = TakeQueueState()
        let a = take()   // 3 s long: it stopped at t0 + 3
        state.add(a, phoneReachableAtStop: true)
        XCTAssertTrue(state.needingCloudUpload(now: t0.addingTimeInterval(122)).isEmpty)
        XCTAssertEqual(state.needingCloudUpload(now: t0.addingTimeInterval(123)).map(\.id), [a.id])
    }

    func test_needingCloudUpload_longTake_isNotUploadedTheMomentItsCaught() {
        var state = TakeQueueState()
        let long = WatchTake(id: UUID(), createdAt: t0, duration: 300)
        state.add(long, phoneReachableAtStop: true)
        XCTAssertTrue(state.needingCloudUpload(now: t0.addingTimeInterval(310)).isEmpty)
        XCTAssertEqual(state.needingCloudUpload(now: t0.addingTimeInterval(420)).map(\.id), [long.id])
    }

    func test_needingCloudUpload_skipsTakesOffTheWatch() {
        var state = TakeQueueState()
        let a = take(), b = take(1)
        state.add(a, phoneReachableAtStop: false)
        state.add(b, phoneReachableAtStop: false)
        state.markInICloud(a.id)
        state.apply([WatchConfirmation(id: b.id, title: nil)])
        XCTAssertTrue(state.needingCloudUpload(now: t0.addingTimeInterval(999)).isEmpty)
    }

    func test_markInICloud_neverDowngradesConfirmed() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.apply([WatchConfirmation(id: a.id, title: nil)])
        state.markInICloud(a.id)
        XCTAssertEqual(state.item(a.id)?.status, .confirmed)
    }

    func test_apply_confirmsKeepsTitleAndIgnoresUnknown() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.apply([
            WatchConfirmation(id: a.id, title: "Lighthouse café"),
            WatchConfirmation(id: UUID(), title: "Not ours"),
        ])
        state.apply([WatchConfirmation(id: a.id, title: nil)])
        XCTAssertEqual(state.takes.count, 1)
        XCTAssertEqual(state.item(a.id)?.status, .confirmed)
        XCTAssertEqual(state.item(a.id)?.title, "Lighthouse café")
    }

    func test_audioDisposable_followsWhereTheTakeIsSafe() {
        var state = TakeQueueState()
        let onWatch = take(), cloudWhileSending = take(1), cloudDone = take(2), confirmed = take(3)
        [onWatch, cloudWhileSending, cloudDone, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markPhoneTransfer(cloudWhileSending.id, .pending)
        state.markInICloud(cloudWhileSending.id)
        state.markInICloud(cloudDone.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])

        XCTAssertFalse(state.audioDisposable(onWatch.id))
        XCTAssertFalse(state.audioDisposable(cloudWhileSending.id), "a pending transfer still reads the file")
        XCTAssertTrue(state.audioDisposable(cloudDone.id))
        XCTAssertTrue(state.audioDisposable(confirmed.id))
        XCTAssertFalse(state.audioDisposable(UUID()), "a recording the queue can't account for is never deleted")
    }

    func test_prune_keepsNewestConfirmedAndEveryUnconfirmed() {
        var state = TakeQueueState()
        let waiting = take(-100)
        let confirmed = (0..<25).map { take(TimeInterval($0)) }
        state.add(waiting, phoneReachableAtStop: true)
        confirmed.forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply(confirmed.map { WatchConfirmation(id: $0.id, title: nil) })

        XCTAssertEqual(state.takes.filter { $0.status == .confirmed }.count, TakeQueueState.confirmedKept)
        XCTAssertNotNil(state.item(waiting.id))
        XCTAssertNil(state.item(confirmed[0].id))
        XCTAssertNil(state.item(confirmed[4].id))
        XCTAssertNotNil(state.item(confirmed[5].id))
        XCTAssertNotNil(state.item(confirmed[24].id))
    }

    func test_codableRoundTrip() throws {
        var state = TakeQueueState()
        let a = take(), b = take(1)
        state.add(a, phoneReachableAtStop: false)
        state.add(b, phoneReachableAtStop: true)
        state.markPhoneTransfer(b.id, .delivered)
        state.apply([WatchConfirmation(id: b.id, title: "Lighthouse café")])
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(TakeQueueState.self, from: data), state)
    }
}
```

`SharedTests/WatchStatusLineTests.swift`:

```swift
import XCTest
import Foundation

/// Every row of the spec's status table, plus the last-title rule.
final class WatchStatusLineTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func take(_ offset: TimeInterval) -> WatchTake {
        WatchTake(id: UUID(), createdAt: t0.addingTimeInterval(offset), duration: 3)
    }

    func test_nothingEverCaught_hasNoLine() {
        XCTAssertEqual(WatchStatusLine.derive(from: TakeQueueState()), .empty)
    }

    func test_anyTakeOnlyOnTheWatch_countsThoseTakes() {
        var state = TakeQueueState()
        let a = take(0), b = take(1), clouded = take(2), confirmed = take(3)
        [a, b, clouded, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        XCTAssertEqual(WatchStatusLine.derive(from: state), .waiting(count: 2))
    }

    func test_noneOnTheWatch_someInICloud_isOnItsWay() {
        var state = TakeQueueState()
        let clouded = take(0), confirmed = take(1)
        [clouded, confirmed].forEach { state.add($0, phoneReachableAtStop: false) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        XCTAssertEqual(WatchStatusLine.derive(from: state), .onItsWay)
    }

    func test_everythingConfirmed_isInOcean() {
        var state = TakeQueueState()
        let a = take(0)
        state.add(a, phoneReachableAtStop: true)
        state.apply([WatchConfirmation(id: a.id, title: nil)])
        XCTAssertEqual(WatchStatusLine.derive(from: state), .inOcean)
    }

    func test_lastTitle_isTheNewestConfirmedTakesTitle() {
        var state = TakeQueueState()
        let older = take(0), newer = take(10)
        [older, newer].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([
            WatchConfirmation(id: older.id, title: "Old idea"),
            WatchConfirmation(id: newer.id, title: "Lighthouse café"),
        ])
        XCTAssertEqual(WatchStatusLine.lastTitle(from: state), "Lighthouse café")
    }

    func test_lastTitle_isNilWhileTheNewestConfirmedIsUnnamed() {
        var state = TakeQueueState()
        let older = take(0), newer = take(10)
        [older, newer].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([
            WatchConfirmation(id: older.id, title: "Old idea"),
            WatchConfirmation(id: newer.id, title: nil),
        ])
        XCTAssertNil(WatchStatusLine.lastTitle(from: state), "an older title would describe the wrong thought")
    }

    func test_lastTitle_ignoresUnconfirmedTakes() {
        var state = TakeQueueState()
        let named = take(0), waiting = take(10)
        [named, waiting].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([WatchConfirmation(id: named.id, title: "Lighthouse café")])
        XCTAssertEqual(WatchStatusLine.lastTitle(from: state), "Lighthouse café")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate`, then the unit test command with `-only-testing:SharedTests/TakeQueueStateTests -only-testing:SharedTests/WatchStatusLineTests`.
Expected: build FAILS with `cannot find 'TakeQueueState' in scope`.

- [ ] **Step 3: Write the implementation**

`Shared/Watch/TakeQueueState.swift`:

```swift
import Foundation

/// Where a wrist take stands on its way to the Ocean.
enum TakeStatus: String, Codable {
    /// Exists only on the watch.
    case onWatch
    /// Safe in the iCloud inbox; the phone hasn't confirmed it yet.
    case inICloud
    /// The phone says it's in the Ocean.
    case confirmed
}

/// The WatchConnectivity handoff for one take.
enum PhoneTransfer: String, Codable {
    /// Not handed to WatchConnectivity (never, or a failed attempt).
    case notSent
    /// Queued with the system, which still reads the file.
    case pending
    /// The system reports the file reached the phone.
    case delivered
}

struct QueuedTake: Codable, Equatable, Identifiable {
    var take: WatchTake
    var status: TakeStatus = .onWatch
    var phoneTransfer: PhoneTransfer = .notSent
    /// Whether the phone was reachable when the take was caught. A take
    /// caught out of reach goes to the iCloud inbox at once.
    var phoneReachableAtStop: Bool
    var title: String? = nil

    var id: UUID { take.id }
}

/// The watch's queue of takes as pure state. Every rule about what to send,
/// what to keep, and what is safe to delete lives here so it can be tested
/// without a watch; `TakeQueue` on the watch persists it and acts on it.
struct TakeQueueState: Codable, Equatable {
    /// Confirmed takes kept for the status line and the last title.
    static let confirmedKept = 20
    /// How long a take may wait for the phone before also going to iCloud.
    static let cloudFallbackDelay: TimeInterval = 120

    /// Oldest first.
    private(set) var takes: [QueuedTake]

    init(takes: [QueuedTake] = []) {
        self.takes = takes
    }

    func item(_ id: UUID) -> QueuedTake? {
        takes.first { $0.id == id }
    }

    mutating func add(_ take: WatchTake, phoneReachableAtStop: Bool) {
        guard item(take.id) == nil else { return }
        takes.append(QueuedTake(take: take, phoneReachableAtStop: phoneReachableAtStop))
    }

    /// Undo: gone from the queue as if never caught.
    mutating func remove(_ id: UUID) {
        takes.removeAll { $0.id == id }
    }

    mutating func markPhoneTransfer(_ id: UUID, _ transfer: PhoneTransfer) {
        update(id) { $0.phoneTransfer = transfer }
    }

    /// Only a take that exists solely on the watch moves to iCloud; a
    /// confirmed take stays confirmed.
    mutating func markInICloud(_ id: UUID) {
        update(id) { if $0.status == .onWatch { $0.status = .inICloud } }
    }

    /// Applies the phone's recent list. Unknown IDs are ignored; a missing
    /// title never erases one the watch already has.
    mutating func apply(_ confirmations: [WatchConfirmation]) {
        for confirmation in confirmations {
            update(confirmation.id) {
                $0.status = .confirmed
                if let title = confirmation.title { $0.title = title }
            }
        }
        prune()
    }

    /// Takes to hand to WatchConnectivity: only on the watch and not yet
    /// handed over. (A take in iCloud reaches the phone from there.)
    func needingPhoneSend() -> [QueuedTake] {
        takes.filter { $0.status == .onWatch && $0.phoneTransfer == .notSent }
    }

    /// Takes to upload to the iCloud inbox: still only on the watch, and
    /// either caught out of the phone's reach or waiting too long. The wait
    /// is timed from when the take ended (`createdAt` is when recording
    /// began), so a long take isn't uploaded the moment it's caught.
    func needingCloudUpload(now: Date) -> [QueuedTake] {
        takes.filter {
            let stoppedAt = $0.take.createdAt.addingTimeInterval($0.take.duration)
            return $0.status == .onWatch
                && (!$0.phoneReachableAtStop
                    || now.timeIntervalSince(stoppedAt) >= Self.cloudFallbackDelay)
        }
    }

    /// Whether the watch may delete this take's audio: it's confirmed, or
    /// it's in iCloud with no WatchConnectivity transfer still reading the
    /// file. A recording the queue can't account for (an unreadable index,
    /// a crash mid-recording) is never deleted: guessing wrong loses a
    /// caught take. Undo deletes its own file.
    func audioDisposable(_ id: UUID) -> Bool {
        guard let item = item(id) else { return false }
        switch item.status {
        case .onWatch: return false
        case .inICloud: return item.phoneTransfer != .pending
        case .confirmed: return true
        }
    }

    /// Keeps every unconfirmed take and the newest `confirmedKept` confirmed.
    mutating func prune() {
        let confirmed = takes.filter { $0.status == .confirmed }
        guard confirmed.count > Self.confirmedKept else { return }
        let keep = Set(
            confirmed
                .sorted { $0.take.createdAt > $1.take.createdAt }
                .prefix(Self.confirmedKept)
                .map(\.id)
        )
        takes.removeAll { $0.status == .confirmed && !keep.contains($0.id) }
    }

    private mutating func update(_ id: UUID, _ change: (inout QueuedTake) -> Void) {
        guard let index = takes.firstIndex(where: { $0.id == id }) else { return }
        change(&takes[index])
    }
}
```

`Shared/Watch/WatchStatusLine.swift`:

```swift
import Foundation

/// The one status line under the record disc, derived from the queue so it
/// can never claim more than is true (PHILOSOPHY §3: nothing untrue, by words
/// or by omission). The watch view turns each case into localized words.
enum WatchStatusLine: Equatable {
    /// Nothing ever caught: no line at all.
    case empty
    /// Takes that exist only on the watch.
    case waiting(count: Int)
    /// Nothing is only on the watch, but not everything is confirmed.
    case onItsWay
    /// The phone has confirmed every take.
    case inOcean

    static func derive(from state: TakeQueueState) -> WatchStatusLine {
        let onWatch = state.takes.filter { $0.status == .onWatch }.count
        if onWatch > 0 { return .waiting(count: onWatch) }
        if state.takes.contains(where: { $0.status == .inICloud }) { return .onItsWay }
        if state.takes.contains(where: { $0.status == .confirmed }) { return .inOcean }
        return .empty
    }

    /// The title of the newest confirmed take, once the phone has named it.
    /// Nil while that take is unnamed: an older title would describe the
    /// wrong thought.
    static func lastTitle(from state: TakeQueueState) -> String? {
        state.takes
            .filter { $0.status == .confirmed }
            .max { $0.take.createdAt < $1.take.createdAt }?
            .title
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodegen generate`, then the same test command.
Expected: `** TEST SUCCEEDED **`, 20 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Shared/Watch/TakeQueueState.swift Shared/Watch/WatchStatusLine.swift SharedTests/TakeQueueStateTests.swift SharedTests/WatchStatusLineTests.swift
git commit -m "Watch: queue rules and the honest status line"
```

---

### Task 3: The phone's import ledger

**Files:**
- Create: `Shared/Watch/ImportLedger.swift`
- Test: `SharedTests/ImportLedgerTests.swift`

**Interfaces:**
- Consumes: `WatchConfirmation` (Task 1).
- Produces: `struct ImportLedger: Codable, Equatable` with `enum State { imported, understood }`, `struct Entry { state; importedAt: Date; title: String? }`, `entries: [UUID: Entry]` (read-only), `retention`, `confirmationLimit`, `defaultsKey = "watch.importLedger"`, `hasSeen(_:)`, `markImported(_:at:)`, `markUnderstood(_:title:)`, `awaitingUnderstanding: [UUID]`, `recentConfirmations() -> [WatchConfirmation]`, `prune(now:)`, `static load(from: UserDefaults)`, `save(to: UserDefaults)`.

- [ ] **Step 1: Write the failing tests**

`SharedTests/ImportLedgerTests.swift`:

```swift
import XCTest
import Foundation

/// The ledger is the phone's only "seen before" check, whichever path
/// delivered a take (spec §2, import exactly once).
final class ImportLedgerTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func test_newTake_isUnseenUntilImported() {
        var ledger = ImportLedger()
        let id = UUID()
        XCTAssertFalse(ledger.hasSeen(id))
        ledger.markImported(id, at: t0)
        XCTAssertTrue(ledger.hasSeen(id))
    }

    func test_secondCopy_fromEitherPath_isSeenAndKeepsTheFirstImport() {
        // WatchConnectivity first or iCloud first: only the ID matters.
        var ledger = ImportLedger()
        let id = UUID()
        ledger.markImported(id, at: t0)
        ledger.markImported(id, at: t0.addingTimeInterval(60))
        XCTAssertTrue(ledger.hasSeen(id))
        XCTAssertEqual(ledger.entries[id]?.importedAt, t0)
        XCTAssertEqual(ledger.entries.count, 1)
    }

    func test_deletedThought_lateCopy_staysSeen() {
        // The ledger never asks the store, so deleting the thought leaves
        // its entry, and a late copy over the other path is still refused.
        var ledger = ImportLedger()
        let id = UUID()
        ledger.markImported(id, at: t0)
        ledger.markUnderstood(id, title: "Lighthouse café")
        ledger.prune(now: t0.addingTimeInterval(89 * day))
        XCTAssertTrue(ledger.hasSeen(id))
    }

    func test_awaitingUnderstanding_isOldestFirstAndExcludesUnderstood() {
        var ledger = ImportLedger()
        let a = UUID(), b = UUID(), c = UUID()
        ledger.markImported(b, at: t0.addingTimeInterval(10))
        ledger.markImported(a, at: t0)
        ledger.markImported(c, at: t0.addingTimeInterval(20))
        ledger.markUnderstood(c, title: nil)
        XCTAssertEqual(ledger.awaitingUnderstanding, [a, b])
    }

    func test_markUnderstood_unknownID_isIgnored() {
        var ledger = ImportLedger()
        ledger.markUnderstood(UUID(), title: "Stray")
        XCTAssertTrue(ledger.entries.isEmpty)
    }

    func test_recentConfirmations_newestFirstCappedWithTitles() {
        var ledger = ImportLedger()
        let ids = (0..<25).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            ledger.markImported(id, at: t0.addingTimeInterval(Double(i)))
        }
        ledger.markUnderstood(ids[24], title: "Newest")

        let recent = ledger.recentConfirmations()

        XCTAssertEqual(recent.count, ImportLedger.confirmationLimit)
        XCTAssertEqual(recent.first, WatchConfirmation(id: ids[24], title: "Newest"))
        XCTAssertEqual(recent.last?.id, ids[5])
        XCTAssertNil(recent[1].title)
    }

    func test_prune_dropsOldSettledKeepsOldPendingAndRecent() {
        var ledger = ImportLedger()
        let old = UUID(), oldPending = UUID(), recent = UUID()
        ledger.markImported(old, at: t0)
        ledger.markUnderstood(old, title: nil)
        ledger.markImported(oldPending, at: t0)
        ledger.markImported(recent, at: t0.addingTimeInterval(80 * day))
        ledger.markUnderstood(recent, title: nil)

        ledger.prune(now: t0.addingTimeInterval(91 * day))

        XCTAssertFalse(ledger.hasSeen(old))
        XCTAssertTrue(ledger.hasSeen(oldPending), "a take still awaiting understanding is never forgotten")
        XCTAssertTrue(ledger.hasSeen(recent))
    }

    func test_saveThenLoad_roundTrips() throws {
        let suite = "ImportLedgerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var ledger = ImportLedger()
        let id = UUID()
        ledger.markImported(id, at: t0)
        ledger.markUnderstood(id, title: "Lighthouse café")

        ledger.save(to: defaults)

        XCTAssertEqual(ImportLedger.load(from: defaults), ledger)
    }

    func test_load_withNothingOrGarbage_isEmpty() throws {
        let suite = "ImportLedgerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ImportLedger.load(from: defaults), ImportLedger())
        defaults.set(Data("nope".utf8), forKey: ImportLedger.defaultsKey)
        XCTAssertEqual(ImportLedger.load(from: defaults), ImportLedger())
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate`, then the unit test command with `-only-testing:SharedTests/ImportLedgerTests`.
Expected: build FAILS with `cannot find 'ImportLedger' in scope`.

- [ ] **Step 3: Write the implementation**

`Shared/Watch/ImportLedger.swift`:

```swift
import Foundation

/// The phone's record of every wrist take it has imported: the one source of
/// truth for "seen before", whichever path delivered the take. Asking the
/// store whether a Node with the ID exists is not enough: a thought the user
/// deleted must not come back when a late copy arrives over the other path.
///
/// Phone-local (App Group defaults), never synced: it is bookkeeping, not
/// the user's water.
struct ImportLedger: Codable, Equatable {
    enum State: String, Codable {
        /// In the store as a voice thought; understanding hasn't finished.
        case imported
        /// The understanding pass ran. The title may still be nil when the
        /// recording held no words.
        case understood
    }

    struct Entry: Codable, Equatable {
        var state: State
        var importedAt: Date
        var title: String?
    }

    static let retention: TimeInterval = 90 * 24 * 60 * 60
    static let confirmationLimit = 20
    static let defaultsKey = "watch.importLedger"

    private(set) var entries: [UUID: Entry] = [:]

    func hasSeen(_ id: UUID) -> Bool {
        entries[id] != nil
    }

    mutating func markImported(_ id: UUID, at date: Date) {
        guard entries[id] == nil else { return }
        entries[id] = Entry(state: .imported, importedAt: date, title: nil)
    }

    mutating func markUnderstood(_ id: UUID, title: String?) {
        guard entries[id] != nil else { return }
        entries[id]?.state = .understood
        entries[id]?.title = title
    }

    /// Imported takes still waiting for understanding, oldest first.
    var awaitingUnderstanding: [UUID] {
        entries
            .filter { $0.value.state == .imported }
            .sorted { $0.value.importedAt < $1.value.importedAt }
            .map(\.key)
    }

    /// What the watch is told: the newest imports, newest first.
    func recentConfirmations() -> [WatchConfirmation] {
        entries
            .sorted { $0.value.importedAt > $1.value.importedAt }
            .prefix(Self.confirmationLimit)
            .map { WatchConfirmation(id: $0.key, title: $0.value.title) }
    }

    /// Forgets settled entries older than the retention window. An entry
    /// still awaiting understanding is kept however old it is.
    mutating func prune(now: Date) {
        entries = entries.filter {
            $0.value.state == .imported || now.timeIntervalSince($0.value.importedAt) < Self.retention
        }
    }

    static func load(from defaults: UserDefaults) -> ImportLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let ledger = try? JSONDecoder().decode(ImportLedger.self, from: data)
        else { return ImportLedger() }
        return ledger
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodegen generate`, then the same test command.
Expected: `** TEST SUCCEEDED **`, 9 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Shared/Watch/ImportLedger.swift SharedTests/ImportLedgerTests.swift
git commit -m "Watch: the phone's import ledger, so a take lands exactly once"
```

---

### Task 4: File stores for both ends

> **Amended after review (Malik, 2026-10-18):** `WatchInboxFolder` writes a second delivery beside the first and swaps it in (a failed redelivery never removes a good copy); `TakeQueueStore.load()` sets an unreadable index aside instead of letting the next save overwrite it, and `TakeQueueStore.unlistedTakes(in:duration:)` returns playable recordings the index doesn't list so `TakeQueue` (Task 10) can queue them again at launch. Shipped in the Task 4 fix commit; the code below is the original task text.

**Files:**
- Create: `Shared/Watch/WatchInboxFolder.swift`
- Create: `Shared/Watch/TakeQueueStore.swift`
- Test: `SharedTests/WatchInboxFolderTests.swift`, `SharedTests/TakeQueueStoreTests.swift`

**Interfaces:**
- Consumes: `WatchTake`, `WatchWire.encode/decodeTake`, `WatchInboxSchema.appGroupID` (Task 1); `TakeQueueState` (Task 2).
- Produces:
  - `struct WatchInboxFolder`: `init(directory:)`, `static var standard`, `directory`, `audioURL(for:)`, `metadataURL(for:)`, `accept(_:movingAudioFrom:) throws`, `accept(_:copyingAudioFrom:) throws`, `pending() -> [WatchTake]` (oldest first), `remove(_:)`
  - `struct TakeQueueStore`: `init(directory:)`, `static var standard`, `indexURL`, `audioURL(for:)`, `load() -> TakeQueueState`, `save(_:)`, `sweep(_:)`, `deleteAudio(_:)`
- Decision (Malik, 2026-10-18): a recording the index doesn't list is never deleted by a sweep (`TakeQueueState.audioDisposable` returns false for unknown IDs), so an unreadable index can't cost a waiting take. Callers delete such files explicitly (Undo, a discarded recording).

- [ ] **Step 1: Write the failing tests**

`SharedTests/WatchInboxFolderTests.swift`:

```swift
import XCTest
import Foundation

final class WatchInboxFolderTests: XCTestCase {

    private var root: URL!
    private var folder: WatchInboxFolder!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchInboxFolderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        folder = WatchInboxFolder(directory: root.appendingPathComponent("WatchInbox", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func take(_ offset: TimeInterval = 0) -> WatchTake {
        WatchTake(id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + offset), duration: 2)
    }

    private func sourceFile(_ bytes: [UInt8]) throws -> URL {
        let url = root.appendingPathComponent("source-\(UUID().uuidString).m4a")
        try Data(bytes).write(to: url)
        return url
    }

    func test_acceptMoving_takesTheFileAndListsTheTake() throws {
        let t = take()
        let source = try sourceFile([1, 2, 3])
        try folder.accept(t, movingAudioFrom: source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(folder.pending(), [t])
        XCTAssertEqual(try Data(contentsOf: folder.audioURL(for: t.id)), Data([1, 2, 3]))
    }

    func test_acceptCopying_leavesTheSource() throws {
        let t = take()
        let source = try sourceFile([4, 5])
        try folder.accept(t, copyingAudioFrom: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(folder.pending(), [t])
    }

    func test_pending_needsBothFiles() throws {
        let audioOnly = take(), metadataOnly = take(1)
        try Data([1]).write(to: folder.audioURL(for: audioOnly.id))
        try XCTUnwrap(WatchWire.encode(metadataOnly)).write(to: folder.metadataURL(for: metadataOnly.id))
        XCTAssertEqual(folder.pending(), [])
    }

    func test_pending_isOldestFirst() throws {
        let older = take(0), newer = take(10)
        try folder.accept(newer, movingAudioFrom: try sourceFile([1]))
        try folder.accept(older, movingAudioFrom: try sourceFile([2]))
        XCTAssertEqual(folder.pending(), [older, newer])
    }

    func test_secondDelivery_replacesTheFirstCopy() throws {
        let t = take()
        try folder.accept(t, movingAudioFrom: try sourceFile([1]))
        try folder.accept(t, copyingAudioFrom: try sourceFile([9, 9]))
        XCTAssertEqual(folder.pending(), [t])
        XCTAssertEqual(try Data(contentsOf: folder.audioURL(for: t.id)), Data([9, 9]))
    }

    func test_remove_deletesBothFiles() throws {
        let t = take()
        try folder.accept(t, movingAudioFrom: try sourceFile([1]))
        folder.remove(t.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.audioURL(for: t.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.metadataURL(for: t.id).path))
        XCTAssertEqual(folder.pending(), [])
    }

    func test_unreadableMetadata_isIgnored() throws {
        let id = UUID()
        try Data([1]).write(to: folder.audioURL(for: id))
        try Data("nope".utf8).write(to: folder.metadataURL(for: id))
        XCTAssertEqual(folder.pending(), [])
    }
}
```

`SharedTests/TakeQueueStoreTests.swift`:

```swift
import XCTest
import Foundation

final class TakeQueueStoreTests: XCTestCase {

    private var directory: URL!
    private var store: TakeQueueStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TakeQueueStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = TakeQueueStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func take(_ offset: TimeInterval = 0) -> WatchTake {
        WatchTake(id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + offset), duration: 2)
    }

    private func writeAudio(_ id: UUID) throws {
        try Data([1]).write(to: store.audioURL(for: id))
    }

    private func audioExists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: store.audioURL(for: id).path)
    }

    func test_loadFromAnEmptyFolder_isEmpty() {
        XCTAssertEqual(store.load(), TakeQueueState())
    }

    func test_saveThenLoad_roundTrips() {
        var state = TakeQueueState()
        state.add(take(), phoneReachableAtStop: false)
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func test_garbageIndex_loadsEmpty() throws {
        try Data("nope".utf8).write(to: store.indexURL)
        XCTAssertEqual(store.load(), TakeQueueState())
    }

    func test_sweep_deletesOnlyAudioSafeElsewhere() throws {
        var state = TakeQueueState()
        let waiting = take(), clouded = take(1), confirmed = take(2)
        let unlisted = UUID()
        [waiting, clouded, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        for id in [waiting.id, clouded.id, confirmed.id, unlisted] { try writeAudio(id) }

        store.sweep(state)

        XCTAssertTrue(audioExists(waiting.id))
        XCTAssertFalse(audioExists(clouded.id))
        XCTAssertFalse(audioExists(confirmed.id))
        XCTAssertTrue(audioExists(unlisted), "a recording the index doesn't list is never guessed away")
    }

    func test_unreadableIndex_neverCostsAWaitingTake() throws {
        let waiting = take()
        var state = TakeQueueState()
        state.add(waiting, phoneReachableAtStop: true)
        store.save(state)
        try writeAudio(waiting.id)
        try Data("corrupt".utf8).write(to: store.indexURL)

        store.sweep(store.load())

        XCTAssertTrue(audioExists(waiting.id))
    }

    func test_deleteAudio_removesTheFile() throws {
        let id = UUID()
        try writeAudio(id)
        store.deleteAudio(id)
        XCTAssertFalse(audioExists(id))
    }

    func test_sweep_neverTouchesTheIndex() {
        let state = TakeQueueState()
        store.save(state)
        store.sweep(state)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.indexURL.path))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate`, then the unit test command with `-only-testing:SharedTests/WatchInboxFolderTests -only-testing:SharedTests/TakeQueueStoreTests`.
Expected: build FAILS with `cannot find 'WatchInboxFolder' in scope`.

- [ ] **Step 3: Write the implementation**

`Shared/Watch/WatchInboxFolder.swift`:

```swift
import Foundation

/// The phone's staging folder for wrist takes: `<id>.m4a` beside `<id>.json`
/// (the encoded `WatchTake`). Both delivery paths write here first and the
/// importer drains it, so a take survives a crash or a refused save between
/// arrival and import. The metadata is written last: a take is listed only
/// once its audio is in place.
struct WatchInboxFolder {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `WatchInbox/` in the App Group container, or app-local storage on a
    /// build without the App Group (mirroring `Persistence`).
    static var standard: WatchInboxFolder {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchInboxSchema.appGroupID)
            ?? URL.applicationSupportDirectory
        return WatchInboxFolder(directory: base.appendingPathComponent("WatchInbox", isDirectory: true))
    }

    func audioURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func metadataURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Takes ownership of a WatchConnectivity file. Synchronous on purpose:
    /// the system deletes the delivered file as soon as the delegate returns.
    func accept(_ take: WatchTake, movingAudioFrom source: URL) throws {
        try place(take) { try FileManager.default.moveItem(at: source, to: $0) }
    }

    /// Copies a CloudKit asset, whose file CloudKit owns and may remove.
    func accept(_ take: WatchTake, copyingAudioFrom source: URL) throws {
        try place(take) { try FileManager.default.copyItem(at: source, to: $0) }
    }

    /// Complete takes waiting for import, oldest first.
    func pending() -> [WatchTake] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap(WatchWire.decodeTake) }
            .filter { FileManager.default.fileExists(atPath: audioURL(for: $0.id).path) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: metadataURL(for: id))
        try? FileManager.default.removeItem(at: audioURL(for: id))
    }

    private func place(_ take: WatchTake, audio write: (URL) throws -> Void) throws {
        // A second delivery of the same take replaces the first copy.
        remove(take.id)
        try write(audioURL(for: take.id))
        guard let data = WatchWire.encode(take) else { throw CocoaError(.coderInvalidValue) }
        try data.write(to: metadataURL(for: take.id), options: .atomic)
    }
}
```

`Shared/Watch/TakeQueueStore.swift`:

```swift
import Foundation

/// The watch's on-disk queue: `queue.json` (the encoded `TakeQueueState`)
/// and one `<id>.m4a` per take, in the watch app's own Application Support.
/// Watch and phone never share a container; the phone gets takes only
/// through WatchConnectivity or the iCloud inbox.
struct TakeQueueStore {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var standard: TakeQueueStore {
        TakeQueueStore(directory: URL.applicationSupportDirectory.appendingPathComponent("Takes", isDirectory: true))
    }

    var indexURL: URL {
        directory.appendingPathComponent("queue.json")
    }

    func audioURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func load() -> TakeQueueState {
        guard let data = try? Data(contentsOf: indexURL),
              let state = try? JSONDecoder().decode(TakeQueueState.self, from: data)
        else { return TakeQueueState() }
        return state
    }

    func save(_ state: TakeQueueState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Deletes audio the state says is safe elsewhere. A recording the index
    /// doesn't list (one being recorded, an unreadable index, a crash
    /// mid-recording) is kept: `audioDisposable` never guesses about it.
    func sweep(_ state: TakeQueueState) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "m4a" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  state.audioDisposable(id)
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func deleteAudio(_ id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(for: id))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodegen generate`, then the same test command.
Expected: `** TEST SUCCEEDED **`, 14 tests passed.

- [ ] **Step 5: Commit**

```bash
git add Shared/Watch/WatchInboxFolder.swift Shared/Watch/TakeQueueStore.swift SharedTests/WatchInboxFolderTests.swift SharedTests/TakeQueueStoreTests.swift
git commit -m "Watch: staging folder on the phone, durable queue on the wrist"
```

---

### Task 5: Extract `VoiceUnderstanding` from `CaptureSession`

A pure refactor: in-app capture must behave exactly as before. The importer (Task 6) is the second caller.

**Files:**
- Create: `Oryne/Services/VoiceUnderstanding.swift`
- Modify: `Oryne/Services/CaptureSession.swift:177-230` (replace `beginUnderstanding`, delete `transcribeThenUnderstand` and `understand`)

**Interfaces:**
- Consumes: `OceanAIService.transcribe(audioURL:)`, `.understand(_:) -> ThoughtUnderstanding` (with `.essence: String`), `NodeComposer.applyUnderstanding(_:to:)`, `Node.meaningText`, `Node.transcriptEditedByUser`.
- Produces: `@MainActor enum VoiceUnderstanding { @discardableResult static func run(nodeID: UUID, audioTempURL: URL?, context: ModelContext, ai: any OceanAIService) async -> String? }` returning the essence, or nil when there were no words or the node is gone.

- [ ] **Step 1: Confirm the name is free and the baseline is green**

Run: `grep -rn "VoiceUnderstanding" Oryne Shared OryneWatch 2>/dev/null` → no output.
Run: the full unit test command → `** TEST SUCCEEDED **`.

- [ ] **Step 2: Create `Oryne/Services/VoiceUnderstanding.swift`**

```swift
import Foundation
import SwiftData

/// The understanding pass for one saved thought: a voice thought with no
/// transcript is transcribed first (from the temp file when it survives,
/// else from the stored bytes), then title and themes come from the words
/// the user kept. Shared by in-app capture (`CaptureSession`) and wrist
/// takes (`WatchTakeImporter`) so the two can never drift.
///
/// Ownership: a transcript the user edited is never overwritten, and every
/// interpretation goes through `NodeComposer.applyUnderstanding`.
/// Cancellation is honored between steps (Undo cancels the capture's task).
@MainActor
enum VoiceUnderstanding {

    /// Returns the essence (the interpreted title), or nil when there were no
    /// words to understand, the user owns the transcript, or the node is gone.
    @discardableResult
    static func run(
        nodeID: UUID,
        audioTempURL: URL?,
        context: ModelContext,
        ai: any OceanAIService
    ) async -> String? {
        guard let node = fetch(nodeID, in: context) else { return nil }
        if node.kind == .voice, (node.transcription ?? "").isEmpty {
            guard await transcribe(nodeID: nodeID, tempURL: audioTempURL, context: context, ai: ai) else {
                return nil
            }
        } else if let audioTempURL {
            // A confirmed transcript wins — the temp file has no further use.
            try? FileManager.default.removeItem(at: audioTempURL)
        }
        return await understand(nodeID: nodeID, context: context, ai: ai)
    }

    /// True when a transcript landed on the node.
    private static func transcribe(
        nodeID: UUID,
        tempURL: URL?,
        context: ModelContext,
        ai: any OceanAIService
    ) async -> Bool {
        // The recognizer wants a file URL; recreate one from the stored bytes
        // when the temp didn't survive (a restored draft, re-released, or a
        // wrist take whose audio lives only in the store).
        let url: URL
        if let tempURL, FileManager.default.fileExists(atPath: tempURL.path) {
            url = tempURL
        } else if let data = fetch(nodeID, in: context)?.audioData {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("transcribe-\(UUID().uuidString).m4a")
            guard (try? data.write(to: url)) != nil else { return false }
        } else {
            return false
        }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let transcript = await ai.transcribe(audioURL: url), !transcript.isEmpty else { return false }
        guard !Task.isCancelled, let node = fetch(nodeID, in: context) else { return false }
        // Ownership: never overwrite words the user has touched.
        guard !node.transcriptEditedByUser else { return false }
        node.transcription = transcript
        node.updatedAt = .now
        try? context.save()
        return true
    }

    private static func understand(nodeID: UUID, context: ModelContext, ai: any OceanAIService) async -> String? {
        guard let node = fetch(nodeID, in: context) else { return nil }
        let basis = node.meaningText
        guard !basis.isEmpty else { return nil }
        let understanding = await ai.understand(basis)
        guard !Task.isCancelled, let fresh = fetch(nodeID, in: context) else { return nil }
        NodeComposer.applyUnderstanding(understanding, to: fresh)
        try? context.save()
        return understanding.essence
    }

    private static func fetch(_ id: UUID, in context: ModelContext) -> Node? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
```

- [ ] **Step 3: Replace the understanding section of `CaptureSession.swift`**

Replace everything from `    // MARK: Understanding` through the closing brace of `private func understand(nodeID:ai:)` (currently lines 175 to 230, just above `    // MARK: Undo`) with:

```swift
    // MARK: Understanding

    /// Title + themes derived from the words the user kept. Voice thoughts
    /// with no transcript go through the post-hoc recognizer first; words the
    /// user has touched are never overwritten (ownership contract). The pass
    /// itself lives in `VoiceUnderstanding`, shared with wrist takes.
    func beginUnderstanding(nodeID: UUID) {
        guard let ai, let context else { return }
        let tempURL = lastReleased?.nodeID == nodeID ? lastReleased?.draft.audioTempURL : nil
        understandingTask?.cancel()
        understandingTask = Task { [weak self] in
            guard let essence = await VoiceUnderstanding.run(
                nodeID: nodeID, audioTempURL: tempURL, context: context, ai: ai
            ) else { return }
            self?.onUnderstood?(nodeID, essence)
        }
    }

```

Keep `private func fetch(_:)` at the bottom of the class: `applyReviewEdits` and `undoLastRelease` still use it.

- [ ] **Step 4: Verify nothing else called the removed functions, then build and test**

Run: `grep -n "transcribeThenUnderstand\|func understand(nodeID" Oryne/Services/CaptureSession.swift` → no output.
Run: `xcodegen generate`, the phone build → `** BUILD SUCCEEDED **`.
Run: the full unit test command → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Oryne/Services/VoiceUnderstanding.swift Oryne/Services/CaptureSession.swift
git commit -m "Watch: lift the understanding pass out of CaptureSession for reuse"
```

---

### Task 6: Phone importer, bridge, and the launch sweep

**Files:**
- Create: `Oryne/Services/WatchTakeImporter.swift`
- Create: `Oryne/Services/WatchBridge.swift`
- Modify: `Oryne/App/OryneApp.swift` (start the bridge in `init`; refresh at launch and on foreground)
- Create: `Scripts/watch-inbox-e2e/run.sh` (the test for this task)

**Interfaces:**
- Consumes: `WatchInboxFolder`, `WatchTake` (Tasks 1, 4); `ImportLedger` (Task 3); `VoiceUnderstanding.run` (Task 5); `NodeComposer.make(kind:audioData:detectThemes:)`; `FastCapturePreferences.defaults`; `String.trimmed` (internal extension in `CaptureView.swift`).
- Produces:
  - `@MainActor final class WatchTakeImporter`: `init(context:ai:folder:defaults:)`, `drain() async`, `recentConfirmations: [WatchConfirmation]`, `confirmationsChanged: (([WatchConfirmation]) -> Void)?`, `didSettle: ((UUID) -> Void)?`
  - `@MainActor final class WatchBridge`: `static let shared`, `start(context:ai:)`, `drain() async`, `refresh() async`

- [ ] **Step 1: Write the end-to-end script (the failing test)**

`Scripts/watch-inbox-e2e/run.sh`:

```bash
#!/usr/bin/env bash
# End-to-end check of the phone's wrist-take import on a simulator. Drops a
# synthetic take (spoken by `say`) into the App Group WatchInbox folder the
# way WatchConnectivity or the iCloud inbox would, launches Oryne, and checks
# that exactly one voice thought with the take's ID lands in the store. Then
# drops the same take again and checks it is not imported twice.
#
# Usage: Scripts/watch-inbox-e2e/run.sh <iphone-sim-udid> [path/to/Oryne.app]
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
UDID=${1:?iPhone simulator UDID}
APP=${2:-build/DerivedData/Build/Products/Debug-iphonesimulator/Oryne.app}
BUNDLE=com.inspireocean.app
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
GROUP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" groups | awk '/group.com.inspireocean.shared/ {print $2}')
[ -n "$GROUP" ] || { echo "FAIL: no App Group container for $BUNDLE"; exit 1; }
INBOX="$GROUP/WatchInbox"
STORE="$GROUP/InspireOcean.store"
mkdir -p "$INBOX"

say -o "$WORK/take.aiff" "A lighthouse cafe with a reading room upstairs"
afconvert -f m4af -d aac -c 1 "$WORK/take.aiff" "$WORK/take.m4a"
ID=$(uuidgen)
HEX=$(echo "$ID" | tr -d '-' | tr 'a-f' 'A-F')
# WatchTake's JSON: Date encodes as seconds since 2001-01-01.
CREATED=$(python3 -I -c 'import time; print(time.time() - 978307200)')

drop_take() {
  cp "$WORK/take.m4a" "$INBOX/$ID.m4a"
  printf '{"id":"%s","createdAt":%s,"duration":3.0,"version":1}' "$ID" "$CREATED" > "$INBOX/$ID.json"
}

launch_and_wait_for_import() {
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  for _ in $(seq 1 30); do
    [ ! -e "$INBOX/$ID.json" ] && break
    sleep 1
  done
  [ ! -e "$INBOX/$ID.json" ] || { echo "FAIL: take still waiting in the inbox after 30 s"; exit 1; }
  sleep 2   # let the save settle before reading the store
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
}

count_nodes() {
  sqlite3 "$STORE" "SELECT count(*) FROM ZNODE WHERE hex(ZID)='$HEX' AND ZKINDRAW='voice';"
}

drop_take
launch_and_wait_for_import
COUNT=$(count_nodes)
[ "$COUNT" = 1 ] || { echo "FAIL: expected 1 voice thought for $ID, found $COUNT"; exit 1; }
echo "PASS: imported $ID as one voice thought"
echo "  title/transcript (empty until speech recognition is allowed):"
sqlite3 "$STORE" "SELECT '  ' || ZTITLE || ' | ' || substr(ifnull(ZTRANSCRIPTION,''),1,60) FROM ZNODE WHERE hex(ZID)='$HEX';"

drop_take
launch_and_wait_for_import
COUNT=$(count_nodes)
[ "$COUNT" = 1 ] || { echo "FAIL: second copy imported again ($COUNT thoughts)"; exit 1; }
echo "PASS: a second copy of $ID was refused"
```

Run: `chmod +x Scripts/watch-inbox-e2e/run.sh`, `xcodegen generate`, the phone build, then `Scripts/watch-inbox-e2e/run.sh $PHONE`.
Expected: `FAIL: take still waiting in the inbox after 30 s` (nothing imports yet).

- [ ] **Step 2: Create `Oryne/Services/WatchTakeImporter.swift`**

```swift
import Foundation
import SwiftData
import UIKit

/// Turns wrist takes waiting in the inbox folder into ordinary voice
/// thoughts, exactly once each, then understands them the way an in-app
/// whisper is understood. Both delivery paths (WatchConnectivity and the
/// iCloud inbox) and the launch sweep call `drain()`. One pass runs at a
/// time; a call that arrives mid-pass gets another pass.
@MainActor
final class WatchTakeImporter {
    private let context: ModelContext
    private let ai: any OceanAIService
    private let folder: WatchInboxFolder
    private let defaults: UserDefaults
    private var ledger: ImportLedger
    private var isDraining = false
    private var needsAnotherPass = false

    /// The watch should hear about these: after each import and each title.
    var confirmationsChanged: (([WatchConfirmation]) -> Void)?
    /// A take is settled (imported now, or already seen): its iCloud inbox
    /// record, if any, can go.
    var didSettle: ((UUID) -> Void)?

    init(context: ModelContext, ai: any OceanAIService, folder: WatchInboxFolder, defaults: UserDefaults) {
        self.context = context
        self.ai = ai
        self.folder = folder
        self.defaults = defaults
        var ledger = ImportLedger.load(from: defaults)
        ledger.prune(now: .now)
        self.ledger = ledger
    }

    var recentConfirmations: [WatchConfirmation] {
        ledger.recentConfirmations()
    }

    func drain() async {
        guard !isDraining else {
            needsAnotherPass = true
            return
        }
        isDraining = true
        // Transcription can take seconds; a background delivery shouldn't be
        // cut off mid-pass. If iOS ends it anyway, the next drain resumes.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Oryne.WatchTakeImport")
        defer {
            isDraining = false
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
        repeat {
            needsAnotherPass = false
            importWaitingTakes()
            await understandImported()
        } while needsAnotherPass
    }

    // MARK: Import

    private func importWaitingTakes() {
        var imported = false
        for take in folder.pending() {
            if !ledger.hasSeen(take.id), let existing = node(take.id) {
                // Already in the store, from before this ledger existed (a
                // reinstall): record it rather than duplicate it.
                ledger.markImported(take.id, at: .now)
                ledger.markUnderstood(take.id, title: title(of: existing))
                ledger.save(to: defaults)
            }
            if ledger.hasSeen(take.id) {
                // A second copy (the other path, a retry) or a thought the
                // user already deleted: never recreate it.
                folder.remove(take.id)
                didSettle?(take.id)
                continue
            }
            guard let audio = try? Data(contentsOf: folder.audioURL(for: take.id)), !audio.isEmpty else {
                // An empty delivery holds nothing to keep. The watch still has
                // the take and will send it again over iCloud.
                folder.remove(take.id)
                continue
            }
            let node = NodeComposer.make(kind: .voice, audioData: audio, detectThemes: false)
            node.id = take.id
            node.createdAt = take.createdAt
            node.updatedAt = take.createdAt
            context.insert(node)
            do {
                try context.save()
            } catch {
                // Leave the files in place: the next pass or launch retries.
                context.delete(node)
                continue
            }
            ledger.markImported(take.id, at: .now)
            ledger.save(to: defaults)
            folder.remove(take.id)
            didSettle?(take.id)
            imported = true
        }
        if imported { confirmationsChanged?(ledger.recentConfirmations()) }
    }

    // MARK: Understanding

    private func understandImported() async {
        for id in ledger.awaitingUnderstanding {
            if node(id) != nil {
                await VoiceUnderstanding.run(nodeID: id, audioTempURL: nil, context: context, ai: ai)
            }
            ledger.markUnderstood(id, title: node(id).flatMap(title(of:)))
            ledger.save(to: defaults)
            confirmationsChanged?(ledger.recentConfirmations())
        }
    }

    // MARK: Helpers

    private func node(_ id: UUID) -> Node? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// The name the watch shows: the thought's title once it has one. Never
    /// the "Whisper" fallback, which would pretend to be a name.
    private func title(of node: Node) -> String? {
        let title = node.title.trimmed
        return title.isEmpty ? nil : title
    }
}
```

- [ ] **Step 3: Create `Oryne/Services/WatchBridge.swift`**

```swift
import Foundation
import SwiftData

/// Wires the phone's wrist-take pipeline together: the inbox folder and the
/// importer (and, in later steps, the WatchConnectivity link and the iCloud
/// inbox reader). A singleton because system callbacks (the WCSession
/// delegate, the app delegate's push handler) need to reach it.
@MainActor
final class WatchBridge {
    static let shared = WatchBridge()

    private var importer: WatchTakeImporter?

    func start(context: ModelContext, ai: any OceanAIService) {
        guard importer == nil else { return }
        importer = WatchTakeImporter(
            context: context,
            ai: ai,
            folder: .standard,
            defaults: FastCapturePreferences.defaults
        )
    }

    /// Imports whatever has arrived and finishes any pending understanding.
    func drain() async {
        await importer?.drain()
    }

    /// Launch and foreground: import everything waiting.
    func refresh() async {
        await drain()
    }
}
```

- [ ] **Step 4: Wire the bridge into `Oryne/App/OryneApp.swift`**

Add the scene phase below `let container = Persistence.shared`:

```swift
    let container = Persistence.shared
    @Environment(\.scenePhase) private var scenePhase
```

At the end of `init()` (after the `#endif`), add:

```swift
        // Wrist takes: start early so deliveries that arrive while the app is
        // launched in the background reach the importer.
        WatchBridge.shared.start(context: container.mainContext, ai: ai)
```

In the first `.task`, after `Self.expireConfirmedAudio(context: container.mainContext)`, add:

```swift
                    // Import any wrist takes that arrived while Oryne was closed.
                    await WatchBridge.shared.refresh()
```

After the second `.task { ... }` block (the speech prefetch), add:

```swift
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await WatchBridge.shared.refresh() }
                }
```

- [ ] **Step 5: Run the end-to-end script to verify it passes**

Run: `xcodegen generate`, the phone build, then `Scripts/watch-inbox-e2e/run.sh $PHONE`.
Expected:
```
PASS: imported <UUID> as one voice thought
  title/transcript (empty until speech recognition is allowed):
  ...
PASS: a second copy of <UUID> was refused
```
The title stays empty when the simulator's speech recognition prompt is unanswered (`simctl privacy` has no speech service); that is expected here and covered on device.

- [ ] **Step 6: Run the full unit tests (regression)**

Run: the full unit test command → `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Oryne/Services/WatchTakeImporter.swift Oryne/Services/WatchBridge.swift Oryne/App/OryneApp.swift Scripts/watch-inbox-e2e/run.sh
git commit -m "Watch: import wrist takes on the phone exactly once, then understand them"
```

---

### Task 7: Phone WatchConnectivity link

**Files:**
- Create: `Oryne/Services/WatchLink.swift`
- Modify: `Oryne/Services/WatchBridge.swift` (full replacement below)

**Interfaces:**
- Consumes: `WatchInboxFolder.accept(_:movingAudioFrom:)` (Task 4); `WatchWire` (Task 1); `WatchTakeImporter` (Task 6).
- Produces: `final class WatchLink: NSObject, WCSessionDelegate`: `init(folder:)`, `activate()`, `send(_ confirmations: [WatchConfirmation])`, `onArrival: (() -> Void)?`, `onActivated: ((_ isPaired: Bool) -> Void)?`. `WatchBridge` gains `linkActivated(isPaired:)` (private).

- [ ] **Step 1: Create `Oryne/Services/WatchLink.swift`**

```swift
import Foundation
import WatchConnectivity

/// The phone's end of WatchConnectivity. Receives wrist takes as files,
/// answers the watch's wake ping, and tells the watch which takes are in the
/// Ocean (application context). Delegate callbacks arrive on a background
/// queue; anything that touches the store hops to the main actor through
/// `onArrival`.
final class WatchLink: NSObject, WCSessionDelegate {
    private let folder: WatchInboxFolder

    /// A take landed in the inbox folder, or the watch pinged: import now.
    var onArrival: (() -> Void)?
    /// Activation finished; `isPaired` is now meaningful.
    var onActivated: ((_ isPaired: Bool) -> Void)?

    init(folder: WatchInboxFolder) {
        self.folder = folder
    }

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Replaces the application context with the latest confirmations. A
    /// no-op until a watch with Oryne installed is paired.
    func send(_ confirmations: [WatchConfirmation]) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled
        else { return }
        try? session.updateApplicationContext(WatchWire.context(for: confirmations))
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        onActivated?(activationState == .activated && session.isPaired)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches: activate again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let take = WatchWire.take(fromMetadata: file.metadata) else { return }
        // Move before returning: the system deletes the file afterwards.
        do {
            try folder.accept(take, movingAudioFrom: file.fileURL)
        } catch {
            return
        }
        onArrival?()
    }

    /// The wake ping. Being launched to receive it is the point: once the
    /// session is active, the queued file transfer is delivered.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onArrival?()
    }
}
```

- [ ] **Step 2: Replace `Oryne/Services/WatchBridge.swift`**

```swift
import Foundation
import SwiftData

/// Wires the phone's wrist-take pipeline together: the inbox folder, the
/// importer, and the WatchConnectivity link (the iCloud inbox reader joins in
/// a later step). A singleton because system callbacks (the WCSession
/// delegate, the app delegate's push handler) need to reach it.
@MainActor
final class WatchBridge {
    static let shared = WatchBridge()

    private var importer: WatchTakeImporter?
    private var link: WatchLink?

    func start(context: ModelContext, ai: any OceanAIService) {
        guard importer == nil else { return }
        let folder = WatchInboxFolder.standard
        let importer = WatchTakeImporter(
            context: context,
            ai: ai,
            folder: folder,
            defaults: FastCapturePreferences.defaults
        )
        let link = WatchLink(folder: folder)
        importer.confirmationsChanged = { [weak link] confirmations in
            link?.send(confirmations)
        }
        link.onArrival = {
            Task { @MainActor in await WatchBridge.shared.drain() }
        }
        link.onActivated = { isPaired in
            Task { @MainActor in WatchBridge.shared.linkActivated(isPaired: isPaired) }
        }
        self.importer = importer
        self.link = link
        link.activate()
    }

    /// Imports whatever has arrived and finishes any pending understanding.
    func drain() async {
        await importer?.drain()
    }

    /// Launch and foreground: import everything waiting.
    func refresh() async {
        await drain()
    }

    private func linkActivated(isPaired: Bool) {
        guard isPaired, let importer else { return }
        // A watch that missed an update catches up on activation.
        link?.send(importer.recentConfirmations)
    }
}
```

- [ ] **Step 3: Build and re-run the end-to-end script (regression)**

Run: `xcodegen generate`, the phone build → `** BUILD SUCCEEDED **`.
Run: `Scripts/watch-inbox-e2e/run.sh $PHONE` → both `PASS` lines (the app launches with the session active on the paired simulator and still imports).
File delivery itself is device only: Apple's docs say `session(_:didReceive:)` is never called in Simulator. Task 13 adds it to the hardware checklist.

- [ ] **Step 4: Commit**

```bash
git add Oryne/Services/WatchLink.swift Oryne/Services/WatchBridge.swift
git commit -m "Watch: receive wrist takes over WatchConnectivity and confirm them back"
```

---

### Task 8: Phone iCloud inbox reader and the silent push

**Files:**
- Create: `Oryne/Services/WatchInboxReader.swift`
- Create: `Oryne/App/OryneAppDelegate.swift`
- Modify: `Oryne/Services/WatchBridge.swift` (full replacement below)
- Modify: `Oryne/App/OryneApp.swift` (adopt the app delegate)

**Interfaces:**
- Consumes: `WatchInboxSchema` (Task 1); `WatchInboxFolder.accept(_:copyingAudioFrom:)` (Task 4); `WatchTakeImporter.didSettle` (Task 6); `WatchLink.onActivated` (Task 7).
- Produces: `@MainActor final class WatchInboxReader`: `init(folder:defaults:)`, `prepare() async`, `fetch() async -> Bool` (true when takes arrived), `deleteRecord(_ id: UUID) async`, `nonisolated static func isInboxPush(_:) -> Bool`. `final class OryneAppDelegate: NSObject, UIApplicationDelegate`. `WatchBridge.refresh()` now fetches the inbox first.

- [ ] **Step 1: Create `Oryne/Services/WatchInboxReader.swift`**

```swift
import Foundation
import CloudKit

/// Reads the iCloud inbox the watch falls back to: a zone subscription for
/// silent pushes, plus a zone-changes fetch at launch and on foreground
/// (pushes are not guaranteed). Each take's audio is copied into the inbox
/// folder for the importer; a record is deleted once the importer has
/// settled its take. Runs only on the paired iPhone, and only in a signed
/// build (CloudKit traps without the entitlement).
@MainActor
final class WatchInboxReader {
    private let database = CKContainer(identifier: WatchInboxSchema.containerID).privateCloudDatabase
    private let folder: WatchInboxFolder
    private let defaults: UserDefaults
    private var isFetching = false

    private static let tokenKey = "watch.inboxChangeToken"
    private static let preparedKey = "watch.inboxPrepared"

    init(folder: WatchInboxFolder, defaults: UserDefaults) {
        self.folder = folder
        self.defaults = defaults
    }

    /// Whether a remote notification is this inbox's subscription firing.
    nonisolated static func isInboxPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID == WatchInboxSchema.subscriptionID
    }

    /// Creates the zone and the silent-push subscription, once.
    func prepare() async {
        guard !defaults.bool(forKey: Self.preparedKey) else { return }
        do {
            _ = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: WatchInboxSchema.zoneID)], deleting: []
            )
            let subscription = CKRecordZoneSubscription(
                zoneID: WatchInboxSchema.zoneID,
                subscriptionID: WatchInboxSchema.subscriptionID
            )
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            defaults.set(true, forKey: Self.preparedKey)
        } catch {
            // Signed out or offline: try again on the next fetch.
        }
    }

    /// Copies every new take in the zone into the inbox folder. True when at
    /// least one arrived.
    func fetch() async -> Bool {
        guard !isFetching else { return false }
        isFetching = true
        defer { isFetching = false }
        await prepare()

        var token = loadToken()
        var arrived = false
        do {
            while true {
                let changes = try await database.recordZoneChanges(inZoneWith: WatchInboxSchema.zoneID, since: token)
                for (_, result) in changes.modificationResultsByID {
                    guard case .success(let modification) = result else { continue }
                    if accept(modification.record) { arrived = true }
                }
                token = changes.changeToken
                saveToken(token)
                if !changes.moreComing { break }
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            saveToken(nil)   // the next fetch starts over
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            defaults.set(false, forKey: Self.preparedKey)
        } catch {
            // Offline or signed out: the next launch, foreground, or push retries.
        }
        return arrived
    }

    /// Deletes a settled take's record. An unknown record is fine: that take
    /// came over WatchConnectivity and was never uploaded.
    func deleteRecord(_ id: UUID) async {
        _ = try? await database.modifyRecords(saving: [], deleting: [WatchInboxSchema.recordID(for: id)])
    }

    private func accept(_ record: CKRecord) -> Bool {
        guard let take = WatchInboxSchema.take(from: record),
              let audio = WatchInboxSchema.audioURL(in: record)
        else { return false }
        return (try? folder.accept(take, copyingAudioFrom: audio)) != nil
    }

    private func loadToken() -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: Self.tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken?) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else {
            defaults.removeObject(forKey: Self.tokenKey)
            return
        }
        defaults.set(data, forKey: Self.tokenKey)
    }
}
```

- [ ] **Step 2: Create `Oryne/App/OryneAppDelegate.swift`**

```swift
import UIKit

/// Receives the iCloud inbox's silent push. The SwiftData mirror handles its
/// own pushes; any notification that isn't the watch inbox subscription is
/// left alone.
final class OryneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard WatchInboxReader.isInboxPush(userInfo) else { return .noData }
        await WatchBridge.shared.refresh()
        return .newData
    }
}
```

- [ ] **Step 3: Replace `Oryne/Services/WatchBridge.swift`**

```swift
import Foundation
import SwiftData

/// Wires the phone's wrist-take pipeline together: the inbox folder, the
/// importer, the WatchConnectivity link, and the iCloud inbox reader. A
/// singleton because system callbacks (the WCSession delegate, the app
/// delegate's push handler) need to reach it.
@MainActor
final class WatchBridge {
    static let shared = WatchBridge()

    private var importer: WatchTakeImporter?
    private var link: WatchLink?
    private var inboxReader: WatchInboxReader?

    func start(context: ModelContext, ai: any OceanAIService) {
        guard importer == nil else { return }
        let folder = WatchInboxFolder.standard
        let importer = WatchTakeImporter(
            context: context,
            ai: ai,
            folder: folder,
            defaults: FastCapturePreferences.defaults
        )
        let link = WatchLink(folder: folder)
        importer.confirmationsChanged = { [weak link] confirmations in
            link?.send(confirmations)
        }
        importer.didSettle = { [weak self] id in
            guard let reader = self?.inboxReader else { return }
            Task { await reader.deleteRecord(id) }
        }
        link.onArrival = {
            Task { @MainActor in await WatchBridge.shared.drain() }
        }
        link.onActivated = { isPaired in
            Task { @MainActor in WatchBridge.shared.linkActivated(isPaired: isPaired) }
        }
        self.importer = importer
        self.link = link
        link.activate()
    }

    /// Imports whatever has arrived and finishes any pending understanding.
    func drain() async {
        await importer?.drain()
    }

    /// Launch, foreground, and the inbox push: pull the iCloud inbox (once
    /// the reader runs), then import everything waiting.
    func refresh() async {
        if let inboxReader {
            _ = await inboxReader.fetch()
        }
        await drain()
    }

    private func linkActivated(isPaired: Bool) {
        guard isPaired, let importer else { return }
        // A watch that missed an update catches up on activation.
        link?.send(importer.recentConfirmations)
        startInboxReader()
    }

    /// Only the paired iPhone reads the inbox (an iPad importing too would
    /// mint duplicates), and only a signed build may touch CloudKit.
    private func startInboxReader() {
        guard inboxReader == nil, WatchInboxSchema.isSignedBuild else { return }
        inboxReader = WatchInboxReader(folder: .standard, defaults: FastCapturePreferences.defaults)
        Task { await refresh() }
    }
}
```

- [ ] **Step 4: Adopt the app delegate in `Oryne/App/OryneApp.swift`**

Add as the first line inside `struct OryneApp: App {`:

```swift
    @UIApplicationDelegateAdaptor(OryneAppDelegate.self) private var appDelegate
```

- [ ] **Step 5: Build, test, and re-run the end-to-end script**

Run: `xcodegen generate`, the phone build → `** BUILD SUCCEEDED **`.
Run: the full unit test command → `** TEST SUCCEEDED **` (Task 1's record round trip covers the mapping the reader uses).
Run: `Scripts/watch-inbox-e2e/run.sh $PHONE` → both `PASS` lines. On the simulator the reader starts (paired, entitlements present) and its CloudKit calls fail without an iCloud account; the import must still pass.

- [ ] **Step 6: Commit**

```bash
git add Oryne/Services/WatchInboxReader.swift Oryne/App/OryneAppDelegate.swift Oryne/Services/WatchBridge.swift Oryne/App/OryneApp.swift
git commit -m "Watch: read the iCloud inbox on the paired iPhone, with a silent push"
```

---

### Task 9: Watch target and recorder

**Files:**
- Modify: `project.yml` (watchOS floor; embed the watch app; add the `OryneWatch` target)
- Create: `OryneWatch/OryneWatchApp.swift`
- Create: `OryneWatch/Services/WatchRecorder.swift`
- Create: `OryneWatch/Debug/WatchSelfTest.swift`
- Copy: `OryneWatch/Assets.xcassets` from Phase 1
- Create: `Scripts/xcstrings-add/add.py`, `OryneWatch/Resources/InfoPlist.xcstrings`
- Generated and committed: `OryneWatch/Info.plist`, `OryneWatch/OryneWatch.entitlements`

**Interfaces:**
- Consumes: `OceanTheme` (by path).
- Produces: `@MainActor @Observable final class WatchRecorder: NSObject`: `enum StartResult { started, permissionDenied, failed }`, `struct Finished { url: URL; duration: TimeInterval }`, `static let cap: TimeInterval` (300, DEBUG override `ORYNE_WATCH_CAP_SECONDS`), `isRecording`, `elapsed`, `level`, `permissionDenied: Bool`, `onEndedBySystem: (() -> Void)?`, `start(writingTo:) async -> StartResult`, `stop() async -> Finished?`, `cancel() async`. `enum WatchSelfTest` (DEBUG). `Scripts/xcstrings-add/add.py <catalog> <pairs.json>`.

- [ ] **Step 1: Add the watch target to `project.yml`**

In `options:`, extend the deployment targets:

```yaml
  deploymentTarget:
    iOS: "18.0"
    watchOS: "11.0"
```

In the `Oryne` target's `dependencies:`, after the `OceanWidgets` entry, add:

```yaml
      # The Apple Watch companion installs alongside the phone app.
      - target: OryneWatch
        embed: true
```

Append this target at the end of `targets:`:

```yaml
  # Apple Watch companion: catches a whisper from the wrist and sends it to
  # the phone (WatchConnectivity, with an iCloud inbox fallback). It records,
  # queues, and sends only; the phone transcribes and organizes. Lean on
  # purpose: it compiles Shared/Watch and the theme, never SwiftData or Node.
  OryneWatch:
    type: application
    platform: watchOS
    sources:
      - path: OryneWatch
      - path: Shared/Watch
      - path: Oryne/DesignSystem/OceanTheme.swift
    scheme:
      configVariants: []
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.inspireocean.app.watchkitapp
        # App Store validation requires the watch app to ship an icon and a
        # CFBundleIconName; actool writes that key from this asset catalog.
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    entitlements:
      path: OryneWatch/OryneWatch.entitlements
      properties:
        # Not shared with the phone (watch containers never are). Present as
        # the signed-build proof that gates CloudKit (WatchInboxSchema.isSignedBuild).
        com.apple.security.application-groups:
          - group.com.inspireocean.shared
        # Upload only, to the iCloud inbox zone.
        com.apple.developer.icloud-services:
          - CloudKit
        com.apple.developer.icloud-container-identifiers:
          - iCloud.com.inspireocean.app
    info:
      path: OryneWatch/Info.plist
      properties:
        CFBundleDisplayName: Oryne
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        CFBundleLocalizations:
          - en
          - zh-Hans
        WKApplication: true
        WKCompanionAppBundleIdentifier: com.inspireocean.app
        # actool writes the nested CFBundleIcons for watchOS but not the
        # top-level CFBundleIconName that App Store validation (error 90713)
        # requires on the watch bundle; set it explicitly to match AppIcon.
        CFBundleIconName: AppIcon
        CFBundleURLTypes:
          - CFBundleURLName: com.inspireocean.app.watchkitapp
            CFBundleURLSchemes:
              - oryne
        # Keeps a take recording with the wrist down (spec §1).
        UIBackgroundModes:
          - audio
        NSMicrophoneUsageDescription: "Oryne uses the microphone to catch a whisper from your wrist before it disappears."
```

- [ ] **Step 2: Copy the Phase 1 icon (files only, no merge)**

Run: `git checkout feat/watchos-quick-capture -- OryneWatch/Assets.xcassets`
Run: `ls OryneWatch/Assets.xcassets/AppIcon.appiconset` → `Contents.json  icon-1024.png`.

- [ ] **Step 3: Create the string catalog helper `Scripts/xcstrings-add/add.py`**

```python
#!/usr/bin/env python3
"""Add keys with zh-Hans values to an Xcode string catalog (.xcstrings).

Value-as-key catalogs (the English text is the key): each pair becomes a key
whose zh-Hans stringUnit is marked needs_review, the way the app's existing
Chinese entries are flagged. Existing keys are left untouched, and a missing
catalog is created. The file is written back in Xcode's own formatting
(2-space indent, " : " separators, empty objects spread over a blank line,
no trailing newline), so a diff shows only the new keys. Round-tripping
Oryne/Resources/Localizable.xcstrings with no pairs is byte-identical.

Usage: add.py <catalog.xcstrings> <pairs.json>
  pairs.json: {"English text": "中文", ...}
"""
import json
import re
import sys
from pathlib import Path


def write_xcode_json(path: Path, data: dict) -> None:
    out = json.dumps(data, indent=2, ensure_ascii=False, separators=(",", " : "))
    out = re.sub(
        r"(?m)^(\s*)(.*) : \{\}(,?)$",
        lambda m: f"{m.group(1)}{m.group(2)} : {{\n\n{m.group(1)}}}{m.group(3)}",
        out,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(out, encoding="utf-8")


def main(catalog_path: str, pairs_path: str) -> None:
    catalog = Path(catalog_path)
    if catalog.exists():
        data = json.loads(catalog.read_text(encoding="utf-8"))
    else:
        data = {"sourceLanguage": "en", "strings": {}, "version": "1.1"}
    pairs = json.loads(Path(pairs_path).read_text(encoding="utf-8"))
    added = 0
    for key, zh in pairs.items():
        if key in data["strings"]:
            continue
        data["strings"][key] = {
            "localizations": {"zh-Hans": {"stringUnit": {"state": "needs_review", "value": zh}}}
        }
        added += 1
    write_xcode_json(catalog, data)
    print(f"{catalog}: added {added}, skipped {len(pairs) - added}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
```

Verify it preserves Xcode's format: `printf '{}' > /tmp/none.json && cp Oryne/Resources/Localizable.xcstrings /tmp/before.xcstrings && python3 -I Scripts/xcstrings-add/add.py /tmp/before.xcstrings /tmp/none.json && cmp /tmp/before.xcstrings Oryne/Resources/Localizable.xcstrings && echo IDENTICAL` → `added 0, skipped 0` then `IDENTICAL`.

- [ ] **Step 4: Localize the microphone prompt**

Write `/tmp/watch-infoplist.json`:

```json
{"NSMicrophoneUsageDescription": "Oryne 使用麦克风，在语音消失之前从手腕上接住它。"}
```

Run: `python3 -I Scripts/xcstrings-add/add.py OryneWatch/Resources/InfoPlist.xcstrings /tmp/watch-infoplist.json` → `added 1, skipped 0`.

- [ ] **Step 5: Create `OryneWatch/Services/WatchRecorder.swift`**

```swift
import Foundation
import AVFoundation
import Observation

/// Records a wrist take to an AAC `.m4a`, byte-compatible with the phone
/// recorder (`kAudioFormatMPEG4AAC`, mono, 12 kHz), so it drops straight into
/// `Node.audioData` on the phone. The watch never transcribes.
///
/// Main-actor isolated: metering, `level`, and `elapsed` all live on the main
/// actor (Phase 1 ran its timer off the main run loop, and the timer froze).
/// `stop()` waits for the recorder's finish callback, so the file is
/// complete before anyone reads it.
@MainActor
@Observable
final class WatchRecorder: NSObject {

    enum StartResult {
        case started
        case permissionDenied
        case failed
    }

    struct Finished {
        let url: URL
        let duration: TimeInterval
    }

    /// The hard cap on one take (spec: 5 minutes). DEBUG builds read
    /// `ORYNE_WATCH_CAP_SECONDS` so the cap path can be tested in seconds.
    static let cap: TimeInterval = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ORYNE_WATCH_CAP_SECONDS"],
           let seconds = TimeInterval(raw) { return seconds }
        #endif
        return 5 * 60
    }()

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// 0...1 input level for the waveform.
    private(set) var level: Double = 0

    /// The take ended without a stop from the user: the cap, an interruption
    /// (a call, Siri), or an encoder error. The owner finishes the take
    /// exactly as if the user had stopped it.
    @ObservationIgnored var onEndedBySystem: (() -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var finishWaiter: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var finishedFlag: Bool?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 12_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    var permissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// Prompts on first use; after a denial it returns false at once, so the
    /// denied state never loops.
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(writingTo url: URL) async -> StartResult {
        guard !isRecording, !isStarting else { return .started }
        isStarting = true
        defer { isStarting = false }
        guard await requestPermission() else { return .permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            return .failed
        }
        do {
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                deactivateSession()
                return .failed
            }
            self.recorder = recorder
            finishedFlag = nil
            isRecording = true
            elapsed = 0
            startMetering()
            observeInterruptions()
            return .started
        } catch {
            deactivateSession()
            return .failed
        }
    }

    /// Stops, waits for the file to be finalized, and returns it. Nil when
    /// nothing was recording or the encoder reported failure.
    func stop() async -> Finished? {
        guard let recorder, isRecording else { return nil }
        let duration = recorder.currentTime   // only valid while running
        let url = recorder.url
        stopMetering()
        isRecording = false
        level = 0

        let succeeded: Bool
        if let finishedFlag {
            // The system already closed the file (an interruption stopped it).
            succeeded = finishedFlag
        } else {
            succeeded = await withCheckedContinuation { continuation in
                finishWaiter = continuation
                recorder.stop()
                // Never hang on a finish callback that doesn't come.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.finished(successfully: FileManager.default.fileExists(atPath: url.path))
                }
            }
        }
        self.recorder = nil
        removeInterruptionObserver()
        deactivateSession()
        return succeeded ? Finished(url: url, duration: duration) : nil
    }

    /// Stops and deletes: a take nobody meant to keep.
    func cancel() async {
        if let finished = await stop() {
            try? FileManager.default.removeItem(at: finished.url)
        }
    }

    // MARK: Metering

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)   // dBFS, about -160...0
                self.level = min(1, Double(max(0, (power + 50) / 50)))
                self.elapsed = recorder.currentTime
                if self.elapsed >= Self.cap {
                    self.onEndedBySystem?()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
    }

    // MARK: Interruptions and session

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began
            else { return }
            MainActor.assumeIsolated { self?.onEndedBySystem?() }
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    fileprivate func finished(successfully flag: Bool) {
        if finishedFlag == nil { finishedFlag = flag }
        finishWaiter?.resume(returning: flag)
        finishWaiter = nil
    }
}

extension WatchRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finished(successfully: flag) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.onEndedBySystem?() }
    }
}
```

- [ ] **Step 6: Create `OryneWatch/Debug/WatchSelfTest.swift`**

```swift
#if DEBUG
import Foundation
import AVFoundation

/// Simulator checks driven by the launch environment (`SIMCTL_CHILD_` prefix
/// on `simctl launch --console-pty`). Each prints one line and exits.
///
/// - `ORYNE_WATCH_SELFTEST=recorder`: records two seconds and checks the file
///   decodes with a nonzero duration.
@MainActor
enum WatchSelfTest {

    static func runIfRequested() {
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_SELFTEST"] {
        case "recorder": Task { await recorder() }
        default: break
        }
    }

    private static func recorder() async {
        let recorder = WatchRecorder()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString).m4a")
        let start = await recorder.start(writingTo: url)
        guard start == .started else { report("RECORDER", "FAIL start=\(start)") }
        try? await Task.sleep(for: .seconds(2))
        guard let finished = await recorder.stop() else { report("RECORDER", "FAIL stop returned nil") }
        let decoded = (try? AVAudioPlayer(contentsOf: finished.url))?.duration ?? 0
        report("RECORDER", decoded > 1.5 ? "PASS duration=\(decoded)" : "FAIL duration=\(decoded)")
    }

    static func report(_ name: String, _ line: String) -> Never {
        print("\(name)_SELFTEST \(line)")
        exit(0)
    }
}
#endif
```

- [ ] **Step 7: Create `OryneWatch/OryneWatchApp.swift`**

```swift
import SwiftUI

@main
struct OryneWatchApp: App {
    init() {
        #if DEBUG
        WatchSelfTest.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            OceanTheme.abyss.ignoresSafeArea()
        }
    }
}
```

- [ ] **Step 8: Generate, build both, and check the embedding**

Run: `xcodegen generate`.
Run: the watch build → `** BUILD SUCCEEDED **`. If `OceanTheme.swift` reports an API unavailable on watchOS, wrap only that declaration in `#if os(iOS)` … `#endif` and rebuild (it compiled on watchOS 11 in Phase 1).
Run: the phone build → `** BUILD SUCCEEDED **`.
Run: `ls $DD/Build/Products/Debug-iphonesimulator/Oryne.app/Watch` → `OryneWatch.app`.
Run: `plutil -p OryneWatch/Info.plist | grep -E "UIBackgroundModes|WKCompanion|CFBundleIconName" -A1` → shows `audio`, `com.inspireocean.app`, `AppIcon`.

- [ ] **Step 9: Run the recorder self-test**

```bash
xcrun simctl boot $WATCH 2>/dev/null || true
xcrun simctl install $WATCH $DD/Build/Products/Debug-watchsimulator/OryneWatch.app
xcrun simctl privacy $WATCH grant microphone com.inspireocean.app.watchkitapp
SIMCTL_CHILD_ORYNE_WATCH_SELFTEST=recorder xcrun simctl launch --console-pty --terminate-running-process $WATCH com.inspireocean.app.watchkitapp
```

Expected: a line `RECORDER_SELFTEST PASS duration=2.0…` (silence still produces a decodable file).

- [ ] **Step 10: Commit**

```bash
git add project.yml OryneWatch Scripts/xcstrings-add
git commit -m "Watch: the wrist target and a recorder that finishes its file"
```

---

### Task 10: Watch queue and sync

**Files:**
- Create: `OryneWatch/Services/TakeQueue.swift`
- Create: `OryneWatch/Services/PhoneLink.swift`
- Create: `OryneWatch/Services/CloudInbox.swift`
- Create: `OryneWatch/Services/TakeSync.swift`
- Modify: `OryneWatch/Debug/WatchSelfTest.swift` (full replacement), `OryneWatch/OryneWatchApp.swift` (full replacement)

**Interfaces:**
- Consumes: `TakeQueueState`, `TakeQueueStore` (Tasks 2, 4); `WatchWire`, `WatchInboxSchema` (Task 1).
- Produces:
  - `@MainActor @Observable final class TakeQueue`: `init(store:)`, `state: TakeQueueState` (read-only), `audioURL(for:)`, `change(_ mutate: (inout TakeQueueState) -> Void)`, `deleteAudio(_:)`, DEBUG `showDemo(_:)`
  - `final class PhoneLink: NSObject, WCSessionDelegate`: `activate()`, `isActivated`, `isReachable`, `outstandingTakeIDs: Set<UUID>`, `send(_:audioURL:) -> Bool`, `wake(_:)`, `onConfirmations`, `onTransferFinished`, `onActivated` (all `@MainActor` closures)
  - `final class CloudInbox`: `static func makeIfAvailable() -> CloudInbox?`, `upload(_:audioURL:) async -> Bool`
  - `@MainActor final class TakeSync`: `init(queue:link:cloud:)`, `static let refreshIdentifier = "oryne.takes"`, `heldTakeID: UUID?`, `isPhoneReachable: Bool`, `start()`, `flush() async`

- [ ] **Step 1: Create `OryneWatch/Services/TakeQueue.swift`**

```swift
import Foundation
import AVFoundation
import Observation

/// The watch's queue of takes: the only place `TakeQueueState` is mutated.
/// Every change saves at once and sweeps audio the state says is safe
/// elsewhere, so a take is never lost to a crash and never kept longer than
/// it needs to be. A sweep never touches a recording the index doesn't list
/// (see `TakeQueueState.audioDisposable`); a take that leaves the queue
/// (Undo, or pruned once confirmed) takes its audio with it deliberately.
@MainActor
@Observable
final class TakeQueue {
    private(set) var state: TakeQueueState
    private let store: TakeQueueStore

    init(store: TakeQueueStore = .standard) {
        self.store = store
        var state = store.load()
        // Recordings caught but missing from the index (a failed save, an
        // unreadable index) go back in the queue rather than sit stuck.
        // Launch only: nothing is being recorded yet.
        let recovered = store.unlistedTakes(in: state) { url in
            let length = (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
            return length > 0 ? length : nil
        }
        for take in recovered {
            state.add(take, phoneReachableAtStop: false)
        }
        self.state = state
        if !recovered.isEmpty { store.save(state) }
        store.sweep(state)
    }

    func audioURL(for id: UUID) -> URL {
        store.audioURL(for: id)
    }

    func change(_ mutate: (inout TakeQueueState) -> Void) {
        let before = state
        mutate(&state)
        store.save(state)
        // A take leaves the index only by Undo or by being pruned once
        // confirmed (even when confirmed and pruned in the same change):
        // either way its audio goes now, since the sweep keeps anything the
        // index doesn't list.
        for item in before.takes where state.item(item.id) == nil {
            store.deleteAudio(item.id)
        }
        store.sweep(state)
    }

    /// Deletes a recording that was never queued (a reflex press, a failed
    /// or empty take). Queued takes lose their audio through `change`.
    func deleteAudio(_ id: UUID) {
        store.deleteAudio(id)
    }

    #if DEBUG
    /// Screenshot seam: show a queue without touching disk.
    func showDemo(_ demo: TakeQueueState) {
        state = demo
    }
    #endif
}
```

- [ ] **Step 2: Create `OryneWatch/Services/PhoneLink.swift`**

```swift
import Foundation
import WatchConnectivity

/// The watch's end of WatchConnectivity: hands takes to the system as file
/// transfers, pings the phone awake, and receives the phone's confirmations
/// (application context). Delegate callbacks arrive off the main thread and
/// hop to the main actor before touching anything.
final class PhoneLink: NSObject, WCSessionDelegate {
    var onConfirmations: (@MainActor ([WatchConfirmation]) -> Void)?
    var onTransferFinished: (@MainActor (_ id: UUID, _ delivered: Bool) -> Void)?
    var onActivated: (@MainActor () -> Void)?

    private let session = WCSession.default

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    var isActivated: Bool {
        session.activationState == .activated
    }

    /// Meaningful only while the watch app is on screen.
    var isReachable: Bool {
        isActivated && session.isReachable
    }

    /// Take IDs whose transfer the system still holds.
    var outstandingTakeIDs: Set<UUID> {
        Set(session.outstandingFileTransfers.compactMap { WatchWire.take(fromMetadata: $0.file.metadata)?.id })
    }

    /// Queues the file with the system. False when the session isn't active.
    func send(_ take: WatchTake, audioURL: URL) -> Bool {
        guard isActivated else { return false }
        session.transferFile(audioURL, metadata: WatchWire.metadata(for: take))
        return true
    }

    /// Wakes the phone app so a queued transfer is delivered now rather than
    /// at its next launch.
    func wake(_ id: UUID) {
        guard isReachable else { return }
        session.sendMessage([WatchWire.wakeKey: id.uuidString], replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let confirmations = WatchWire.confirmations(fromContext: session.receivedApplicationContext)
        Task { @MainActor in
            self.onActivated?()
            if !confirmations.isEmpty { self.onConfirmations?(confirmations) }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let confirmations = WatchWire.confirmations(fromContext: applicationContext)
        Task { @MainActor in self.onConfirmations?(confirmations) }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let id = WatchWire.take(fromMetadata: fileTransfer.file.metadata)?.id else { return }
        let delivered = error == nil
        Task { @MainActor in self.onTransferFinished?(id, delivered) }
    }
}
```

- [ ] **Step 3: Create `OryneWatch/Services/CloudInbox.swift`**

```swift
import Foundation
import CloudKit

/// Uploads takes to the iCloud inbox when the phone is out of reach. Upload
/// only: the watch never fetches the Ocean or any other record.
final class CloudInbox {
    private let database: CKDatabase
    private static let zoneReadyKey = "watch.inboxZoneReady"

    /// Nil in an unsigned build: CloudKit traps without the iCloud
    /// entitlement, and the App Group container is the signed-build proof.
    static func makeIfAvailable() -> CloudInbox? {
        guard WatchInboxSchema.isSignedBuild else { return nil }
        return CloudInbox(database: CKContainer(identifier: WatchInboxSchema.containerID).privateCloudDatabase)
    }

    private init(database: CKDatabase) {
        self.database = database
    }

    /// True once the record is saved in iCloud. A second upload of the same
    /// take overwrites the first.
    func upload(_ take: WatchTake, audioURL: URL) async -> Bool {
        do {
            try await ensureZone()
            let record = WatchInboxSchema.record(for: take, audioURL: audioURL)
            let (results, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            switch results[record.recordID] {
            case .success:
                return true
            case .failure(let error as CKError) where error.code == .zoneNotFound || error.code == .userDeletedZone:
                UserDefaults.standard.set(false, forKey: Self.zoneReadyKey)
                return false
            default:
                return false
            }
        } catch {
            return false
        }
    }

    private func ensureZone() async throws {
        guard !UserDefaults.standard.bool(forKey: Self.zoneReadyKey) else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: WatchInboxSchema.zoneID)], deleting: [])
        UserDefaults.standard.set(true, forKey: Self.zoneReadyKey)
    }
}
```

- [ ] **Step 4: Create `OryneWatch/Services/TakeSync.swift`**

```swift
import Foundation
import WatchKit

/// Moves takes off the watch (spec §2): WatchConnectivity for every take,
/// the iCloud inbox for takes the phone may not reach soon. It acts on what
/// `TakeQueueState` says each take still needs, and holds back the take
/// inside its Undo window.
@MainActor
final class TakeSync {
    static let refreshIdentifier = "oryne.takes"

    private let queue: TakeQueue
    private let link: PhoneLink
    private let cloud: CloudInbox?
    private var isFlushing = false
    private var flushAgain = false

    /// The take inside its Undo window: never sent until released.
    var heldTakeID: UUID?

    init(queue: TakeQueue, link: PhoneLink, cloud: CloudInbox?) {
        self.queue = queue
        self.link = link
        self.cloud = cloud
        link.onConfirmations = { [weak self] confirmations in
            self?.queue.change { $0.apply(confirmations) }
        }
        link.onTransferFinished = { [weak self] id, delivered in
            // A failed transfer is retried on the next flush, not in a loop.
            self?.queue.change { $0.markPhoneTransfer(id, delivered ? .delivered : .notSent) }
        }
        link.onActivated = { [weak self] in
            self?.reconcile()
            Task { await self?.flush() }
        }
    }

    /// The reading taken at stop decides the iCloud fallback.
    var isPhoneReachable: Bool {
        link.isReachable
    }

    func start() {
        link.activate()
    }

    /// Sends what each take still needs.
    func flush() async {
        guard !isFlushing else {
            flushAgain = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }
        repeat {
            flushAgain = false
            var sent: UUID?
            for item in queue.state.needingPhoneSend() where item.id != heldTakeID {
                if link.send(item.take, audioURL: queue.audioURL(for: item.id)) {
                    queue.change { $0.markPhoneTransfer(item.id, .pending) }
                    sent = item.id
                }
            }
            if let sent { link.wake(sent) }
            if let cloud {
                for item in queue.state.needingCloudUpload(now: .now) where item.id != heldTakeID {
                    if await cloud.upload(item.take, audioURL: queue.audioURL(for: item.id)) {
                        queue.change { $0.markInICloud(item.id) }
                    }
                }
            }
        } while flushAgain
        scheduleRefreshIfNeeded()
    }

    /// A transfer the state thinks is pending but the system no longer holds
    /// (the app relaunched before `didFinish` arrived) is sent again; the
    /// phone's ledger drops the duplicate.
    private func reconcile() {
        let outstanding = link.outstandingTakeIDs
        let lost = queue.state.takes
            .filter { $0.phoneTransfer == .pending && !outstanding.contains($0.id) }
            .map(\.id)
        guard !lost.isEmpty else { return }
        queue.change { state in lost.forEach { state.markPhoneTransfer($0, .notSent) } }
    }

    /// While any take is still only on the watch, ask watchOS for a
    /// background refresh so the iCloud fallback runs without the app open.
    private func scheduleRefreshIfNeeded() {
        guard queue.state.takes.contains(where: { $0.status == .onWatch }) else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: 15 * 60),
            userInfo: Self.refreshIdentifier as NSString
        ) { _ in }
    }
}
```

- [ ] **Step 5: Replace `OryneWatch/Debug/WatchSelfTest.swift`**

```swift
#if DEBUG
import Foundation
import AVFoundation

/// Simulator checks driven by the launch environment (`SIMCTL_CHILD_` prefix
/// on `simctl launch --console-pty`). Each prints one line and exits.
///
/// - `ORYNE_WATCH_SELFTEST=recorder`: records two seconds and checks the file
///   decodes with a nonzero duration.
/// - `ORYNE_WATCH_SELFTEST=sync`: waits for WatchConnectivity activation and
///   reports whether the session is active and whether the iCloud inbox is
///   available in this build.
@MainActor
enum WatchSelfTest {

    static func runIfRequested(sync: TakeSync? = nil, cloudAvailable: Bool = false) {
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_SELFTEST"] {
        case "recorder": Task { await recorder() }
        case "sync": Task { await syncCheck(cloudAvailable: cloudAvailable) }
        default: break
        }
    }

    private static func recorder() async {
        let recorder = WatchRecorder()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString).m4a")
        let start = await recorder.start(writingTo: url)
        guard start == .started else { report("RECORDER", "FAIL start=\(start)") }
        try? await Task.sleep(for: .seconds(2))
        guard let finished = await recorder.stop() else { report("RECORDER", "FAIL stop returned nil") }
        let decoded = (try? AVAudioPlayer(contentsOf: finished.url))?.duration ?? 0
        report("RECORDER", decoded > 1.5 ? "PASS duration=\(decoded)" : "FAIL duration=\(decoded)")
    }

    private static func syncCheck(cloudAvailable: Bool) async {
        let link = PhoneLink()
        link.activate()
        for _ in 0..<50 where !link.isActivated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        report("SYNC", link.isActivated
            ? "PASS activated=true cloud=\(cloudAvailable)"
            : "FAIL activated=false (is the watch simulator paired?)")
    }

    static func report(_ name: String, _ line: String) -> Never {
        print("\(name)_SELFTEST \(line)")
        exit(0)
    }
}
#endif
```

(The `sync` check activates its own `PhoneLink` so it reports independently of the app's session; WCSession is a singleton, so both see the same activation.)

- [ ] **Step 6: Replace `OryneWatch/OryneWatchApp.swift`**

```swift
import SwiftUI

@main
struct OryneWatchApp: App {
    private let queue: TakeQueue
    private let sync: TakeSync

    init() {
        let queue = TakeQueue()
        let cloud = CloudInbox.makeIfAvailable()
        let sync = TakeSync(queue: queue, link: PhoneLink(), cloud: cloud)
        self.queue = queue
        self.sync = sync
        sync.start()
        #if DEBUG
        WatchSelfTest.runIfRequested(sync: sync, cloudAvailable: cloud != nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            OceanTheme.abyss.ignoresSafeArea()
        }
        .backgroundTask(.appRefresh(TakeSync.refreshIdentifier)) { [sync] in
            await sync.flush()
        }
    }
}
```

- [ ] **Step 7: Build and run the sync self-test**

Run: `xcodegen generate`, the watch build → `** BUILD SUCCEEDED **`, the phone build → `** BUILD SUCCEEDED **`.
Run:

```bash
xcrun simctl boot $PHONE 2>/dev/null || true
xcrun simctl boot $WATCH 2>/dev/null || true
xcrun simctl install $WATCH $DD/Build/Products/Debug-watchsimulator/OryneWatch.app
SIMCTL_CHILD_ORYNE_WATCH_SELFTEST=sync xcrun simctl launch --console-pty --terminate-running-process $WATCH com.inspireocean.app.watchkitapp
```

Expected: `SYNC_SELFTEST PASS activated=true cloud=…`. `cloud=true` when the simulator build carries the App Group (the iCloud inbox is constructed, and its uploads fail without an iCloud account, which is the honest "waiting" path); `cloud=false` when it doesn't (the gate held). Either passes; note which in the task report.
Run: the full unit test command → `** TEST SUCCEEDED **` (the sending rules are Task 2's tests).

- [ ] **Step 8: Commit**

```bash
git add OryneWatch
git commit -m "Watch: a durable queue that sends over WatchConnectivity and falls back to iCloud"
```

---

### Task 11: Capture model, screens, and watch strings

**Files:**
- Create: `OryneWatch/Features/Capture/WatchCaptureModel.swift`
- Create: `OryneWatch/Features/Capture/WatchCaptureView.swift`
- Create: `OryneWatch/Resources/Localizable.xcstrings` (through the helper)
- Modify: `OryneWatch/Debug/WatchSelfTest.swift` (full replacement), `OryneWatch/OryneWatchApp.swift` (full replacement)
- Create: `Scripts/watch-screens/run.sh`

**Interfaces:**
- Consumes: `WatchRecorder` (Task 9); `TakeQueue`, `TakeSync` (Task 10); `WatchStatusLine`, `WatchTake` (Tasks 1, 2).
- Produces: `@MainActor @Observable final class WatchCaptureModel`: `enum Stage: Equatable { idle, starting, recording, caught(UUID), denied, failed, nothingCaught }`, `minimumDuration = 0.6`, `undoWindow = 5`, `stage`, `recorder`, `queue`, `statusLine`, `lastTitle`, `toggle() async`, `begin() async`, `finish() async`, `undo()`, `releaseHeldTake()`, `sceneBecameInactive()`, `sceneBecameActive() async`, `backgroundRefresh() async`, DEBUG `applyDemoEnvironment()`. `struct WatchCaptureView: View` taking `model`.

- [ ] **Step 1: Create `OryneWatch/Features/Capture/WatchCaptureModel.swift`**

```swift
import Foundation
import AVFoundation
import Observation
import WatchKit

/// The wrist capture flow as one state machine (spec §1): idle, recording,
/// caught (with Undo), and the honest failure states. The Action Button,
/// Siri, and the complication all call `toggle()`; the app icon only opens.
@MainActor
@Observable
final class WatchCaptureModel {

    enum Stage: Equatable {
        case idle
        case starting
        case recording
        case caught(UUID)
        case denied
        case failed
        case nothingCaught
    }

    /// A reflex press shouldn't mint a take.
    static let minimumDuration: TimeInterval = 0.6
    static let undoWindow: TimeInterval = 5

    private(set) var stage: Stage = .idle
    let recorder = WatchRecorder()
    let queue: TakeQueue
    private let sync: TakeSync
    @ObservationIgnored private var current: (id: UUID, startedAt: Date)?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init(queue: TakeQueue, sync: TakeSync) {
        self.queue = queue
        self.sync = sync
        recorder.onEndedBySystem = { [weak self] in
            Task { await self?.finish() }
        }
    }

    var statusLine: WatchStatusLine {
        .derive(from: queue.state)
    }

    var lastTitle: String? {
        WatchStatusLine.lastTitle(from: queue.state)
    }

    /// The one rule every trigger shares: idle or caught → record (a take
    /// held for Undo sends at once); recording → stop and catch.
    func toggle() async {
        switch stage {
        case .recording: await finish()
        case .starting: break
        default: await begin()
        }
    }

    func begin() async {
        releaseHeldTake()
        noticeTask?.cancel()
        stage = .starting
        let id = UUID()
        current = (id, .now)
        switch await recorder.start(writingTo: queue.audioURL(for: id)) {
        case .started:
            stage = .recording
        case .permissionDenied:
            discardRecording(id)
            stage = .denied
        case .failed:
            discardRecording(id)
            stage = .failed
        }
    }

    func finish() async {
        guard stage == .recording, let current else { return }
        // Claimed before any await: a second stop arriving together (the cap
        // and a tap) finds nothing to finish, instead of deleting this file.
        self.current = nil
        // The reading at stop decides whether the take also goes to iCloud now.
        let reachable = sync.isPhoneReachable
        let finished = await recorder.stop()

        guard let finished else {
            discardRecording(current.id)
            showNothingCaught()
            return
        }
        if finished.duration < Self.minimumDuration {
            discardRecording(current.id)
            stage = .idle   // a reflex press, discarded silently
            return
        }
        guard Self.isDecodable(finished.url) else {
            discardRecording(current.id)
            showNothingCaught()
            return
        }

        let take = WatchTake(id: current.id, createdAt: current.startedAt, duration: finished.duration)
        queue.change { $0.add(take, phoneReachableAtStop: reachable) }
        sync.heldTakeID = take.id
        WKInterfaceDevice.current().play(.success)
        stage = .caught(take.id)

        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            guard !Task.isCancelled else { return }
            self?.releaseHeldTake()
        }
    }

    /// Undo inside the window: nothing was sent, so nothing exists anywhere else.
    func undo() {
        guard case .caught(let id) = stage else { return }
        undoTask?.cancel()
        sync.heldTakeID = nil
        queue.change { $0.remove(id) }   // leaving the queue deletes its audio
        stage = .idle
    }

    /// Ends the Undo window (it ran out, the screen went off, or a new take
    /// began) and sends.
    func releaseHeldTake() {
        undoTask?.cancel()
        let wasHolding = sync.heldTakeID != nil
        sync.heldTakeID = nil
        if case .caught = stage { stage = .idle }
        if wasHolding { Task { await sync.flush() } }
    }

    /// Wrist down: a recording keeps going (spec §1); a take held for Undo
    /// sends now.
    func sceneBecameInactive() {
        if case .caught = stage { releaseHeldTake() }
    }

    func sceneBecameActive() async {
        // Recovery once the microphone has been allowed in Settings.
        if stage == .denied, !recorder.permissionDenied { stage = .idle }
        await sync.flush()
    }

    func backgroundRefresh() async {
        await sync.flush()
    }

    // MARK: Helpers

    private func discardRecording(_ id: UUID) {
        queue.deleteAudio(id)
    }

    private func showNothingCaught() {
        stage = .nothingCaught
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.stage == .nothingCaught else { return }
            self?.stage = .idle
        }
    }

    private static func isDecodable(_ url: URL) -> Bool {
        ((try? AVAudioPlayer(contentsOf: url))?.duration ?? 0) > 0
    }

    #if DEBUG
    /// Screenshot seams (`SIMCTL_CHILD_` prefix on `simctl launch`):
    /// `ORYNE_WATCH_DEMO=empty|waiting|onItsWay|inOcean` shows a sample queue;
    /// `ORYNE_WATCH_STAGE=recording|caught|denied|failed|nothing` shows that screen.
    func applyDemoEnvironment() {
        let env = ProcessInfo.processInfo.environment
        let now = Date()
        func take(_ secondsAgo: TimeInterval) -> WatchTake {
            WatchTake(id: UUID(), createdAt: now.addingTimeInterval(-secondsAgo), duration: 8)
        }
        var demo = TakeQueueState()
        let named = take(600)
        demo.add(named, phoneReachableAtStop: true)
        demo.apply([WatchConfirmation(id: named.id, title: "Lighthouse café")])
        switch env["ORYNE_WATCH_DEMO"] {
        case "empty":
            queue.showDemo(TakeQueueState())
        case "waiting":
            demo.add(take(60), phoneReachableAtStop: false)
            demo.add(take(30), phoneReachableAtStop: false)
            queue.showDemo(demo)
        case "onItsWay":
            let clouded = take(60)
            demo.add(clouded, phoneReachableAtStop: false)
            demo.markInICloud(clouded.id)
            queue.showDemo(demo)
        case "inOcean":
            queue.showDemo(demo)
        default:
            break
        }
        switch env["ORYNE_WATCH_STAGE"] {
        case "recording": Task { await begin() }
        case "caught": stage = .caught(UUID())
        case "denied": stage = .denied
        case "failed": stage = .failed
        case "nothing": stage = .nothingCaught
        default: break
        }
    }
    #endif
}
```

- [ ] **Step 2: Create `OryneWatch/Features/Capture/WatchCaptureView.swift`**

```swift
import SwiftUI

/// The wrist screens (spec §1), all from OceanTheme: near monochrome and
/// matte. The one circle is a flat control disc, never a lit orb.
struct WatchCaptureView: View {
    let model: WatchCaptureModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        ZStack {
            OceanTheme.abyss.ignoresSafeArea()
            switch model.stage {
            case .idle: idle
            case .starting: ProgressView().tint(OceanTheme.accent)
            case .recording: recording
            case .caught: caught
            case .denied: denied
            case .failed: failed
            case .nothingCaught: notice(Text("Nothing was caught"))
            }
        }
        .animation(.snappy, value: model.stage)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.sceneBecameActive() }
            } else {
                model.sceneBecameInactive()
            }
        }
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: 10) {
            Button { Task { await model.begin() } } label: { disc(symbol: "mic.fill") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Catch a thought"))
            statusLine
            if let title = model.lastTitle {
                Text("Last: \(title)")
                    .font(.footnote)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var statusLine: some View {
        switch model.statusLine {
        case .empty: EmptyView()
        case .waiting(let count): caption(Text("\(count) waiting for iPhone"))
        case .onItsWay: caption(Text("On its way"))
        case .inOcean: caption(Text("In your Ocean"))
        }
    }

    // MARK: Recording

    private var recording: some View {
        VStack(spacing: 10) {
            if !luminanceReduced {
                Text("Listening…")
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.mist)
                WatchWaveform(level: model.recorder.level)
                    .frame(height: 22)
            }
            Button { Task { await model.finish() } } label: { disc(symbol: "stop.fill") }
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction)   // Double Tap stops the take
                .accessibilityLabel(Text("Stop and catch"))
                .opacity(luminanceReduced ? 0 : 1)     // Always On dims to the timer alone
            Text(Self.timeString(model.recorder.elapsed))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(OceanTheme.foam.opacity(luminanceReduced ? 0.6 : 1))
        }
    }

    // MARK: Caught

    private var caught: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(OceanTheme.accent)
            Text("Caught")
                .font(.headline)
                .foregroundStyle(OceanTheme.foam)
            Button { model.undo() } label: { Text("Undo") }
                .font(.footnote.weight(.semibold))
                .tint(OceanTheme.accent)
                .accessibilityLabel(Text("Undo this take"))
        }
    }

    // MARK: Failure states

    private var denied: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.title3)
                .foregroundStyle(OceanTheme.mist)
            Text("Allow the microphone for Oryne in Settings on your watch.")
                .font(.footnote)
                .foregroundStyle(OceanTheme.foam)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var failed: some View {
        Button { Task { await model.begin() } } label: {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(OceanTheme.mist)
                Text("Couldn't start. Tap to try again.")
                    .font(.footnote)
                    .foregroundStyle(OceanTheme.foam)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func notice(_ text: Text) -> some View {
        text
            .font(.footnote)
            .foregroundStyle(OceanTheme.foam)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    // MARK: Pieces

    private func caption(_ text: Text) -> some View {
        text
            .font(.caption2)
            .foregroundStyle(OceanTheme.mist)
            .multilineTextAlignment(.center)
    }

    /// The flat control disc: matte fill, no rim light, no gloss.
    private func disc(symbol: String) -> some View {
        ZStack {
            Circle().fill(OceanTheme.current)
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(OceanTheme.foam)
        }
        .frame(width: 64, height: 64)
    }

    private static func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

/// The phone's listening waveform, scaled to the wrist. Reduce Motion stills
/// it to bars that follow the input level only.
private struct WatchWaveform: View {
    let level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<13, id: \.self) { i in
                    let swing = reduceMotion ? 0.6 : 0.3 + 0.7 * abs(sin(t * 4 + Double(i) * 0.5))
                    Capsule()
                        .fill(OceanTheme.accent.opacity(0.9))
                        .frame(width: 3, height: max(3, swing * (5 + level * 22)))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
```

- [ ] **Step 3: Create the watch string catalog**

Write `/tmp/watch-strings.json`:

```json
{
  "Catch a thought": "记一条灵感",
  "Stop and catch": "停止并接住",
  "Listening…": "聆听中…",
  "Caught": "接住了",
  "Undo": "撤销",
  "Undo this take": "撤销这一条",
  "%lld waiting for iPhone": "%lld 条在等 iPhone",
  "On its way": "正在汇入",
  "In your Ocean": "已汇入你的海洋",
  "Last: %@": "上一条：%@",
  "Couldn't start. Tap to try again.": "没能开始。轻点再试一次。",
  "Nothing was caught": "什么也没接住",
  "Allow the microphone for Oryne in Settings on your watch.": "请在手表的「设置」中允许 Oryne 使用麦克风。",
  "Start or stop a whisper on your wrist.": "在手腕上开始或停止一段语音。"
}
```

Run: `python3 -I Scripts/xcstrings-add/add.py OryneWatch/Resources/Localizable.xcstrings /tmp/watch-strings.json` → `added 14, skipped 0`.
Run: `grep -c "—\|–" OryneWatch/Resources/Localizable.xcstrings` → `0` (no em or en dashes).

- [ ] **Step 4: Replace `OryneWatch/Debug/WatchSelfTest.swift`**

```swift
#if DEBUG
import Foundation
import AVFoundation

/// Simulator checks driven by the launch environment (`SIMCTL_CHILD_` prefix
/// on `simctl launch --console-pty`). Each prints one line and exits.
///
/// - `recorder`: records two seconds; the file must decode with a nonzero duration.
/// - `sync`: WatchConnectivity must activate on the paired simulator.
/// - `flow`: toggle, two seconds, toggle; the take must be queued with its
///   file, held through the Undo window, then handed to WatchConnectivity.
/// - `undo`: toggle, two seconds, toggle, Undo; nothing may remain.
/// - `cap` (with `ORYNE_WATCH_CAP_SECONDS=2`): one toggle; the cap must end
///   and catch the take on its own.
@MainActor
enum WatchSelfTest {

    static func runIfRequested(model: WatchCaptureModel, cloudAvailable: Bool) {
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_SELFTEST"] {
        case "recorder": Task { await recorder() }
        case "sync": Task { await syncCheck(cloudAvailable: cloudAvailable) }
        case "flow": Task { await flow(model) }
        case "undo": Task { await undo(model) }
        case "cap": Task { await cap(model) }
        default: break
        }
    }

    private static func recorder() async {
        let recorder = WatchRecorder()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString).m4a")
        let start = await recorder.start(writingTo: url)
        guard start == .started else { report("RECORDER", "FAIL start=\(start)") }
        try? await Task.sleep(for: .seconds(2))
        guard let finished = await recorder.stop() else { report("RECORDER", "FAIL stop returned nil") }
        let decoded = (try? AVAudioPlayer(contentsOf: finished.url))?.duration ?? 0
        report("RECORDER", decoded > 1.5 ? "PASS duration=\(decoded)" : "FAIL duration=\(decoded)")
    }

    private static func syncCheck(cloudAvailable: Bool) async {
        let link = PhoneLink()
        link.activate()
        for _ in 0..<50 where !link.isActivated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        report("SYNC", link.isActivated
            ? "PASS activated=true cloud=\(cloudAvailable)"
            : "FAIL activated=false (is the watch simulator paired?)")
    }

    private static func recordTwoSeconds(_ model: WatchCaptureModel, name: String) async -> UUID {
        await model.toggle()
        guard model.stage == .recording else { report(name, "FAIL stage after first toggle=\(model.stage)") }
        try? await Task.sleep(for: .seconds(2))
        await model.toggle()
        guard case .caught(let id) = model.stage else { report(name, "FAIL stage after second toggle=\(model.stage)") }
        return id
    }

    private static func flow(_ model: WatchCaptureModel) async {
        let id = await recordTwoSeconds(model, name: "FLOW")
        guard FileManager.default.fileExists(atPath: model.queue.audioURL(for: id).path),
              model.queue.state.item(id)?.status == .onWatch,
              model.queue.state.item(id)?.phoneTransfer == .notSent
        else { report("FLOW", "FAIL take not queued and held") }
        try? await Task.sleep(for: .seconds(WatchCaptureModel.undoWindow + 1))
        guard let item = model.queue.state.item(id) else { report("FLOW", "FAIL take vanished") }
        report("FLOW", item.phoneTransfer == .pending && model.stage == .idle
            ? "PASS transfer=pending status=\(item.status.rawValue)"
            : "FAIL transfer=\(item.phoneTransfer.rawValue) stage=\(model.stage)")
    }

    private static func undo(_ model: WatchCaptureModel) async {
        let id = await recordTwoSeconds(model, name: "UNDO")
        model.undo()
        let fileGone = !FileManager.default.fileExists(atPath: model.queue.audioURL(for: id).path)
        report("UNDO", fileGone && model.queue.state.item(id) == nil && model.stage == .idle
            ? "PASS nothing remains"
            : "FAIL fileGone=\(fileGone) queued=\(model.queue.state.item(id) != nil)")
    }

    private static func cap(_ model: WatchCaptureModel) async {
        await model.toggle()
        guard model.stage == .recording else { report("CAP", "FAIL stage after toggle=\(model.stage)") }
        try? await Task.sleep(for: .seconds(WatchRecorder.cap + 2))
        guard case .caught = model.stage else { report("CAP", "FAIL stage after cap=\(model.stage)") }
        report("CAP", "PASS caught at the cap")
    }

    static func report(_ name: String, _ line: String) -> Never {
        print("\(name)_SELFTEST \(line)")
        exit(0)
    }
}
#endif
```

- [ ] **Step 5: Replace `OryneWatch/OryneWatchApp.swift`**

```swift
import SwiftUI

@main
struct OryneWatchApp: App {
    private let model: WatchCaptureModel

    init() {
        let queue = TakeQueue()
        let cloud = CloudInbox.makeIfAvailable()
        let sync = TakeSync(queue: queue, link: PhoneLink(), cloud: cloud)
        let model = WatchCaptureModel(queue: queue, sync: sync)
        self.model = model
        sync.start()
        #if DEBUG
        model.applyDemoEnvironment()
        WatchSelfTest.runIfRequested(model: model, cloudAvailable: cloud != nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchCaptureView(model: model)
        }
        .backgroundTask(.appRefresh(TakeSync.refreshIdentifier)) { [model] in
            await model.backgroundRefresh()
        }
    }
}
```

- [ ] **Step 6: Create `Scripts/watch-screens/run.sh`**

```bash
#!/usr/bin/env bash
# Screenshots every wrist screen on a watch simulator, in English and
# Chinese, through the DEBUG seams in WatchCaptureModel.applyDemoEnvironment.
# Read the PNGs: each screen must match spec §1 (flat disc, honest status
# line, no dashes in copy).
#
# Usage: Scripts/watch-screens/run.sh <watch-sim-udid> <out-dir> [path/to/OryneWatch.app]
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
UDID=${1:?watch simulator UDID}
OUT=${2:?output directory}
APP=${3:-build/DerivedData/Build/Products/Debug-watchsimulator/OryneWatch.app}
BUNDLE=com.inspireocean.app.watchkitapp
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant microphone "$BUNDLE"

shot() {   # shot <name> <language> [SIMCTL_CHILD_KEY=value ...]
  local name=$1 lang=$2
  shift 2
  env "$@" xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -AppleLanguages "($lang)" >/dev/null
  sleep 2
  xcrun simctl io "$UDID" screenshot "$OUT/$name-$lang.png" >/dev/null
}

for lang in en zh-Hans; do
  shot idle-empty     "$lang" SIMCTL_CHILD_ORYNE_WATCH_DEMO=empty
  shot idle-waiting   "$lang" SIMCTL_CHILD_ORYNE_WATCH_DEMO=waiting
  shot idle-onItsWay  "$lang" SIMCTL_CHILD_ORYNE_WATCH_DEMO=onItsWay
  shot idle-inOcean   "$lang" SIMCTL_CHILD_ORYNE_WATCH_DEMO=inOcean
  shot recording      "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=recording
  shot caught         "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=caught
  shot denied         "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=denied
  shot failed         "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=failed
  shot nothing        "$lang" SIMCTL_CHILD_ORYNE_WATCH_STAGE=nothing
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "Screens written to $OUT"
```

- [ ] **Step 7: Build and run the flow, Undo, and cap self-tests**

Run: `chmod +x Scripts/watch-screens/run.sh`, `xcodegen generate`, the watch build, the phone build → both `** BUILD SUCCEEDED **`.
Run (with both simulators booted and the watch app installed as in Task 10 Step 7):

```bash
xcrun simctl install $WATCH $DD/Build/Products/Debug-watchsimulator/OryneWatch.app
xcrun simctl privacy $WATCH grant microphone com.inspireocean.app.watchkitapp
SIMCTL_CHILD_ORYNE_WATCH_SELFTEST=flow xcrun simctl launch --console-pty --terminate-running-process $WATCH com.inspireocean.app.watchkitapp
SIMCTL_CHILD_ORYNE_WATCH_SELFTEST=undo xcrun simctl launch --console-pty --terminate-running-process $WATCH com.inspireocean.app.watchkitapp
SIMCTL_CHILD_ORYNE_WATCH_SELFTEST=cap SIMCTL_CHILD_ORYNE_WATCH_CAP_SECONDS=2 xcrun simctl launch --console-pty --terminate-running-process $WATCH com.inspireocean.app.watchkitapp
```

Expected, in order: `FLOW_SELFTEST PASS transfer=pending status=…`, `UNDO_SELFTEST PASS nothing remains`, `CAP_SELFTEST PASS caught at the cap`.

- [ ] **Step 8: Capture and read every screen**

Run: `Scripts/watch-screens/run.sh $WATCH /tmp/oryne-watch-screens`
Open each PNG (Read tool). Check, in both languages:
- `idle-empty`: disc only, no status line, no "Last".
- `idle-waiting`: "2 waiting for iPhone" / "2 条在等 iPhone" and "Last: Lighthouse café".
- `idle-onItsWay`: "On its way"; `idle-inOcean`: "In your Ocean"; both with the last title.
- `recording`: "Listening…", waveform, flat stop disc, timer.
- `caught`: checkmark, "Caught", "Undo".
- `denied`, `failed`, `nothing`: the one line each, readable on black.
- No glossy or lit circles; no em or en dashes anywhere.

- [ ] **Step 9: Commit**

```bash
git add OryneWatch Scripts/watch-screens
git commit -m "Watch: catch, hold for Undo, and say honestly where each take is"
```

---

### Task 12: Triggers: Action Button and Siri intent, complication, deep link

**Files:**
- Create: `OryneWatch/Intents/CatchThoughtIntent.swift`
- Modify: `OryneWatch/OryneWatchApp.swift` (full replacement)
- Create: `OryneWatchWidgets/OryneWatchWidgetsBundle.swift`, `OryneWatchWidgets/CatchComplication.swift`, `OryneWatchWidgets/Localizable.xcstrings` (through the helper)
- Modify: `project.yml` (add `OryneWatchWidgets`; embed it in `OryneWatch`)
- Generated and committed: `OryneWatchWidgets/Info.plist`

**Interfaces:**
- Consumes: `WatchCaptureModel.toggle()` (Task 11); `WatchDeepLink` (Task 1).
- Produces: `struct CatchThoughtIntent: AppIntent` (`openAppWhenRun = true`, `@Dependency var model: WatchCaptureModel`); `struct OryneWatchShortcuts: AppShortcutsProvider`; widget kind `OryneCatch`.

- [ ] **Step 1: Create `OryneWatch/Intents/CatchThoughtIntent.swift`**

```swift
import AppIntents

/// The one intent behind the Action Button (through its Shortcut slot) and
/// Siri. Implemented in the watch app itself, not an extension, as Apple
/// requires for Action Button intents. Idle or Caught → record; recording →
/// stop and catch.
struct CatchThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Catch a thought"
    static let description = IntentDescription("Start or stop a whisper on your wrist.")
    static let openAppWhenRun = true

    @Dependency private var model: WatchCaptureModel

    @MainActor
    func perform() async throws -> some IntentResult {
        await model.toggle()
        return .result()
    }
}

struct OryneWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // "Catch this in Oryne" belongs to iPhone Fast Capture
        // (Oryne/Intents/CaptureIntents.swift); these phrases must not collide.
        AppShortcut(
            intent: CatchThoughtIntent(),
            phrases: [
                "Whisper to \(.applicationName)",
                "Record a thought in \(.applicationName)"
            ],
            shortTitle: "Catch a thought",
            systemImageName: "waveform"
        )
    }
}
```

- [ ] **Step 2: Replace `OryneWatch/OryneWatchApp.swift`**

```swift
import SwiftUI
import AppIntents

@main
struct OryneWatchApp: App {
    private let model: WatchCaptureModel

    init() {
        let queue = TakeQueue()
        let cloud = CloudInbox.makeIfAvailable()
        let sync = TakeSync(queue: queue, link: PhoneLink(), cloud: cloud)
        let model = WatchCaptureModel(queue: queue, sync: sync)
        self.model = model
        // The Action Button and Siri reach the same model the screen shows.
        AppDependencyManager.shared.add { model }
        sync.start()
        #if DEBUG
        model.applyDemoEnvironment()
        WatchSelfTest.runIfRequested(model: model, cloudAvailable: cloud != nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchCaptureView(model: model)
                .onOpenURL { url in
                    // The complication: same rule as the Action Button.
                    guard WatchDeepLink.isCatch(url) else { return }
                    Task { await model.toggle() }
                }
        }
        .backgroundTask(.appRefresh(TakeSync.refreshIdentifier)) { [model] in
            await model.backgroundRefresh()
        }
    }
}
```

- [ ] **Step 3: Create the complication extension**

`OryneWatchWidgets/OryneWatchWidgetsBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct OryneWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CatchComplication()
    }
}
```

`OryneWatchWidgets/CatchComplication.swift`:

```swift
import WidgetKit
import SwiftUI

/// A static launcher (spec §1): one tap opens Oryne already listening. It
/// shows no queue status; that lives on the idle screen.
struct CatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OryneCatch", provider: CatchProvider()) { _ in
            CatchComplicationView()
        }
        .configurationDisplayName("Catch a thought")
        .description("Opens Oryne, already listening.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

struct CatchEntry: TimelineEntry {
    let date: Date
}

struct CatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> CatchEntry {
        CatchEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CatchEntry) -> Void) {
        completion(CatchEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatchEntry>) -> Void) {
        completion(Timeline(entries: [CatchEntry(date: .now)], policy: .never))
    }
}

struct CatchComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(WatchDeepLink.catchURL)
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text("Catch a thought")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCorner:
            Image(systemName: "waveform")
                .font(.title3)
                .widgetLabel { Text(verbatim: "Oryne") }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform")
                    .font(.title3)
            }
        }
    }
}
```

Write `/tmp/widget-strings.json`:

```json
{
  "Catch a thought": "记一条灵感",
  "Opens Oryne, already listening.": "打开 Oryne，即刻开始聆听。"
}
```

Run: `python3 -I Scripts/xcstrings-add/add.py OryneWatchWidgets/Localizable.xcstrings /tmp/widget-strings.json` → `added 2, skipped 0`.

- [ ] **Step 4: Add the widget target to `project.yml`**

In the `OryneWatch` target, add a `dependencies:` block (after `sources:`):

```yaml
    dependencies:
      - target: OryneWatchWidgets
        embed: true
```

Append this target at the end of `targets:`:

```yaml
  # Watch face complications and the Smart Stack: static launchers into a
  # hot mic (oryne://watch/catch). No App Group or iCloud: they show no data.
  OryneWatchWidgets:
    type: app-extension
    platform: watchOS
    sources:
      - path: OryneWatchWidgets
      - path: Shared/Watch/WatchDeepLink.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.inspireocean.app.watchkitapp.widgets
    info:
      path: OryneWatchWidgets/Info.plist
      properties:
        CFBundleDisplayName: Oryne
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        CFBundleLocalizations:
          - en
          - zh-Hans
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

- [ ] **Step 5: Build, check the embedding, and test the deep link**

Run: `xcodegen generate`, the watch build, the phone build → both `** BUILD SUCCEEDED **`.
Run: `ls $DD/Build/Products/Debug-watchsimulator/OryneWatch.app/PlugIns` → `OryneWatchWidgets.appex`.
Run:

```bash
xcrun simctl install $WATCH $DD/Build/Products/Debug-watchsimulator/OryneWatch.app
xcrun simctl privacy $WATCH grant microphone com.inspireocean.app.watchkitapp
xcrun simctl launch --terminate-running-process $WATCH com.inspireocean.app.watchkitapp
xcrun simctl openurl $WATCH oryne://watch/catch
```

Wait two seconds, then `xcrun simctl io $WATCH screenshot /tmp/oryne-watch-deeplink.png` and read it: the recording screen ("Listening…", timer running). Run `xcrun simctl openurl $WATCH oryne://watch/catch` again, screenshot: "Caught" with "Undo".
Run: the flow self-test from Task 11 Step 7 again → `FLOW_SELFTEST PASS …` (the intent dependency doesn't change the model).
The Action Button and Siri paths are device only; Task 13 adds them to the checklist.

- [ ] **Step 6: Commit**

```bash
git add OryneWatch OryneWatchWidgets project.yml
git commit -m "Watch: Action Button and Siri intent, complication, and deep link"
```

---

### Task 13: Phone setup card, phone strings, and the device checklist

**Files:**
- Modify: `Oryne/Features/FastCapture/FastCaptureSettingsView.swift` (add `watchSection`)
- Modify: `Oryne/Resources/Localizable.xcstrings` (through the helper)
- Modify: `docs/HARDWARE_CHECKLIST.md` (append an Apple Watch section)
- Modify: `docs/KNOWN_ISSUES.md` (replace the watchOS Phase 1 entry)

**Interfaces:**
- Consumes: `GlassCard`, `settingsHeader(title:subtitle:systemImage:)`, `FastCaptureSetupStep(number:title:)` (existing, same file).
- Produces: nothing new for code.

- [ ] **Step 1: Add the Apple Watch card to `FastCaptureSettingsView.swift`**

In `body`, under `setupSection`, add `watchSection`:

```swift
                        shortcutSection
                        inputSection
                        setupSection
                        watchSection
```

Add below `setupSection` (before `settingsHeader`):

```swift
    /// The Ultra's Action Button reaches Oryne through its Shortcut slot:
    /// watchOS lists only workout and dive apps there directly. Confirmed on
    /// device per docs/HARDWARE_CHECKLIST.md › Apple Watch.
    private var watchSection: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeader(
                    title: String(localized: "Apple Watch"),
                    subtitle: "Catch a whisper from your wrist.",
                    systemImage: "applewatch"
                )

                VStack(spacing: 10) {
                    ForEach(Array(Self.watchSteps.enumerated()), id: \.offset) { index, title in
                        FastCaptureSetupStep(number: index + 1, title: title)
                    }
                }

                Text("No Action Button? Add the Oryne complication to a watch face.")
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
    }

    private static var watchSteps: [String] {
        [
            String(localized: "Settings on your watch"),
            String(localized: "Action Button"),
            String(localized: "Shortcut"),
            String(localized: "Catch a thought")
        ]
    }
```

- [ ] **Step 2: Add the phone strings**

Write `/tmp/phone-strings.json` (existing keys such as "Action Button" and "Shortcut" are skipped automatically):

```json
{
  "Apple Watch": "Apple Watch",
  "Catch a whisper from your wrist.": "在手腕上记一段语音。",
  "Settings on your watch": "手表上的「设置」",
  "Action Button": "操作按钮",
  "Shortcut": "快捷指令",
  "Catch a thought": "记一条灵感",
  "No Action Button? Add the Oryne complication to a watch face.": "没有操作按钮？把 Oryne 复杂功能添加到表盘上。"
}
```

Run: `python3 -I Scripts/xcstrings-add/add.py Oryne/Resources/Localizable.xcstrings /tmp/phone-strings.json` → `added 5, skipped 2`.
Run: `git diff --stat Oryne/Resources/Localizable.xcstrings` → only additions in that file.

- [ ] **Step 3: Append the Apple Watch section to `docs/HARDWARE_CHECKLIST.md`**

```markdown

## Apple Watch

Signed build on a real watch paired with a real iPhone. Simulator cannot
deliver WatchConnectivity files, press the Action Button, or prove
wrist-down recording.

- [ ] **Action Button setup** — on an Ultra: Settings › Action Button ›
  Shortcut. Confirm "Catch a thought" can be chosen directly; if it must be
  wrapped in a user shortcut, update the setup card in Fast Capture settings
  and this item. A press opens Oryne recording.
- [ ] **Second press stops** — press the Action Button again while recording:
  the take is caught. If the press doesn't reach the app, record that, and
  the setup card must say stop with a tap or Double Tap.
- [ ] **Double Tap stop** — Series 9+ or Ultra 2+: Double Tap while recording
  catches the take.
- [ ] **Wrist down keeps recording** — start a take, lower the wrist, keep
  talking 20 s, raise, stop: the take holds all of it. If recording stops
  when the app suspends, fall back to "wrist down ends the take" (spec §9.3).
- [ ] **Always On** — wrist down while recording shows the timer alone.
- [ ] **5 minute cap** — a haptic and the take is caught at 5:00.
- [ ] **Call mid take** — a call ends and catches the take; no stuck screen.
- [ ] **Delivery with the phone app force quit** — catch a take with Oryne
  force quit on the phone, phone nearby: within a minute the thought is in
  Library (does the wake ping deliver the file?). Record the latency.
- [ ] **iCloud fallback** — phone in airplane mode, watch on Wi-Fi or LTE:
  catch a take; the watch says "On its way"; turn the phone back on; the
  thought arrives and the watch says "In your Ocean" with its title.
- [ ] **Both paths, one thought** — catch a take that goes over both paths:
  exactly one thought in Library; the iCloud record is gone afterwards.
- [ ] **Undo** — Undo within 5 s: nothing reaches the phone or iCloud.
- [ ] **Microphone denied** — deny on first use: the one-line message, no
  loop; allow in Settings, return: the idle screen is back. Confirm the
  Settings path the message names.
- [ ] **SwiftData sync unaffected** — after installing this build (it adds an
  app delegate for the inbox push), run the CloudKit two-device sync item
  above again.
- [ ] **Production schema** — before release, deploy the `WatchTake` record
  type in CloudKit Console (development creates it on first write).
```

- [ ] **Step 4: Replace the Phase 1 entry in `docs/KNOWN_ISSUES.md`**

Replace the section headed `## 2026-06-28 — watchOS Phase 1 (committed on \`feat/watchos-quick-capture\`)` and its bullet with:

```markdown
## 2026-10-18 — Apple Watch capture (branch `am/oryne-apple-watch-app-177fc5`)

- Built from the 2026-10-18 spec; supersedes `feat/watchos-quick-capture`,
  which is not to be merged (its icon was copied). Simulator verified:
  recorder, queue, Undo, cap, screens in both languages, deep link, and the
  phone import end to end (`Scripts/watch-inbox-e2e`).
- Still owes the device pass in `docs/HARDWARE_CHECKLIST.md` › Apple Watch:
  Action Button second press, wake ping delivery, wrist-down recording, and
  the iCloud fallback cannot be proven in Simulator.
- Chinese strings for the watch are drafts (`needs_review`).
```

- [ ] **Step 5: Build, test, and look at the card**

Run: the phone build → `** BUILD SUCCEEDED **`; the full unit test command → `** TEST SUCCEEDED **`; `Scripts/watch-inbox-e2e/run.sh $PHONE` → both `PASS` lines.
Open Fast Capture settings on the phone simulator (Capture tab → Fast Capture settings) and screenshot with `xcrun simctl io $PHONE screenshot /tmp/oryne-fastcapture-watch.png`; read it: the Apple Watch card sits under the setup card, steps numbered 1 to 4, the complication line beneath, no dashes.

- [ ] **Step 6: Commit**

```bash
git add Oryne/Features/FastCapture/FastCaptureSettingsView.swift Oryne/Resources/Localizable.xcstrings docs/HARDWARE_CHECKLIST.md docs/KNOWN_ISSUES.md
git commit -m "Watch: setup card on the phone and the device checklist"
```

---

## Spec coverage

| Spec section | Tasks |
|---|---|
| §1 Entry points (Action Button, complication, Siri, icon) | 12 (intent, complication, deep link), 11 (icon opens idle) |
| §1 Recording (disc, waveform, stop, wrist down, cap, interruptions, 0.6 s) | 9 (recorder, background audio), 11 (model, view) |
| §1 Caught and Undo | 11 |
| §1 Idle status line and last title | 2 (rules), 11 (view) |
| §1 Failure states and copy | 11; zh drafts 9, 11, 12, 13 |
| §2 One ID, wire format, CloudKit schema | 1 |
| §2 Watch queue and both paths | 2, 4, 10 |
| §2 Import exactly once, paired iPhone only | 3, 6, 8 |
| §2 Confirmation back to the watch | 7, 10 |
| §2 Release task (production schema) | 13 (checklist) |
| §3 WatchLink, reader, importer, sweep, VoiceUnderstanding, no schema change, setup help, packaging | 5, 6, 7, 8, 9, 13 |
| §5 Failure handling | 6 (refused save, duplicates, empty), 9 (finalize, start failure), 10 (retries), 11 (nothing caught, denied recovery) |
| §6 Testing | Unit tests 1 to 4; simulator self-tests 9 to 12; e2e script 6; device checklist 13 |
| §8 Porting Phase 1 and its defects | 9 (main-actor recorder, awaited finalize, double start guard, session deactivation), 11 (denied recovery, Always On, VoiceOver labels, intent entries record) |
| §9 Device unknowns | 13 (each is a checklist item with its fallback) |
