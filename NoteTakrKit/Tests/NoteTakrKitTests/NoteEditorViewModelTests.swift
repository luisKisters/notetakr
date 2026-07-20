import XCTest
@testable import NoteTakrKit

final class NoteEditorViewModelTests: XCTestCase {

    // MARK: - Debounce: two edits within the window → exactly one save

    func testTypingTwiceCausesOneSave() throws {
        let (vm, spy, scheduler) = makeVM(id: "n1", title: "T", body: "")

        try vm.load(noteID: "n1")
        vm.setBody("First edit")
        vm.setBody("Second edit")

        XCTAssertEqual(scheduler.pendingCount, 1, "Two rapid edits should collapse to one pending debounce")
        scheduler.fireAll()
        XCTAssertEqual(spy.saveCallCount, 1, "Exactly one save after debounce fires")
        XCTAssertFalse(vm.isDirty)
    }

    // MARK: - Flush cancels pending debounce and saves exactly once

    func testFlushCancelsPendingAndSavesOnce() throws {
        let (vm, spy, scheduler) = makeVM(id: "n1", title: "T", body: "")

        try vm.load(noteID: "n1")
        vm.setBody("Some text")

        XCTAssertTrue(scheduler.hasPending)
        try vm.flush()

        XCTAssertFalse(scheduler.hasPending, "Flush must cancel the pending debounce")
        XCTAssertEqual(spy.saveCallCount, 1)
        XCTAssertFalse(vm.isDirty)

        scheduler.fireAll()
        XCTAssertEqual(spy.saveCallCount, 1, "No additional save after flush clears dirty flag")
    }

    // MARK: - Title change persists via store (triggers rename path in real store)

    func testTitleChangeSavedCorrectly() throws {
        let (vm, spy, scheduler) = makeVM(id: "n1", title: "Old Title", body: "")

        try vm.load(noteID: "n1")
        vm.setTitle("New Title")

        XCTAssertEqual(vm.title, "New Title")
        scheduler.fireAll()

        XCTAssertEqual(spy.saveCallCount, 1)
        XCTAssertEqual(spy.lastSaved?.title, "New Title")
    }

    func testDebouncedBodySavePreservesLatestFrontmatterChanges() throws {
        let (vm, spy, scheduler) = makeVM(id: "n1", title: "T", body: "")

        try vm.load(noteID: "n1")
        vm.setBody("Edited body")

        var latest = try XCTUnwrap(spy.load(id: "n1"))
        latest.participants = [Participant(name: "Ada Lovelace", email: "ada@example.test")]
        spy.add(latest)

        scheduler.fireAll()

        XCTAssertEqual(spy.saveCallCount, 1)
        XCTAssertEqual(spy.lastSaved?.body, "Edited body")
        XCTAssertEqual(spy.lastSaved?.participants, [
            Participant(name: "Ada Lovelace", email: "ada@example.test")
        ])
    }

    func testFlushPreservesLatestFrontmatterChanges() throws {
        let (vm, spy, scheduler) = makeVM(id: "n1", title: "Old Title", body: "")

        try vm.load(noteID: "n1")
        vm.setTitle("New Title")

        var latest = try XCTUnwrap(spy.load(id: "n1"))
        latest.participants = [Participant(name: "Ada Lovelace")]
        spy.add(latest)

        try vm.flush()

        XCTAssertFalse(scheduler.hasPending)
        XCTAssertEqual(spy.saveCallCount, 1)
        XCTAssertEqual(spy.lastSaved?.title, "New Title")
        XCTAssertEqual(spy.lastSaved?.participants, [Participant(name: "Ada Lovelace")])
    }

    // MARK: - Loading a new note flushes the previous one

    func testLoadNewNoteFlushesOldOne() throws {
        let spy = StoreSpy()
        let n1 = makeNote(id: "n1", title: "First", body: "")
        let n2 = makeNote(id: "n2", title: "Second", body: "")
        spy.add(n1); spy.add(n2)
        let scheduler = TestScheduler()
        let vm = NoteEditorViewModel(store: spy, scheduler: scheduler)

        try vm.load(noteID: "n1")
        vm.setBody("Edited first note")
        XCTAssertTrue(scheduler.hasPending)

        try vm.load(noteID: "n2")

        XCTAssertFalse(scheduler.hasPending, "Load must have flushed and cancelled pending debounce")
        XCTAssertEqual(spy.saveCallCount, 1, "Previous note saved on flush")
        XCTAssertEqual(spy.lastSaved?.id, "n1", "Saved note should be n1")
        XCTAssertEqual(vm.title, "Second", "ViewModel now shows n2")
        XCTAssertFalse(vm.isDirty)
    }

    // MARK: - No save when not dirty

    func testNoSaveWhenNotDirty() throws {
        let (vm, spy, scheduler) = makeVM(id: "n1", title: "T", body: "")

        try vm.load(noteID: "n1")
        try vm.flush()

        XCTAssertEqual(spy.saveCallCount, 0)
        scheduler.fireAll()
        XCTAssertEqual(spy.saveCallCount, 0)
    }

    // MARK: - onChange fired after load and edits

    func testOnChangeCalledAfterLoad() throws {
        let (vm, _, _) = makeVM(id: "n1", title: "T", body: "")
        var callCount = 0
        vm.onChange = { callCount += 1 }

        try vm.load(noteID: "n1")
        XCTAssertEqual(callCount, 1)
    }

    func testOnChangeCalledOnBodyEdit() throws {
        let (vm, _, _) = makeVM(id: "n1", title: "T", body: "")
        try vm.load(noteID: "n1")
        var callCount = 0
        vm.onChange = { callCount += 1 }

        vm.setBody("hello")
        XCTAssertEqual(callCount, 1)
    }

    func testOnChangeCalledOnTitleEdit() throws {
        let (vm, _, _) = makeVM(id: "n1", title: "T", body: "")
        try vm.load(noteID: "n1")
        var callCount = 0
        vm.onChange = { callCount += 1 }

        vm.setTitle("New Title")
        XCTAssertEqual(callCount, 1)
    }

    func testGeneratedSessionMarkdownDoesNotAppearInNotes() throws {
        let generated = """
        # Recorded meeting

        **Date:** July 20, 2026 at 10:00
        **Status:** stopped

        ## Audio Sources

        - **Microphone:** Captured

        ## Transcript

        **[0:00] Speaker 1:** Generated words
        """
        let (vm, _, _) = makeVM(id: "n1", title: "T", body: generated)

        try vm.load(noteID: "n1")

        XCTAssertEqual(vm.body, "")
    }

    func testPersonalNotesAreExtractedFromGeneratedSessionMarkdown() throws {
        let generated = """
        # Recorded meeting

        **Status:** stopped

        ## Personal Notes

        User-authored thought
        with a second line

        ## Transcript

        **[0:00] Speaker 1:** Generated words
        """
        let (vm, _, _) = makeVM(id: "n1", title: "T", body: generated)

        try vm.load(noteID: "n1")

        XCTAssertEqual(vm.body, "User-authored thought\nwith a second line")
    }

    func testOrdinaryUserMarkdownRemainsUntouched() throws {
        let notes = "## My thoughts\n\nOnly I wrote this."
        let (vm, _, _) = makeVM(id: "n1", title: "T", body: notes)

        try vm.load(noteID: "n1")

        XCTAssertEqual(vm.body, notes)
    }

    // MARK: - setBody/setTitle is no-op before load

    func testSetBodyBeforeLoadIsNoop() {
        let spy = StoreSpy()
        let scheduler = TestScheduler()
        let vm = NoteEditorViewModel(store: spy, scheduler: scheduler)

        vm.setBody("ignored")

        XCTAssertFalse(scheduler.hasPending)
        XCTAssertFalse(vm.isDirty)
    }

    // MARK: - Helpers

    private func makeVM(
        id: String, title: String, body: String
    ) -> (NoteEditorViewModel, StoreSpy, TestScheduler) {
        let spy = StoreSpy()
        spy.add(makeNote(id: id, title: title, body: body))
        let scheduler = TestScheduler()
        let vm = NoteEditorViewModel(store: spy, scheduler: scheduler)
        return (vm, spy, scheduler)
    }

    private func makeNote(id: String, title: String, body: String) -> MeetingNote {
        MeetingNote(id: id, title: title, date: Date(), body: body)
    }
}

// MARK: - Test doubles

final class TestScheduler: Scheduler {
    private struct Pending {
        let delay: TimeInterval
        let work: () -> Void
    }

    private var pending: [String: Pending] = [:]

    var hasPending: Bool { !pending.isEmpty }
    var pendingCount: Int { pending.count }

    func schedule(id: String, delay: TimeInterval, work: @escaping () -> Void) {
        pending[id] = Pending(delay: delay, work: work)
    }

    func cancel(id: String) {
        pending.removeValue(forKey: id)
    }

    func fire(id: String) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.work()
    }

    func fireAll() {
        let snapshot = pending
        pending.removeAll()
        snapshot.values.forEach { $0.work() }
    }
}

final class StoreSpy: NoteStoring {
    private var notes: [String: MeetingNote] = [:]
    private(set) var saveCallCount = 0
    private(set) var savedNotes: [MeetingNote] = []
    var lastSaved: MeetingNote? { savedNotes.last }

    func add(_ note: MeetingNote) {
        notes[note.id] = note
    }

    func load(id: String) throws -> MeetingNote? {
        notes[id]
    }

    func save(_ note: MeetingNote) throws {
        saveCallCount += 1
        savedNotes.append(note)
        notes[note.id] = note
    }
}
