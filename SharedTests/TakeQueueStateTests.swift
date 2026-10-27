import XCTest
import Foundation

final class TakeQueueStateTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func take(_ offset: TimeInterval = 0) -> WatchTake {
        WatchTake(id: UUID(), createdAt: t0.addingTimeInterval(offset), duration: 3)
    }

    private func snapshot(_ thoughts: [WristThought] = [], deleted: [UUID] = []) -> WristSnapshot {
        WristSnapshot(recent: thoughts, today: nil, todayDay: nil, deletedIDs: deleted, generatedAt: t0)
    }

    private func transcribed(_ take: WatchTake, title: String? = nil) -> WristThought {
        var thought = WristThought(id: take.id, title: title, createdAt: take.createdAt)
        thought.hasTranscript = true
        return thought
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

    func test_deliveredTake_isNotSentAgain() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.markPhoneTransfer(a.id, .delivered)
        XCTAssertTrue(state.needingPhoneSend().isEmpty)
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

    func test_audioDisposable_keepsEveryRecordingTheWristCanReplay() {
        var state = TakeQueueState()
        let onWatch = take(), clouded = take(1), confirmed = take(2)
        [onWatch, clouded, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        let soon = t0.addingTimeInterval(60)

        XCTAssertFalse(state.audioDisposable(onWatch.id, now: soon))
        XCTAssertFalse(state.audioDisposable(clouded.id, now: soon))
        XCTAssertFalse(state.audioDisposable(confirmed.id, now: soon))
        XCTAssertFalse(state.audioDisposable(UUID(), now: soon), "a recording the queue can't account for is never deleted")
    }

    func test_audioDisposable_keepsAnUnconfirmedTake_evenTranscribedAndOld() {
        var state = TakeQueueState()
        let onWatch = take(), clouded = take(1)
        [onWatch, clouded].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply(snapshot([transcribed(onWatch), transcribed(clouded)]))
        let late = t0.addingTimeInterval(TakeQueueState.audioRetention * 2)

        XCTAssertFalse(state.audioDisposable(onWatch.id, now: late))
        XCTAssertFalse(state.audioDisposable(clouded.id, now: late))
    }

    func test_audioDisposable_expiresATranscribedTakeAsThePhoneDoes() {
        var state = TakeQueueState()
        let withWords = take(), withoutWords = take(1)
        [withWords, withoutWords].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([WatchConfirmation(id: withWords.id, title: nil), WatchConfirmation(id: withoutWords.id, title: nil)])
        state.apply(snapshot([transcribed(withWords)]))
        let retention = TakeQueueState.audioRetention

        XCTAssertFalse(state.audioDisposable(withWords.id, now: t0.addingTimeInterval(retention - 10)))
        XCTAssertTrue(state.audioDisposable(withWords.id, now: t0.addingTimeInterval(retention + 10)))
        XCTAssertFalse(state.audioDisposable(withoutWords.id, now: t0.addingTimeInterval(retention + 10)),
                       "with no transcript the recording is the only copy of the words")
    }

    func test_applySnapshot_removesOnlyConfirmedTakesThePhoneDeleted() {
        var state = TakeQueueState()
        let waiting = take(), confirmed = take(1)
        [waiting, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        let before = state

        state.apply(snapshot(deleted: [waiting.id, confirmed.id]))

        XCTAssertNotNil(state.item(waiting.id), "the phone can't have deleted a take it never confirmed")
        XCTAssertNil(state.item(confirmed.id))
        XCTAssertEqual(state.idsRemoved(since: before), [confirmed.id])
    }

    func test_applySnapshot_takesCurrentTitles_butANilTitleNeverErases() {
        var state = TakeQueueState()
        let renamed = take(), unnamed = take(1)
        [renamed, unnamed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([
            WatchConfirmation(id: renamed.id, title: "Lighthouse café"),
            WatchConfirmation(id: unnamed.id, title: "Old idea"),
        ])

        state.apply(snapshot([transcribed(renamed, title: "The café by the lighthouse"), transcribed(unnamed)]))

        XCTAssertEqual(state.item(renamed.id)?.title, "The café by the lighthouse")
        XCTAssertEqual(state.item(unnamed.id)?.title, "Old idea")
        XCTAssertEqual(state.item(renamed.id)?.hasTranscript, true)
    }

    func test_indexFromAnEarlierVersion_stillLoads() throws {
        let id = UUID()
        let json = """
        {"takes":[{"take":{"id":"\(id.uuidString)","createdAt":0,"duration":3,"version":1},\
        "status":"confirmed","phoneTransfer":"delivered","phoneReachableAtStop":true,"title":"Lighthouse café"}]}
        """
        let state = try JSONDecoder().decode(TakeQueueState.self, from: Data(json.utf8))
        XCTAssertEqual(state.item(id)?.title, "Lighthouse café")
        XCTAssertEqual(state.item(id)?.hasTranscript, false)
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

    func test_nextCloudAttempt_isNilWhenNothingWaitsOnTheWatch() {
        var state = TakeQueueState()
        XCTAssertNil(state.nextCloudAttempt(now: t0))
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.apply([WatchConfirmation(id: a.id, title: nil)])
        XCTAssertNil(state.nextCloudAttempt(now: t0.addingTimeInterval(10)))
    }

    func test_nextCloudAttempt_reachableTake_wakesWhenItBecomesEligible() {
        var state = TakeQueueState()
        state.add(take(), phoneReachableAtStop: true)   // 3 s long: eligible at t0 + 3 + 120
        XCTAssertEqual(state.nextCloudAttempt(now: t0.addingTimeInterval(10)), t0.addingTimeInterval(123))
    }

    func test_nextCloudAttempt_unreachableTake_retriesAfterTheInterval() {
        var state = TakeQueueState()
        state.add(take(), phoneReachableAtStop: false)   // already eligible: its upload failed
        let now = t0.addingTimeInterval(10)
        XCTAssertEqual(state.nextCloudAttempt(now: now), now.addingTimeInterval(TakeQueueState.cloudRetryInterval))
        XCTAssertEqual(state.nextCloudAttempt(now: now), t0.addingTimeInterval(10 + 900))
    }

    func test_nextCloudAttempt_takesTheSoonerOfEligibleAndRetry() {
        var state = TakeQueueState()
        state.add(take(), phoneReachableAtStop: true)
        state.add(take(1), phoneReachableAtStop: false)
        XCTAssertEqual(state.nextCloudAttempt(now: t0.addingTimeInterval(10)), t0.addingTimeInterval(123))
    }

    func test_idsRemoved_listsUndoneTakes() {
        var state = TakeQueueState()
        let a = take(), b = take(1)
        state.add(a, phoneReachableAtStop: true)
        state.add(b, phoneReachableAtStop: true)
        let before = state
        state.remove(a.id)
        XCTAssertEqual(state.idsRemoved(since: before), [a.id])
    }

    func test_idsRemoved_listsExactlyThePrunedTakes() {
        var state = TakeQueueState()
        let confirmed = (0..<25).map { take(TimeInterval($0)) }
        confirmed.forEach { state.add($0, phoneReachableAtStop: true) }
        let before = state
        state.apply(confirmed.map { WatchConfirmation(id: $0.id, title: nil) })
        XCTAssertEqual(Set(state.idsRemoved(since: before)), Set(confirmed.prefix(5).map(\.id)))
        XCTAssertEqual(state.idsRemoved(since: before).count, 5)
        XCTAssertTrue(TakeQueueState().idsRemoved(since: TakeQueueState()).isEmpty)
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
