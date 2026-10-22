# Composer images and link sensing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the capture composer a + that attaches photos (latest-photos strip, Camera, All Photos) shown as thumbnails in the card, and sense links in the typed words so the first one becomes the thought's link card.

**Architecture:** A pure `LinkSensing` (Shared, unit-tested) finds, chooses and lifts links; `NodeKind.captured` names a release from what it holds. The composer (`FastCaptureSessionView`) keeps its pictures as `CaptureImage`s (bytes plus a thumbnail decoded once), shows them and the sensed link in a new `CaptureAttachments` row, and opens a new `CaptureAttachSheet`. `CaptureSession.release` lifts edge links from the words and starts link enrichment. The model is unchanged.

**Tech Stack:** SwiftUI (iOS 18 target, iOS 26 SDK), PhotosUI embedded `PhotosPicker`, `UIImagePickerController`, `NSDataDetector`, SwiftData, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-22-composer-images-and-links-design.md`

## Global Constraints

- Work only in `/Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138` (branch `am/image-link-input-318138`). Never `cd` to the main checkout.
- iOS deployment target 18.0; `SWIFT_VERSION` 5.0. Nothing above iOS 18 without `#available`.
- The `.xcodeproj` is generated and gitignored: run `xcodegen generate` after adding a file or editing `project.yml`.
- Every Xcode command is prefixed `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, builds into `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/oryne-image-link` (outside iCloud-synced `~/Documents`, or codesign fails), and appends `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES`.
- Every git command is `git -c core.trustctime=false -c core.checkStat=minimal …` (iCloud eviction makes plain `git status` hang). Commit messages are plain sentences with no attribution lines.
- Simulator: only the throwaway **"Oryne attach test"** (iPhone 17 Pro, iOS 26.5), created in Task 1. Never boot, install on or erase other simulators: other sessions use them.
- `SharedTests` compiles `Shared/` straight into the test bundle: test files `import XCTest` and `Foundation`, never `@testable import Oryne`.
- UI copy has no em or en dashes (use a comma, colon or period). The String Catalog `Oryne/Resources/Localizable.xcstrings` is value-as-key: the English literal is the key, and every new key gets a zh-Hans translation.
- No change to any `@Model` (no CloudKit schema redeploy).
- Visual rules: Liquid Glass only on the floating layer (the card, discs); content tiles are a flat fill (white 8%), never gradients; controls are 44 pt; the card's open corner radius is `FastCaptureLayout.cardRadius` (24) with a 12 pt inset (`FastCaptureLayout.cardInset`).

## File Structure

| File | Responsibility |
|---|---|
| `Shared/Services/LinkSensing.swift` (new) | Find http(s) links in words, choose the one a release attaches, lift it from the words at an edge. Pure. |
| `Shared/Models/Enums.swift` | `NodeKind.captured(voice:words:images:link:)`: a release's kind from what it holds. |
| `SharedTests/LinkSensingTests.swift`, `SharedTests/CaptureKindTests.swift` (new) | Unit tests for the two above. |
| `Oryne/Services/ImageDownsampler.swift` | Gains `image(_:maxPixel:)` (a decoded, size-capped `UIImage`); `downsample` uses it. |
| `Oryne/Features/FastCapture/CaptureAttachments.swift` (new) | `CaptureImage` (bytes plus thumbnail) and the card's attachments row (thumbnails, loading tiles, link tile, ✕ badges). |
| `Oryne/Features/FastCapture/CaptureAttachSheet.swift` (new) | The + sheet (embedded latest-photos strip, Camera, All Photos) and `CameraPicker`. |
| `Oryne/Features/FastCapture/FastCaptureSessionView.swift` | The composer: pictures, +, the row, presenting the sheet, camera and library, sensing the link, what a release carries. |
| `Oryne/Features/FastCapture/CaptureControl.swift` | `ParkedCapture` keeps pictures and link dismissals; its bar line. |
| `Oryne/Services/CaptureSession.swift` | `CaptureDraft` (pictures, link, dismissals); `release` lifts and names; `beginUnderstanding` starts link enrichment. |
| `project.yml` | `NSCameraUsageDescription`. |
| `Oryne/Resources/Localizable.xcstrings` | New keys `%lld images`, `Camera`, `All Photos`; `Remove screenshot` pruned. |

---

### Task 1: Link sensing and the capture kind

**Files:**
- Create: `Shared/Services/LinkSensing.swift`
- Modify: `Shared/Models/Enums.swift` (append an extension at the end of the file)
- Test: `SharedTests/LinkSensingTests.swift`, `SharedTests/CaptureKindTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum LinkSensing` with `struct Sensed: Equatable { let urlString: String; let range: Range<String.Index>; var host: String }`, `static func links(in text: String) -> [Sensed]`, `static func chosen(in text: String, dismissed: Set<String> = []) -> Sensed?`, `static func words(_ text: String, lifting urlString: String?) -> String`.
  - `extension NodeKind { static func captured(voice: Bool, words: String, images: Int, link: Bool) -> NodeKind }`.

- [ ] **Step 1: Create the test simulator (once for the whole plan)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices | grep -q "Oryne attach test" \
  || DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl create "Oryne attach test" \
       com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices | grep "Oryne attach test"
```

Expected: one line, `Oryne attach test (<UDID>) (Shutdown)`.

- [ ] **Step 2: Write the failing link sensing tests**

Create `SharedTests/LinkSensingTests.swift`:

```swift
import XCTest
import Foundation

/// Unit tests for `LinkSensing`: which links the composer senses, which one
/// a release attaches, and when the link leaves the words.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class LinkSensingTests: XCTestCase {

    // MARK: Finding

    func testFindsAFullURL() {
        XCTAssertEqual(
            LinkSensing.links(in: "https://www.nytimes.com/2026/10/20/arts/story.html").map(\.urlString),
            ["https://www.nytimes.com/2026/10/20/arts/story.html"]
        )
    }

    func testABareDomainGetsHTTPS() {
        XCTAssertEqual(
            LinkSensing.links(in: "check this nytimes.com/2026/10/20/story later").map(\.urlString),
            ["https://nytimes.com/2026/10/20/story"]
        )
        XCTAssertEqual(
            LinkSensing.links(in: "www.are.na/block/12345").map(\.urlString),
            ["https://www.are.na/block/12345"]
        )
    }

    func testATypedHTTPStaysHTTP() {
        XCTAssertEqual(
            LinkSensing.links(in: "old site http://example.com/page").map(\.urlString),
            ["http://example.com/page"]
        )
    }

    func testEmailsAreNotLinks() {
        XCTAssertTrue(LinkSensing.links(in: "email me at me@example.com").isEmpty)
    }

    func testFileNamesAndAbbreviationsAreNotLinks() {
        XCTAssertTrue(LinkSensing.links(in: "sunset.jpg looks nice, 3.5x brighter, e.g. this").isEmpty)
    }

    func testTheHostDropsWWW() {
        XCTAssertEqual(LinkSensing.links(in: "www.are.na/block/12345").first?.host, "are.na")
    }

    // MARK: Choosing

    func testTheFirstLinkIsChosen() {
        XCTAssertEqual(
            LinkSensing.chosen(in: "two links: https://a.com and https://b.org/page")?.urlString,
            "https://a.com"
        )
    }

    func testADismissedLinkGivesWayToTheNext() {
        XCTAssertEqual(
            LinkSensing.chosen(
                in: "two links: https://a.com and https://b.org/page",
                dismissed: ["https://a.com"]
            )?.urlString,
            "https://b.org/page"
        )
    }

    func testNothingIsChosenWhenEveryLinkIsDismissed() {
        XCTAssertNil(LinkSensing.chosen(in: "only https://a.com", dismissed: ["https://a.com"]))
    }

    // MARK: Lifting

    func testALinkAtTheEndLeavesTheWords() {
        XCTAssertEqual(
            LinkSensing.words("Love this palette https://are.na/b/42", lifting: "https://are.na/b/42"),
            "Love this palette"
        )
    }

    func testATrailingLinkTakesItsSentenceEnd() {
        XCTAssertEqual(LinkSensing.words("see https://a.com.", lifting: "https://a.com"), "see")
        XCTAssertEqual(
            LinkSensing.words("看这个 https://www.bilibili.com/video/BV1xx 。", lifting: "https://www.bilibili.com/video/BV1xx"),
            "看这个"
        )
    }

    func testATrailingLinkTakesWhatJoinedIt() {
        XCTAssertEqual(LinkSensing.words("Great read - https://a.com", lifting: "https://a.com"), "Great read")
        XCTAssertEqual(
            LinkSensing.words("Love this: https://are.na/b/42", lifting: "https://are.na/b/42"),
            "Love this"
        )
        XCTAssertEqual(
            LinkSensing.words("看这个：https://www.bilibili.com/video/BV1xx", lifting: "https://www.bilibili.com/video/BV1xx"),
            "看这个"
        )
    }

    func testAQuestionBeforeATrailingLinkKeepsItsMark() {
        XCTAssertEqual(LinkSensing.words("Is this real? https://a.com", lifting: "https://a.com"), "Is this real?")
    }

    func testALinkAtTheStartLeavesTheWords() {
        XCTAssertEqual(LinkSensing.words("https://a.com, great read", lifting: "https://a.com"), "great read")
        XCTAssertEqual(LinkSensing.words("https://a.com\nGreat read", lifting: "https://a.com"), "Great read")
    }

    func testALinkMidSentenceStays() {
        let words = "read https://x.com/someone/status/123 before friday"
        XCTAssertEqual(LinkSensing.words(words, lifting: "https://x.com/someone/status/123"), words)
    }

    func testAChineseLinkMidSentenceStays() {
        let words = "小红书链接 xhslink.com/a/AbC123，复制后打开"
        XCTAssertEqual(LinkSensing.words(words, lifting: "https://xhslink.com/a/AbC123"), words)
    }

    func testOnlyALinkLeavesNoWords() {
        XCTAssertEqual(LinkSensing.words("  https://are.na/b/42 \n", lifting: "https://are.na/b/42"), "")
    }

    func testABareDomainIsLiftedByItsHTTPSForm() {
        XCTAssertEqual(
            LinkSensing.words("check nytimes.com/2026/10/20/story", lifting: "https://nytimes.com/2026/10/20/story"),
            "check"
        )
    }

    func testOnlyTheChosenOfTwoLinksIsLifted() {
        XCTAssertEqual(LinkSensing.words("https://a.com https://b.com", lifting: "https://a.com"), "https://b.com")
    }

    func testWithoutALinkTheWordsAreOnlyTrimmed() {
        XCTAssertEqual(LinkSensing.words("  hello  ", lifting: nil), "hello")
        XCTAssertEqual(LinkSensing.words("hello", lifting: "https://a.com"), "hello")
    }
}
```

- [ ] **Step 3: Write the failing capture kind tests**

Create `SharedTests/CaptureKindTests.swift`:

```swift
import XCTest
import Foundation

/// Unit tests for `NodeKind.captured`: the kind a capture release gives a
/// thought from what it holds.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class CaptureKindTests: XCTestCase {

    func testARecordingIsAWhisperWhateverRidesAlong() {
        XCTAssertEqual(NodeKind.captured(voice: true, words: "", images: 2, link: true), .voice)
    }

    func testWordsMakeAThought() {
        XCTAssertEqual(NodeKind.captured(voice: false, words: "Love this palette", images: 1, link: true), .text)
    }

    func testPicturesWithoutWordsMakeAnImage() {
        XCTAssertEqual(NodeKind.captured(voice: false, words: "  \n", images: 1, link: true), .image)
    }

    func testALinkAloneMakesALink() {
        XCTAssertEqual(NodeKind.captured(voice: false, words: "", images: 0, link: true), .link)
    }

    func testNothingFallsBackToAThought() {
        XCTAssertEqual(NodeKind.captured(voice: false, words: "", images: 0, link: false), .text)
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Oryne.xcodeproj -scheme Oryne \
  -destination 'platform=iOS Simulator,name=Oryne attach test' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/oryne-image-link \
  -only-testing:SharedTests/LinkSensingTests -only-testing:SharedTests/CaptureKindTests \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head -20
```

Expected: `error: cannot find 'LinkSensing' in scope` and `error: type 'NodeKind' has no member 'captured'`, then `** TEST FAILED **`.

- [ ] **Step 5: Implement `LinkSensing`**

Create `Shared/Services/LinkSensing.swift`:

```swift
import Foundation

/// Links in what the user typed, sensed rather than entered: the composer
/// has no link field. The first web link the user hasn't dismissed becomes
/// the thought's link. At the start or end of the words it leaves them (its
/// card carries it); in the middle of a sentence it stays.
enum LinkSensing {

    /// One web link in the words.
    struct Sensed: Equatable {
        /// What the thought stores: a link typed without a scheme gets https.
        let urlString: String
        /// Where it sits in the words it was found in.
        let range: Range<String.Index>

        /// The site's name for the composer's tile, without "www.".
        var host: String {
            let host = URL(string: urlString)?.host ?? urlString
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    /// Every http and https link in `text`, in order. Emails and other
    /// schemes are not links here.
    static func links(in text: String) -> [Sensed] {
        let whole = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: whole).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let range = Range(match.range, in: text) else { return nil }
            let typed = text[range].lowercased()
            var urlString = url.absoluteString
            // A bare domain comes back as http; the web is https now.
            if !typed.hasPrefix("http://"), !typed.hasPrefix("https://"), urlString.hasPrefix("http://") {
                urlString = "https://" + urlString.dropFirst("http://".count)
            }
            return Sensed(urlString: urlString, range: range)
        }
    }

    /// The link a release attaches: the first one the user hasn't dismissed.
    static func chosen(in text: String, dismissed: Set<String> = []) -> Sensed? {
        links(in: text).first { !dismissed.contains($0.urlString) }
    }

    /// The words a thought keeps, trimmed. When `urlString` sits at their
    /// start or end it leaves them, with the punctuation that joined it to
    /// them; anywhere else the words keep it.
    static func words(_ text: String, lifting urlString: String?) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlString,
              let link = links(in: text).first(where: { $0.urlString == urlString }) else { return text }
        let before = text[..<link.range.lowerBound]
        let after = text[link.range.upperBound...]
        if before.allSatisfy(\.isWhitespace) {
            return String(after.drop { $0.isWhitespace || joints.contains($0) })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if after.allSatisfy({ $0.isWhitespace || sentenceEnds.contains($0) }) {
            var kept = before
            while let last = kept.last, last.isWhitespace || joints.contains(last) { kept.removeLast() }
            return String(kept)
        }
        return text
    }

    /// What ends a sentence after a link at the end of the words.
    private static let sentenceEnds: Set<Character> = [".", ",", ";", "!", "?", "…", "。", "，", "；", "！", "？"]
    /// What joins a link to the words beside it ("Great read - link",
    /// "link, great read", "看这个：link").
    private static let joints: Set<Character> = ["-", "–", "—", "|", "·", ":", "：", ",", "，", ";", "；"]

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}
```

- [ ] **Step 6: Implement `NodeKind.captured`**

Append to the end of `Shared/Models/Enums.swift`:

```swift

extension NodeKind {
    /// What a captured thought is, from what it holds: a recording makes a
    /// whisper and words a thought; with neither, its pictures name it, then
    /// its link. The kind follows what happened, never a choice.
    static func captured(voice: Bool, words: String, images: Int, link: Bool) -> NodeKind {
        if voice { return .voice }
        if !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text }
        if images > 0 { return .image }
        if link { return .link }
        return .text
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass, then the whole suite**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Oryne.xcodeproj -scheme Oryne \
  -destination 'platform=iOS Simulator,name=Oryne attach test' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/oryne-image-link \
  -only-testing:SharedTests CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES 2>&1 | grep -E "error:|failed|Executed|TEST (SUCCEEDED|FAILED)" | tail -8
```

Expected: `** TEST SUCCEEDED **`, with `Executed` counts including the 25 new tests (20 link sensing, 5 kind) and 0 failures.

- [ ] **Step 8: Commit**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && \
git -c core.trustctime=false -c core.checkStat=minimal add Shared/Services/LinkSensing.swift Shared/Models/Enums.swift SharedTests/LinkSensingTests.swift SharedTests/CaptureKindTests.swift && \
git -c core.trustctime=false -c core.checkStat=minimal commit -q -m "Link sensing: find, choose and lift a link from typed words; a capture's kind from what it holds" && \
git log --oneline -1
```

---

### Task 2: Pictures on the composer's card

The composer's one screenshot slot becomes a list of pictures shown as 64 pt thumbnails at the top of the card, each removable, kept through parking, whispers and Undo. The Action Button screenshot is the first thumbnail. (Adding pictures from Photos comes in Task 3.)

**Files:**
- Modify: `Oryne/Services/ImageDownsampler.swift`
- Create: `Oryne/Features/FastCapture/CaptureAttachments.swift`
- Modify: `Oryne/Features/FastCapture/CaptureControl.swift` (`ParkedCapture`, lines 82-97)
- Modify: `Oryne/Services/CaptureSession.swift` (`CaptureDraft` lines 11-40, `release` lines 122-155)
- Modify: `Oryne/Features/FastCapture/FastCaptureSessionView.swift`
- Modify: `Oryne/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `NodeKind.captured(voice:words:images:link:)` (Task 1).
- Produces:
  - `ImageDownsampler.image(_ data: Data, maxPixel: CGFloat) -> UIImage?`
  - `struct CaptureImage: Identifiable { let id: UUID; let data: Data; let thumbnail: UIImage; init?(data: Data); static func make(from datas: [Data]) async -> [CaptureImage] }`
  - `struct CaptureAttachments: View` with `init(images: [CaptureImage], pending: Int = 0, onRemoveImage: @escaping (CaptureImage.ID) -> Void)`
  - `ParkedCapture(text: String, images: [CaptureImage] = [], heldDraft: CaptureDraft?)`
  - `CaptureDraft.imageDatas: [Data]` (the single `imageData` is gone)
  - In `FastCaptureSessionView`: `@State private var images: [CaptureImage]`, `private func removeImage(_ id: CaptureImage.ID)`

- [ ] **Step 1: Give `ImageDownsampler` a decoded, size-capped image**

In `Oryne/Services/ImageDownsampler.swift`, replace:

```swift
    static func downsample(_ data: Data, maxPixel: CGFloat, quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }
```

with:

```swift
    static func downsample(_ data: Data, maxPixel: CGFloat, quality: CGFloat = 0.8) -> Data? {
        image(data, maxPixel: maxPixel)?.jpegData(compressionQuality: quality)
    }

    /// The picture in `data`, decoded upright and no larger than `maxPixel`
    /// on its longest edge (ImageIO never decodes the full image). Nil when
    /// the bytes aren't a picture.
    static func image(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
```

- [ ] **Step 2: Create the attachments row**

Create `Oryne/Features/FastCapture/CaptureAttachments.swift`:

```swift
import SwiftUI

/// One picture on the composer's card: the bytes a release keeps and the
/// small image the card shows. The thumbnail is decoded once, when the
/// picture is added, so typing never decodes a photo again.
struct CaptureImage: Identifiable {
    let id = UUID()
    let data: Data
    let thumbnail: UIImage

    /// A tile's 64 pt at 3x.
    static let thumbnailPixels: CGFloat = 192

    /// Nil when the bytes aren't a picture ImageIO can read.
    init?(data: Data) {
        guard let thumbnail = ImageDownsampler.image(data, maxPixel: Self.thumbnailPixels) else { return nil }
        self.data = data
        self.thumbnail = thumbnail
    }

    /// Several pictures, decoded off the main actor, in order; any that
    /// can't be read are left out.
    static func make(from datas: [Data]) async -> [CaptureImage] {
        await Task.detached { datas.compactMap(CaptureImage.init(data:)) }.value
    }
}

/// What rides on the composer's card above the words: its pictures, and a
/// quiet tile for each one still loading. Square tiles of 64 pt whose
/// corners sit concentric with the card's, each with its own ✕. The row
/// scrolls sideways once it is wider than the card.
struct CaptureAttachments: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm

    let images: [CaptureImage]
    /// Pictures picked but not yet loaded.
    var pending = 0
    var onRemoveImage: (CaptureImage.ID) -> Void

    static let tileSize: CGFloat = 64
    /// The card's corner less its inset, so the tiles sit concentric.
    static let tileRadius: CGFloat = FastCaptureLayout.cardRadius - FastCaptureLayout.cardInset

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
    }

    /// Reduce Motion: tiles fade in place instead of growing in.
    private var arrival: AnyTransition {
        reduceMotion || calm ? .opacity : .scale(scale: 0.8).combined(with: .opacity)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    thumbnail(image)
                        .transition(arrival)
                }
                ForEach(0..<pending, id: \.self) { _ in
                    loadingTile
                        .transition(.opacity)
                }
            }
        }
        .frame(height: Self.tileSize)
    }

    private func thumbnail(_ image: CaptureImage) -> some View {
        Image(uiImage: image.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: Self.tileSize, height: Self.tileSize)
            .clipShape(tileShape)
            .overlay(alignment: .topTrailing) {
                RemoveBadge(label: Text("Remove image")) { onRemoveImage(image.id) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(NodeKind.image.label))
    }

    private var loadingTile: some View {
        tileShape
            .fill(Color.white.opacity(0.08))
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay { ProgressView().tint(OceanTheme.mist) }
            .accessibilityHidden(true)
    }
}

/// The small ✕ in a tile's corner: a white glyph on a dark disc, so it
/// reads on any photo, inside a 32 pt target.
private struct RemoveBadge: View {
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.black.opacity(0.6), in: Circle())
                .padding(4)
                .frame(width: 32, height: 32, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
```

- [ ] **Step 3: Let a parked draft hold pictures**

In `Oryne/Features/FastCapture/CaptureControl.swift`, replace:

```swift
/// A draft put away unsent: the words, and a screenshot or a take's audio
/// riding along with them. It lives as long as the app does.
struct ParkedCapture {
    var text: String
    var imageData: Data?
    var heldDraft: CaptureDraft?

    /// The bar's line: the words' first line, or what rides along when
    /// nothing was typed.
    var line: String {
        if let first = text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
            return first
        }
        return heldDraft?.audioData != nil ? String(localized: "Whisper") : String(localized: "Screenshot")
    }
}
```

with:

```swift
/// A draft put away unsent: the words, and the pictures or a take's audio
/// riding along with them. It lives as long as the app does.
struct ParkedCapture {
    var text: String
    var images: [CaptureImage] = []
    var heldDraft: CaptureDraft?

    /// The bar's line: the words' first line, or what rides along when
    /// nothing was typed.
    var line: String {
        if let first = text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
            return first
        }
        if heldDraft?.audioData != nil { return String(localized: "Whisper") }
        return images.count > 1 ? String(localized: "\(images.count) images") : String(localized: "Image")
    }
}
```

- [ ] **Step 4: One picture list through the capture pipeline**

In `Oryne/Services/CaptureSession.swift`, replace:

```swift
    /// Single-image input (Fast Capture's one screenshot). The Capture surface
    /// uses `imageDatas` for multi-image; `release` normalizes either into the
    /// node's image set.
    var imageData: Data? = nil
    var imageDatas: [Data] = []
```

with:

```swift
    /// The pictures on the card, in the order they were added (at most
    /// `Node.maxImages`).
    var imageDatas: [Data] = []
```

Replace:

```swift
            && audioData == nil
            && imageData == nil
            && imageDatas.isEmpty
```

with:

```swift
            && audioData == nil
            && imageDatas.isEmpty
```

Replace:

```swift
        let meaning = [draft.text, draft.transcript]
            .map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        let imageDatas = draft.imageDatas.isEmpty ? [draft.imageData].compactMap { $0 } : draft.imageDatas
        let node = NodeComposer.make(
            kind: draft.kind,
            text: draft.text.trimmed,
            transcription: draft.transcript.trimmed.isEmpty ? nil : draft.transcript.trimmed,
            linkURLString: draft.linkURLString,
            audioData: draft.audioData,
            imageDatas: imageDatas,
            detectThemes: !meaning.isEmpty
        )
```

with:

```swift
        let meaning = [draft.text, draft.transcript]
            .map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        let node = NodeComposer.make(
            // What it holds names it: a whisper, a thought, or (with no
            // words) its pictures or its link.
            kind: NodeKind.captured(
                voice: draft.kind == .voice || draft.audioData != nil,
                words: meaning,
                images: draft.imageDatas.count,
                link: draft.linkURLString != nil
            ),
            text: draft.text.trimmed,
            transcription: draft.transcript.trimmed.isEmpty ? nil : draft.transcript.trimmed,
            linkURLString: draft.linkURLString,
            audioData: draft.audioData,
            imageDatas: draft.imageDatas,
            detectThemes: !meaning.isEmpty
        )
```

- [ ] **Step 5: The composer keeps a list of pictures**

All in `Oryne/Features/FastCapture/FastCaptureSessionView.swift`. Make each replacement exactly.

5a. Replace:

```swift
    @State private var text: String
    @State private var imageData: Data?
    @State private var session = CaptureSession()
```

with:

```swift
    @State private var text: String
    /// The pictures on the card, in the order they were added.
    @State private var images: [CaptureImage]
    @State private var session = CaptureSession()
```

5b. Replace:

```swift
        _text = State(initialValue: request.seedText)
        _imageData = State(initialValue: request.imageData)
```

with:

```swift
        _text = State(initialValue: request.seedText)
        // The Action Button's screenshot is the card's first picture.
        _images = State(initialValue: request.imageData.flatMap(CaptureImage.init(data:)).map { [$0] } ?? [])
```

5c. Replace:

```swift
        VStack(alignment: .leading, spacing: cardInset) {
            if let imageData, let uiImage = UIImage(data: imageData) {
                screenshotPreview(uiImage)
            }
```

with:

```swift
        VStack(alignment: .leading, spacing: cardInset) {
            // What rides along sits above the words, only while the card
            // is open, so the fold still lands on the bar's one line.
            if cardShown, !images.isEmpty {
                CaptureAttachments(images: images, onRemoveImage: removeImage)
                    .transition(.opacity)
            }
```

5d. Replace:

```swift
            CaptureBarWords(draft: canRelease ? ParkedCapture(text: text, imageData: imageData, heldDraft: heldDraft).line : nil)
```

with:

```swift
            CaptureBarWords(draft: canRelease ? ParkedCapture(text: text, images: images, heldDraft: heldDraft).line : nil)
```

5e. Replace:

```swift
            control.parked = ParkedCapture(text: text, imageData: imageData, heldDraft: heldDraft)
```

with:

```swift
            control.parked = ParkedCapture(text: text, images: images, heldDraft: heldDraft)
```

5f. Replace:

```swift
        text = parked.text
        imageData = parked.imageData
        heldDraft = parked.heldDraft
```

with:

```swift
        text = parked.text
        images = parked.images
        heldDraft = parked.heldDraft
```

5g. The tall preview goes. Replace the whole `screenshotPreview` function and the `canRelease` after it:

```swift
    private func screenshotPreview(_ uiImage: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(height: 116)
                .frame(maxWidth: .infinity)
                // Concentric with the card's corner.
                .clipShape(RoundedRectangle(
                    cornerRadius: FastCaptureLayout.cardRadius - FastCaptureLayout.cardInset,
                    style: .continuous
                ))

            Button {
                withAnimation(.snappy) { imageData = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(6)
            }
            .accessibilityLabel("Remove screenshot")
        }
    }

    private var canRelease: Bool {
        !text.trimmed.isEmpty || imageData != nil || heldDraft?.audioData != nil
    }
```

with:

```swift
    private var canRelease: Bool {
        !text.trimmed.isEmpty || !images.isEmpty || heldDraft?.audioData != nil
    }

    /// A picture's ✕.
    private func removeImage(_ id: CaptureImage.ID) {
        withAnimation(.snappy) { images.removeAll { $0.id == id } }
    }
```

5h. In `catchTake()`, replace:

```swift
        if words.isEmpty, note.isEmpty, imageData == nil, heldDraft == nil, elapsed < 1 {
```

with:

```swift
        if words.isEmpty, note.isEmpty, images.isEmpty, heldDraft == nil, elapsed < 1 {
```

and replace:

```swift
        draft.imageData = imageData
        draft.anchorThemeKey = request.anchorThemeKey
        heldDraft = nil
```

with:

```swift
        draft.imageDatas = images.map(\.data)
        draft.anchorThemeKey = request.anchorThemeKey
        heldDraft = nil
```

5i. In `saveTyped()`, replace:

```swift
        } else {
            draft.kind = (imageData != nil && trimmed.isEmpty) ? .image : .text
            draft.text = trimmed
        }
        draft.imageData = imageData
        draft.anchorThemeKey = request.anchorThemeKey
```

with:

```swift
        } else {
            // `release` names a thought of only pictures (NodeKind.captured).
            draft.kind = .text
            draft.text = trimmed
        }
        draft.imageDatas = images.map(\.data)
        draft.anchorThemeKey = request.anchorThemeKey
```

5j. In `beginNextCapture()`, replace:

```swift
        text = ""
        imageData = nil
        heldDraft = nil
```

with:

```swift
        text = ""
        images = []
        heldDraft = nil
```

5k. In `undoCapture()`, replace:

```swift
        imageData = draft.imageData
        control.toastShowing = false
```

with:

```swift
        images = draft.imageDatas.compactMap(CaptureImage.init(data:))
        control.toastShowing = false
```

Then confirm nothing still names the old slot:

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && grep -n -E "imageData\b|screenshotPreview" Oryne/Features/FastCapture/FastCaptureSessionView.swift Oryne/Services/CaptureSession.swift Oryne/Features/FastCapture/CaptureControl.swift
```

Expected: only `request.imageData` lines in `FastCaptureSessionView.swift` (the init and the `.task` check).

- [ ] **Step 6: Strings: add `%lld images`, prune `Remove screenshot`**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && python3 - <<'EOF'
import json, re
path = 'Oryne/Resources/Localizable.xcstrings'
raw = open(path, encoding='utf-8').read()

def entry(key, zh):
    k = json.dumps(key, ensure_ascii=False)
    v = json.dumps(zh, ensure_ascii=False)
    return ('    ' + k + ' : {\n'
            '      "localizations" : {\n'
            '        "zh-Hans" : {\n'
            '          "stringUnit" : {\n'
            '            "state" : "translated",\n'
            '            "value" : ' + v + '\n'
            '          }\n'
            '        }\n'
            '      }\n'
            '    }')

assert '"%lld images"' not in raw
tail = '\n  },\n  "version" : "1.1"\n}'
assert raw.endswith(tail), "catalog tail changed; add the entry by hand"
raw = raw[:-len(tail)] + ',\n' + entry("%lld images", "%lld 张图片") + tail

# Its only use went with the tall screenshot preview.
raw, n = re.subn(r'\n    "Remove screenshot" : \{.*?\n    \},', '', raw, count=1, flags=re.S)
assert n == 1
json.loads(raw)
open(path, 'w', encoding='utf-8').write(raw)
print("catalog updated")
EOF
```

Expected: `catalog updated`.

- [ ] **Step 7: Build and run the unit tests**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Oryne.xcodeproj -scheme Oryne \
  -destination 'platform=iOS Simulator,name=Oryne attach test' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/oryne-image-link \
  -only-testing:SharedTests CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES 2>&1 | grep -E "error:|warning: .*FastCapture|Executed|TEST (SUCCEEDED|FAILED)" | tail -8
```

Expected: no `error:`, `** TEST SUCCEEDED **` (the app target builds as part of the scheme).

- [ ] **Step 8: See the screenshot arrive as a thumbnail (headless)**

Stage an Action Button capture before the app's first launch, then screenshot the composer.

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SHOTS=/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-image-link-input-318138/3b17d77d-3c92-4dcc-8a1b-9f72ca5079ab/scratchpad/shots && mkdir -p "$SHOTS"
UDID=$(xcrun simctl list devices | grep "Oryne attach test" | grep -oE '[0-9A-F-]{36}' | head -1)
APP=~/Library/Developer/Xcode/DerivedData/oryne-image-link/Build/Products/Debug-iphonesimulator/Oryne.app
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl uninstall "$UDID" com.inspireocean.app 2>/dev/null; xcrun simctl install "$UDID" "$APP"
GROUP=$(xcrun simctl get_app_container "$UDID" com.inspireocean.app groups | grep shared | awk '{print $2}')
PLIST="$GROUP/Library/Preferences/group.com.inspireocean.shared"
xcrun simctl spawn "$UDID" defaults write "$PLIST" fastCapture.onboardingCompleted -bool true
mkdir -p "$GROUP/FastCapture"
xcrun simctl io "$UDID" screenshot "$GROUP/FastCapture/context-test.image" >/dev/null
JSON='{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","source":"shortcut","inputPreferenceRaw":"typingFirst","imageFileName":"context-test.image","seedText":"","createdAt":783000000}'
xcrun simctl spawn "$UDID" defaults write "$PLIST" fastCapture.pendingRequest -data "$(printf '%s' "$JSON" | xxd -p | tr -d '\n')"
xcrun simctl launch "$UDID" com.inspireocean.app -AppleLanguages '(en)'
sleep 5
xcrun simctl io "$UDID" screenshot "$SHOTS/task2-screenshot-thumbnail.png"
```

Then look at `task2-screenshot-thumbnail.png` (Read tool). Expected: the open composer card with one 64 pt square thumbnail of the home screen at its top-left, a ✕ badge in the thumbnail's top-right corner, the field "What are you noticing?" under it, and the disc showing the send arrow. No tall full-width preview.

- [ ] **Step 9: Commit**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && \
git -c core.trustctime=false -c core.checkStat=minimal add Oryne/Services/ImageDownsampler.swift Oryne/Features/FastCapture/CaptureAttachments.swift Oryne/Features/FastCapture/CaptureControl.swift Oryne/Services/CaptureSession.swift Oryne/Features/FastCapture/FastCaptureSessionView.swift Oryne/Resources/Localizable.xcstrings && \
git -c core.trustctime=false -c core.checkStat=minimal commit -q -m "Capture composer: pictures as thumbnails on the card, the screenshot first among them" && \
git log --oneline -1
```

---

### Task 3: The + and its sheet

**Files:**
- Create: `Oryne/Features/FastCapture/CaptureAttachSheet.swift`
- Modify: `Oryne/Features/FastCapture/FastCaptureSessionView.swift`
- Modify: `project.yml` (the app target's `info.properties`, after `NSPhotoLibraryUsageDescription`, line 91)
- Modify: `Oryne/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CaptureImage`, `CaptureImage.make(from:)`, `CaptureAttachments(images:pending:onRemoveImage:)` (Task 2); `ImageDownsampler.attachmentData(from:)`, `ImageDownsampler.downsample(_:maxPixel:)`, `ImageDownsampler.Size.attachment` (existing).
- Produces:
  - `struct CaptureAttachSheet: View { init(onPick: @escaping (PhotosPickerItem) -> Void, onCamera: @escaping () -> Void, onLibrary: @escaping () -> Void) }`
  - `struct CameraPicker: UIViewControllerRepresentable { init(onFinish: @escaping (UIImage?) -> Void); static var isAvailable: Bool }`
  - In `FastCaptureSessionView`: `@State private var pendingImages: Int`, `private var room: Int`, `private func attach(_ items: [PhotosPickerItem])`.

- [ ] **Step 1: Create the sheet and the camera**

Create `Oryne/Features/FastCapture/CaptureAttachSheet.swift`:

```swift
import SwiftUI
import UIKit
import PhotosUI

/// The composer's +, after Claude and ChatGPT: a strip of the latest
/// photos (a tap attaches one and closes the sheet), then Camera and All
/// Photos. The strip is the system's own picker drawn in place, out of
/// process, so Oryne never reads the library and never asks for access.
struct CaptureAttachSheet: View {
    var onPick: (PhotosPickerItem) -> Void
    var onCamera: () -> Void
    var onLibrary: () -> Void

    @State private var selection: [PhotosPickerItem] = []

    /// The strip, the rows and the sheet's margins.
    static let height: CGFloat = 268

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(
                selection: $selection,
                maxSelectionCount: 1,
                selectionBehavior: .continuous,
                matching: .images
            ) {
                EmptyView()
            }
            .photosPickerStyle(.compact)
            .photosPickerDisabledCapabilities([.search, .collectionNavigation, .stagingArea, .selectionActions])
            .photosPickerAccessoryVisibility(.hidden, edges: .all)
            .frame(height: 120)
            .onChange(of: selection) { _, items in
                if let item = items.first { onPick(item) }
            }

            VStack(spacing: 0) {
                if CameraPicker.isAvailable {
                    row("Camera", systemImage: "camera", action: onCamera)
                }
                row("All Photos", systemImage: "photo.on.rectangle", action: onLibrary)
            }
        }
        .padding(.horizontal, OceanSpacing.gutter)
        .padding(.top, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.visible)
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body)
                .foregroundStyle(OceanTheme.foam)
                .frame(maxWidth: .infinity, minHeight: OceanControlSize.height, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The system camera, for one photo. `UIImagePickerController` is still
/// the only system camera screen an app can present.
struct CameraPicker: UIViewControllerRepresentable {
    /// The shot, or nil when the camera was closed without one.
    var onFinish: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
```

- [ ] **Step 2: The camera's permission line**

In `project.yml`, replace:

```yaml
        NSPhotoLibraryUsageDescription: "Oryne lets you capture screenshots and photos as inspiration fragments."
```

with:

```yaml
        NSPhotoLibraryUsageDescription: "Oryne lets you capture screenshots and photos as inspiration fragments."
        NSCameraUsageDescription: "Oryne uses the camera to catch what you see."
```

(Only the first occurrence, under the `Oryne` target; it appears once.)

- [ ] **Step 3: The composer's +, its sheet, and loading pictures**

All in `Oryne/Features/FastCapture/FastCaptureSessionView.swift`.

3a. Replace:

```swift
import SwiftUI
import SwiftData
```

with:

```swift
import SwiftUI
import SwiftData
import PhotosUI
```

3b. Replace:

```swift
    /// The pictures on the card, in the order they were added.
    @State private var images: [CaptureImage]
    @State private var session = CaptureSession()
```

with:

```swift
    /// The pictures on the card, in the order they were added.
    @State private var images: [CaptureImage]
    /// Pictures picked but still loading: a quiet tile each.
    @State private var pendingImages = 0
    /// The send was tapped while pictures were still loading: it goes once
    /// they are in, so a release never leaves one behind.
    @State private var releaseWhenLoaded = false
    @State private var attachSheetShown = false
    /// Where the + sheet hands over once it has closed.
    @State private var attachRoute: AttachRoute?
    @State private var cameraShown = false
    @State private var libraryShown = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var session = CaptureSession()
```

3c. Replace:

```swift
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            finishInterruptedCapture()
        }
    }
```

with:

```swift
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            finishInterruptedCapture()
        }
        .sheet(isPresented: $attachSheetShown, onDismiss: attachSheetClosed) {
            CaptureAttachSheet(
                onPick: { item in
                    attachSheetShown = false
                    attach([item])
                },
                onCamera: { route(to: .camera) },
                onLibrary: { route(to: .library) }
            )
        }
        .fullScreenCover(isPresented: $cameraShown, onDismiss: { textFocused = true }) {
            CameraPicker(onFinish: attachShot)
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $libraryShown,
            selection: $libraryItems,
            maxSelectionCount: max(room, 1),
            selectionBehavior: .ordered,
            matching: .images
        )
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            libraryItems = []
            attach(items)
        }
        .onChange(of: libraryShown) { _, shown in
            if !shown { textFocused = true }
        }
    }
```

3d. Replace:

```swift
            if cardShown, !images.isEmpty {
                CaptureAttachments(images: images, onRemoveImage: removeImage)
                    .transition(.opacity)
            }
```

with:

```swift
            if cardShown, !images.isEmpty || pendingImages > 0 {
                CaptureAttachments(images: images, pending: pendingImages, onRemoveImage: removeImage)
                    .transition(.opacity)
            }
```

3e. Replace the whole `actionRow` (doc comment included):

```swift
    /// The card's second row, at its foot: the disc at the trailing end,
    /// and before it what the card has to say. Folded, only the disc shows,
    /// as on the bar.
    private var actionRow: some View {
        HStack(alignment: .center, spacing: 8) {
            composerCaptions
                .opacity(cardShown ? 1 : 0)
            Spacer(minLength: 0)
            overlayDisc(inComposer: true, send: canRelease ? saveTyped : nil)
        }
        .frame(minHeight: FastCaptureLayout.buttonSize)
    }
```

with:

```swift
    /// The card's second row, at its foot: the + at the leading end, the
    /// disc at the trailing end, and between them what the card has to
    /// say. Folded, only the disc shows, as on the bar.
    private var actionRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                attachButton
                composerCaptions
            }
            .opacity(cardShown ? 1 : 0)
            Spacer(minLength: 0)
            overlayDisc(inComposer: true, send: canRelease ? saveTyped : nil)
        }
        .frame(minHeight: FastCaptureLayout.buttonSize)
    }

    /// The card's +, the send disc's twin: the latest photos, Camera, All
    /// Photos. The keyboard steps down for the sheet and comes back after.
    /// Dimmed once the thought holds all the pictures it can.
    private var attachButton: some View {
        Button {
            textFocused = false
            attachSheetShown = true
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.oceanIcon)
        .disabled(room == 0)
        .opacity(room == 0 ? 0.4 : 1)
        .accessibilityLabel("Add image")
        .accessibilityIdentifier("composer.attach")
    }
```

3f. Replace:

```swift
    private var canRelease: Bool {
        !text.trimmed.isEmpty || !images.isEmpty || heldDraft?.audioData != nil
    }
```

with:

```swift
    /// Something to release: what the card holds, or pictures on their way.
    private var canRelease: Bool { hasDraft || pendingImages > 0 }

    /// What the card holds now, which open water parks in the bar.
    private var hasDraft: Bool {
        !text.trimmed.isEmpty || !images.isEmpty || heldDraft?.audioData != nil
    }

    /// Pictures the thought can still take (`Node.maxImages` in all).
    private var room: Int { max(0, Node.maxImages - images.count - pendingImages) }
```

3g. In `putAway()`, replace:

```swift
        if canRelease, !asSheet {
```

with:

```swift
        if hasDraft, !asSheet {
```

3h. In `composerField`, replace:

```swift
            CaptureBarWords(draft: canRelease ? ParkedCapture(text: text, images: images, heldDraft: heldDraft).line : nil)
```

with:

```swift
            CaptureBarWords(draft: hasDraft ? ParkedCapture(text: text, images: images, heldDraft: heldDraft).line : nil)
```

3i. In `saveTyped()`, replace:

```swift
    private func saveTyped() {
        guard !isSaving, canRelease else { return }
        let trimmed = text.trimmed
```

with:

```swift
    private func saveTyped() {
        guard !isSaving, canRelease else { return }
        // Pictures still loading go too: the send waits for them.
        guard pendingImages == 0 else {
            releaseWhenLoaded = true
            return
        }
        let trimmed = text.trimmed
```

3j. Add the attach functions right after `removeImage(_:)` (which Task 2 put after `canRelease`; keep it):

```swift
    private enum AttachRoute { case camera, library }

    /// The + sheet's Camera or All Photos: the sheet closes first, then the
    /// one chosen opens (`attachSheetClosed`).
    private func route(to route: AttachRoute) {
        attachRoute = route
        attachSheetShown = false
    }

    /// The + sheet has closed: on to the camera or the whole library when
    /// one was chosen, else back to the words.
    private func attachSheetClosed() {
        let route = attachRoute
        attachRoute = nil
        switch route {
        case .camera: cameraShown = true
        case .library: libraryShown = true
        case nil: textFocused = true
        }
    }

    /// Picked photos join the card in the order picked, each shrunk to the
    /// attachment size first, as many as the thought has room for; a quiet
    /// tile holds each one's place meanwhile.
    private func attach(_ items: [PhotosPickerItem]) {
        let fits = Array(items.prefix(room))
        if fits.count < items.count {
            message = String(localized: "Only added \(fits.count), \(Node.maxImages) images max.")
        }
        guard !fits.isEmpty else { return }
        pendingImages += fits.count
        Task {
            let datas = await ImageDownsampler.attachmentData(from: fits)
            await add(datas, standingIn: fits.count)
        }
    }

    /// The camera's shot, shrunk off the main actor like a picked photo.
    private func attachShot(_ shot: UIImage?) {
        cameraShown = false
        guard let shot, room > 0 else { return }
        pendingImages += 1
        Task {
            let data = await Task.detached {
                shot.jpegData(compressionQuality: 0.9).flatMap {
                    ImageDownsampler.downsample($0, maxPixel: ImageDownsampler.Size.attachment)
                }
            }.value
            await add([data].compactMap { $0 }, standingIn: 1)
        }
    }

    /// Loaded pictures take their tiles' places. A send tapped meanwhile
    /// goes now.
    @MainActor
    private func add(_ datas: [Data], standingIn placeholders: Int) async {
        let fresh = await CaptureImage.make(from: datas)
        pendingImages = max(0, pendingImages - placeholders)
        withAnimation(.snappy) { images.append(contentsOf: fresh) }
        if releaseWhenLoaded, pendingImages == 0 {
            releaseWhenLoaded = false
            saveTyped()
        }
    }
```

- [ ] **Step 4: Strings: `Camera`, `All Photos`**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && python3 - <<'EOF'
import json
path = 'Oryne/Resources/Localizable.xcstrings'
raw = open(path, encoding='utf-8').read()

def entry(key, zh):
    k = json.dumps(key, ensure_ascii=False)
    v = json.dumps(zh, ensure_ascii=False)
    return ('    ' + k + ' : {\n'
            '      "localizations" : {\n'
            '        "zh-Hans" : {\n'
            '          "stringUnit" : {\n'
            '            "state" : "translated",\n'
            '            "value" : ' + v + '\n'
            '          }\n'
            '        }\n'
            '      }\n'
            '    }')

new = [("Camera", "相机"), ("All Photos", "所有照片")]
for key, _ in new:
    assert ('"%s" :' % key) not in raw, key
tail = '\n  },\n  "version" : "1.1"\n}'
assert raw.endswith(tail), "catalog tail changed; add the entries by hand"
raw = raw[:-len(tail)] + ',\n' + ',\n'.join(entry(k, zh) for k, zh in new) + tail
json.loads(raw)
open(path, 'w', encoding='utf-8').write(raw)
print("catalog updated")
EOF
```

Expected: `catalog updated`.

- [ ] **Step 5: Build and run the unit tests**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Oryne.xcodeproj -scheme Oryne \
  -destination 'platform=iOS Simulator,name=Oryne attach test' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/oryne-image-link \
  -only-testing:SharedTests CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" | tail -6
```

Expected: no `error:`, `** TEST SUCCEEDED **`. Also confirm the camera line reached the built app:

```bash
/usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" ~/Library/Developer/Xcode/DerivedData/oryne-image-link/Build/Products/Debug-iphonesimulator/Oryne.app/Info.plist
```

Expected: `Oryne uses the camera to catch what you see.`

- [ ] **Step 6: Try the + on the simulator**

Seed the photo library and reinstall, then drive the composer with the iOS Simulator `control` tool (the controller does this if the implementer has no simulator tool):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(xcrun simctl list devices | grep "Oryne attach test" | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl addmedia "$UDID" "/System/Library/Desktop Pictures/.thumbnails/Big Sur Aerial.heic" "/System/Library/Desktop Pictures/.thumbnails/Big Sur Coastline.heic" "/System/Library/Desktop Pictures/.thumbnails/Big Sur Graphic Light.heic"
xcrun simctl terminate "$UDID" com.inspireocean.app 2>/dev/null
xcrun simctl install "$UDID" ~/Library/Developer/Xcode/DerivedData/oryne-image-link/Build/Products/Debug-iphonesimulator/Oryne.app
xcrun simctl launch "$UDID" com.inspireocean.app -AppleLanguages '(en)'
```

With `control` (taps `duration: 0.1`; proof shots with `xcrun simctl io "$UDID" screenshot …`): tap the capture bar's words; the card opens with + at its leading end. Tap +. Expected: a short sheet with a row of the latest photos and one row, All Photos (no Camera row on the simulator). Tap a photo in the strip. Expected: the sheet closes, the keyboard returns, and a thumbnail (briefly a loading tile) appears at the top of the card. Tap + then All Photos, pick two, tap Add. Expected: three thumbnails in pick order.

- [ ] **Step 7: Commit**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && \
git -c core.trustctime=false -c core.checkStat=minimal add Oryne/Features/FastCapture/CaptureAttachSheet.swift Oryne/Features/FastCapture/FastCaptureSessionView.swift project.yml Oryne/Resources/Localizable.xcstrings && \
git -c core.trustctime=false -c core.checkStat=minimal commit -q -m "Capture composer: a + for the latest photos, Camera and All Photos" && \
git log --oneline -1
```

---

### Task 4: Links sensed in the words

**Files:**
- Modify: `Oryne/Services/CaptureSession.swift` (`CaptureDraft`, `release`, `beginUnderstanding`)
- Modify: `Oryne/Features/FastCapture/CaptureControl.swift` (`ParkedCapture`)
- Modify: `Oryne/Features/FastCapture/CaptureAttachments.swift`
- Modify: `Oryne/Features/FastCapture/FastCaptureSessionView.swift`

**Interfaces:**
- Consumes: `LinkSensing.chosen(in:dismissed:)`, `LinkSensing.words(_:lifting:)`, `LinkSensing.Sensed` (Task 1); `LinkEnrichmentService.shared.enrich(nodeID:context:ai:)` (existing).
- Produces:
  - `CaptureDraft.dismissedLinks: Set<String>`; `ParkedCapture.dismissedLinks: Set<String>` (memberwise `ParkedCapture(text:images:heldDraft:dismissedLinks:)`)
  - `CaptureAttachments(images:pending:link:onRemoveImage:onRemoveLink:)` with `link: LinkSensing.Sensed? = nil`, `onRemoveLink: (String) -> Void = { _ in }`

- [ ] **Step 1: The draft remembers dismissed links; release lifts and enriches**

In `Oryne/Services/CaptureSession.swift`, replace:

```swift
    var imageDatas: [Data] = []
    var linkURLString: String? = nil
```

with:

```swift
    var imageDatas: [Data] = []
    /// The link a release attaches, sensed in the words. `text` keeps the
    /// words as typed (for Undo); `release` lifts the link out of the
    /// thought's words when it sits at their start or end.
    var linkURLString: String? = nil
    /// Links the user took off the card: they stay words, and Undo brings
    /// them back that way.
    var dismissedLinks: Set<String> = []
```

Replace:

```swift
        let meaning = [draft.text, draft.transcript]
            .map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        let node = NodeComposer.make(
            // What it holds names it: a whisper, a thought, or (with no
            // words) its pictures or its link.
            kind: NodeKind.captured(
                voice: draft.kind == .voice || draft.audioData != nil,
                words: meaning,
                images: draft.imageDatas.count,
                link: draft.linkURLString != nil
            ),
            text: draft.text.trimmed,
            transcription: draft.transcript.trimmed.isEmpty ? nil : draft.transcript.trimmed,
            linkURLString: draft.linkURLString,
            audioData: draft.audioData,
            imageDatas: draft.imageDatas,
            detectThemes: !meaning.isEmpty
        )
```

with:

```swift
        // A link at the start or end of the words leaves them: its card
        // carries it.
        let link = draft.linkURLString
        let text = LinkSensing.words(draft.text, lifting: link)
        let transcript = LinkSensing.words(draft.transcript, lifting: link)
        let meaning = [text, transcript].filter { !$0.isEmpty }.joined(separator: " ")
        let node = NodeComposer.make(
            // What it holds names it: a whisper, a thought, or (with no
            // words) its pictures or its link.
            kind: NodeKind.captured(
                voice: draft.kind == .voice || draft.audioData != nil,
                words: meaning,
                images: draft.imageDatas.count,
                link: link != nil
            ),
            text: text,
            transcription: transcript.isEmpty ? nil : transcript,
            linkURLString: link,
            audioData: draft.audioData,
            imageDatas: draft.imageDatas,
            detectThemes: !meaning.isEmpty
        )
```

Replace:

```swift
        understandingTask?.cancel()
        understandingTask = Task {
            await VoiceUnderstanding.run(
                nodeID: nodeID, audioTempURL: tempURL, context: context, ai: ai, vocabulary: vocabulary
            )
        }
    }
```

with:

```swift
        understandingTask?.cancel()
        understandingTask = Task {
            await VoiceUnderstanding.run(
                nodeID: nodeID, audioTempURL: tempURL, context: context, ai: ai, vocabulary: vocabulary
            )
        }
        // A link becomes a rich card, and what its page says joins the
        // thought's meaning (best effort; a link alone is named by its page).
        if fetch(nodeID)?.linkURL != nil {
            LinkEnrichmentService.shared.enrich(nodeID: nodeID, context: context, ai: ai)
        }
    }
```

- [ ] **Step 2: A parked draft keeps its dismissals**

In `Oryne/Features/FastCapture/CaptureControl.swift`, replace:

```swift
    var images: [CaptureImage] = []
    var heldDraft: CaptureDraft?
```

with:

```swift
    var images: [CaptureImage] = []
    var heldDraft: CaptureDraft?
    /// Links taken off the card: they are still words when it comes back.
    var dismissedLinks: Set<String> = []
```

- [ ] **Step 3: The link tile**

In `Oryne/Features/FastCapture/CaptureAttachments.swift`:

Replace the struct's doc comment and stored inputs:

```swift
/// What rides on the composer's card above the words: its pictures, and a
/// quiet tile for each one still loading. Square tiles of 64 pt whose
/// corners sit concentric with the card's, each with its own ✕. The row
/// scrolls sideways once it is wider than the card.
struct CaptureAttachments: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm

    let images: [CaptureImage]
    /// Pictures picked but not yet loaded.
    var pending = 0
    var onRemoveImage: (CaptureImage.ID) -> Void
```

with:

```swift
/// What rides on the composer's card above the words: its pictures, a
/// quiet tile for each one still loading, and the link sensed in the
/// words. Square tiles of 64 pt whose corners sit concentric with the
/// card's, each with its own ✕. The row scrolls sideways once it is wider
/// than the card.
struct CaptureAttachments: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm

    let images: [CaptureImage]
    /// Pictures picked but not yet loaded.
    var pending = 0
    /// The link a release would attach.
    var link: LinkSensing.Sensed? = nil
    var onRemoveImage: (CaptureImage.ID) -> Void
    /// The link tile's ✕, with the link's URL.
    var onRemoveLink: (String) -> Void = { _ in }
```

Replace:

```swift
                ForEach(0..<pending, id: \.self) { _ in
                    loadingTile
                        .transition(.opacity)
                }
            }
```

with:

```swift
                ForEach(0..<pending, id: \.self) { _ in
                    loadingTile
                        .transition(.opacity)
                }
                if let link {
                    linkTile(link)
                        .transition(.opacity)
                }
            }
```

Add after `loadingTile`:

```swift

    /// The sensed link: its site's name under the link glyph, on the quiet
    /// fill of a content control. Its ✕ leaves the link in the words as
    /// text, never attached.
    private func linkTile(_ link: LinkSensing.Sensed) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "link")
                .font(.footnote.weight(.medium))
                .foregroundStyle(OceanTheme.mist)
            Spacer(minLength: 0)
            Text(verbatim: link.host)
                .font(.footnote)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(1)
        }
        .padding(10)
        .frame(
            minWidth: Self.tileSize, maxWidth: 168,
            minHeight: Self.tileSize, maxHeight: Self.tileSize,
            alignment: .leading
        )
        .background(Color.white.opacity(0.08), in: tileShape)
        .overlay(alignment: .topTrailing) {
            RemoveBadge(label: Text("Remove link")) { onRemoveLink(link.urlString) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(NodeKind.link.label))
        .accessibilityValue(Text(verbatim: link.host))
    }
```

- [ ] **Step 4: The composer senses the link and carries it**

All in `Oryne/Features/FastCapture/FastCaptureSessionView.swift`.

4a. Replace:

```swift
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var session = CaptureSession()
```

with:

```swift
    @State private var libraryItems: [PhotosPickerItem] = []
    /// Links taken off the card with the tile's ✕: they stay in the words
    /// as text and are never attached.
    @State private var dismissedLinks: Set<String> = []
    /// The link the tile shows, sensed from the field a moment after the
    /// last edit. A release senses the words afresh.
    @State private var sensedLink: LinkSensing.Sensed?
    @State private var senseTask: Task<Void, Never>?
    @State private var session = CaptureSession()
```

4b. In `.task`, replace:

```swift
               request.seedText.isEmpty, request.imageData == nil, request.anchorThemeKey == nil {
                takeBackParked()
            }
```

with:

```swift
               request.seedText.isEmpty, request.imageData == nil, request.anchorThemeKey == nil {
                takeBackParked()
            }
            // Words already in the field (a seed, a draft brought back) show
            // their link at once.
            senseLink(now: true)
```

4c. Replace:

```swift
            finishInterruptedCapture()
        }
        .sheet(isPresented: $attachSheetShown, onDismiss: attachSheetClosed) {
```

with:

```swift
            finishInterruptedCapture()
        }
        .onChange(of: text) { _, _ in senseLink() }
        .sheet(isPresented: $attachSheetShown, onDismiss: attachSheetClosed) {
```

4d. Replace:

```swift
            if cardShown, !images.isEmpty || pendingImages > 0 {
                CaptureAttachments(images: images, pending: pendingImages, onRemoveImage: removeImage)
                    .transition(.opacity)
            }
```

with:

```swift
            if cardShown, !images.isEmpty || pendingImages > 0 || sensedLink != nil {
                CaptureAttachments(
                    images: images,
                    pending: pendingImages,
                    link: sensedLink,
                    onRemoveImage: removeImage,
                    onRemoveLink: dismissLink
                )
                .transition(.opacity)
            }
```

4e. In `putAway()`, replace:

```swift
            control.parked = ParkedCapture(text: text, images: images, heldDraft: heldDraft)
```

with:

```swift
            control.parked = ParkedCapture(text: text, images: images, heldDraft: heldDraft, dismissedLinks: dismissedLinks)
```

4f. In `takeBackParked()`, replace:

```swift
        text = parked.text
        images = parked.images
        heldDraft = parked.heldDraft
    }
```

with:

```swift
        text = parked.text
        images = parked.images
        heldDraft = parked.heldDraft
        dismissedLinks = parked.dismissedLinks
        senseLink(now: true)
    }
```

4g. In `catchTake()`, replace:

```swift
        draft.imageDatas = images.map(\.data)
        draft.anchorThemeKey = request.anchorThemeKey
        heldDraft = nil
```

with:

```swift
        draft.imageDatas = images.map(\.data)
        // A typed note's link rides with the whisper; spoken words are
        // never scanned.
        draft.linkURLString = LinkSensing.chosen(in: note, dismissed: dismissedLinks)?.urlString
        draft.dismissedLinks = dismissedLinks
        draft.anchorThemeKey = request.anchorThemeKey
        heldDraft = nil
```

4h. In `saveTyped()`, replace:

```swift
        draft.imageDatas = images.map(\.data)
        draft.anchorThemeKey = request.anchorThemeKey
        guard let nodeID = session.release(draft) else {
```

with:

```swift
        draft.imageDatas = images.map(\.data)
        // The words' first link the user kept becomes the thought's link;
        // `release` lifts it out of the words when it sits at an edge.
        draft.linkURLString = LinkSensing.chosen(in: trimmed, dismissed: dismissedLinks)?.urlString
        draft.dismissedLinks = dismissedLinks
        draft.anchorThemeKey = request.anchorThemeKey
        guard let nodeID = session.release(draft) else {
```

4i. In `beginNextCapture()`, replace:

```swift
        text = ""
        images = []
        heldDraft = nil
```

with:

```swift
        text = ""
        images = []
        heldDraft = nil
        dismissedLinks = []
        senseTask?.cancel()
        sensedLink = nil
```

4j. In `undoCapture()`, replace:

```swift
        images = draft.imageDatas.compactMap(CaptureImage.init(data:))
        control.toastShowing = false
```

with:

```swift
        images = draft.imageDatas.compactMap(CaptureImage.init(data:))
        dismissedLinks = draft.dismissedLinks
        senseLink(now: true)
        control.toastShowing = false
```

4k. Add after `removeImage(_:)`:

```swift

    /// The tile follows the field half a second behind, so a link still
    /// being typed never flickers in; `now` shows it at once.
    private func senseLink(now: Bool = false) {
        senseTask?.cancel()
        guard !now else {
            sensedLink = LinkSensing.chosen(in: text, dismissed: dismissedLinks)
            return
        }
        senseTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                sensedLink = LinkSensing.chosen(in: text, dismissed: dismissedLinks)
            }
        }
    }

    /// The link tile's ✕: the link stays in the words as text and is never
    /// attached; the words' next link, if any, takes the tile.
    private func dismissLink(_ urlString: String) {
        dismissedLinks.insert(urlString)
        withAnimation(.snappy) {
            sensedLink = LinkSensing.chosen(in: text, dismissed: dismissedLinks)
        }
    }
```

- [ ] **Step 5: Build and run the unit tests**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Oryne.xcodeproj -scheme Oryne \
  -destination 'platform=iOS Simulator,name=Oryne attach test' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/oryne-image-link \
  -only-testing:SharedTests CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" | tail -6
```

Expected: no `error:`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: See a seeded link's tile (headless)**

The staged-request seed only works before the app's first launch, so reinstall first:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SHOTS=/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-image-link-input-318138/3b17d77d-3c92-4dcc-8a1b-9f72ca5079ab/scratchpad/shots && mkdir -p "$SHOTS"
UDID=$(xcrun simctl list devices | grep "Oryne attach test" | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl terminate "$UDID" com.inspireocean.app 2>/dev/null
xcrun simctl uninstall "$UDID" com.inspireocean.app; xcrun simctl install "$UDID" ~/Library/Developer/Xcode/DerivedData/oryne-image-link/Build/Products/Debug-iphonesimulator/Oryne.app
GROUP=$(xcrun simctl get_app_container "$UDID" com.inspireocean.app groups | grep shared | awk '{print $2}')
PLIST="$GROUP/Library/Preferences/group.com.inspireocean.shared"
xcrun simctl spawn "$UDID" defaults write "$PLIST" fastCapture.onboardingCompleted -bool true
JSON='{"id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","source":"shortcut","inputPreferenceRaw":"typingFirst","seedText":"Love this palette https://www.are.na/block/12345","createdAt":783000000}'
xcrun simctl spawn "$UDID" defaults write "$PLIST" fastCapture.pendingRequest -data "$(printf '%s' "$JSON" | xxd -p | tr -d '\n')"
xcrun simctl launch "$UDID" com.inspireocean.app -AppleLanguages '(en)'
sleep 5
xcrun simctl io "$UDID" screenshot "$SHOTS/task4-link-tile.png"
```

Read `task4-link-tile.png`. Expected: the open card with the words "Love this palette https://www.are.na/block/12345" and, above them, one tile reading "are.na" under a link glyph, with a ✕ badge.

- [ ] **Step 7: Commit**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && \
git -c core.trustctime=false -c core.checkStat=minimal add Oryne/Services/CaptureSession.swift Oryne/Features/FastCapture/CaptureControl.swift Oryne/Features/FastCapture/CaptureAttachments.swift Oryne/Features/FastCapture/FastCaptureSessionView.swift && \
git -c core.trustctime=false -c core.checkStat=minimal commit -q -m "Capture composer: a link in the words becomes the thought's link, shown as a tile before release" && \
git log --oneline -1
```

---

### Task 5: Verify on the simulator

End-to-end on "Oryne attach test", driving the app with the iOS Simulator `control` tool (taps `duration: 0.1`; proof shots with `xcrun simctl io <UDID> screenshot`, since `control`'s own screenshot can be stale), and reading the store after terminating the app:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(xcrun simctl list devices | grep "Oryne attach test" | grep -oE '[0-9A-F-]{36}' | head -1)
GROUP=$(xcrun simctl get_app_container "$UDID" com.inspireocean.app groups | grep shared | awk '{print $2}')
xcrun simctl terminate "$UDID" com.inspireocean.app
sqlite3 "$GROUP/InspireOcean.store" "select n.ZKINDRAW, quote(n.ZTEXT), quote(n.ZLINKURLSTRING), n.ZLINKENRICHMENTSTATERAW, (select count(*) from ZNODEIMAGE i where i.ZNODE = n.Z_PK) from ZNODE n where n.ZISEXAMPLE = 0 order by n.ZCREATEDAT desc limit 5;"
```

(First run `sqlite3 "$GROUP/InspireOcean.store" ".schema ZNODEIMAGE"` once and adjust the `ZNODE` column name if Core Data named the relationship column differently.)

**Files:** none expected; fix anything found in the file it lives in, with its own commit.

- [ ] **Step 1: Screenshot seed released.** Fresh install with the Task 2 Step 8 staging; tap send. Store: newest row `image`, NULL text, NULL link, 1 image.
- [ ] **Step 2: Strip pick with words.** Bar → + → tap a strip photo → type "Sunset palette" → send. Store: `text`, `'Sunset palette'`, NULL link, 1 image.
- [ ] **Step 3: All Photos, several.** + → All Photos → pick 3 → Add → send. Store: `image`, 3 images; open the thought: the strip shows them in pick order.
- [ ] **Step 4: Trailing link lifted.** Type "Love this palette https://www.are.na/block/12345"; within a second the tile shows "are.na"; send. Store: `text`, `'Love this palette'`, `'https://www.are.na/block/12345'`, enrichment state past `notStarted`. Open the thought: the link card follows the words.
- [ ] **Step 5: Link only.** Type "apple.com/newsroom"; send. Store: `link`, `''` text, `'https://apple.com/newsroom'`. After enrichment the Library card reads the page's title, not the URL.
- [ ] **Step 6: Mid-sentence and dismissed.** Type "read https://example.com/essay before friday"; send. Store: words unchanged, link set. Then type "see https://example.org", tap the tile's ✕ (tile goes), send. Store: `'see https://example.org'`, NULL link.
- [ ] **Step 7: Park and Undo.** Attach a photo and type "Coastline https://www.are.na/block/9"; tap open water. The bar reads "Coastline https://www.are.na/block/9". Tap the bar: the thumbnail and the tile are back. Send, then Undo: the words (URL included), the thumbnail and the tile come back. A draft of only two pictures parked reads "2 images".
- [ ] **Step 8: Whisper with pictures.** Attach a photo, then hold the disc and speak a few words, lift. Store: `voice` with 1 image.
- [ ] **Step 9: Cap.** Attach until 10; the + dims and does not open.
- [ ] **Step 10: zh-Hans.** Relaunch with `-AppleLanguages '(zh-Hans)'`: the sheet's row reads 所有照片; a parked two-picture draft reads 2 张图片.
- [ ] **Step 11: Reduce Motion.** `xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true`, relaunch: the card is open from the start and new thumbnails fade in. Turn it back off after.
- [ ] **Step 12: Tune and record.** If the sheet's strip or rows sit badly, adjust `CaptureAttachSheet.height` or the strip's 120 pt frame and recheck. Note anything that only a device can show (Camera, VoiceOver gestures) as owed to a device pass. Commit any fixes:

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/image-link-input-318138 && \
git -c core.trustctime=false -c core.checkStat=minimal status --short
```

Expected after the last commit: a clean tree.
