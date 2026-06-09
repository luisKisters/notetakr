import AppKit
import SwiftUI
import NoteTakrCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: SessionStore
    private let recordingManager: RecordingManager
    private let vocabularyStore: VocabularyStore
    private let transcriptionSettingsStore: TranscriptionSettingsStore
    private let fluidAudioRuntime: FluidAudioRuntime
    private let notificationScheduler = MeetingNotificationScheduler()
    private var sessionsWindow: NSPanel?
    private var detailWindow: NSPanel?
    private var detailCoordinator: TranscriptionCoordinator?
    private var calendarAdapter: (any CalendarAdapter)?
    private var nextCalendarMeeting: CalendarEvent?
    private var nextMeetingMenuItem: NSMenuItem?
    private var recordingMenuItem: NSMenuItem?
    private var isCalendarLoading = false
    private var calendarError: String? = nil

    override init() {
        let appSupportBase = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let appSupport = appSupportBase
            .appendingPathComponent("NoteTakr/Sessions", isDirectory: true)
        store = SessionStore(baseURL: appSupport)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? store.recoverInterruptedSessions()

        let vocabURL = appSupportBase
            .appendingPathComponent("NoteTakr/vocabulary.json")
        vocabularyStore = VocabularyStore(fileURL: vocabURL)
        transcriptionSettingsStore = TranscriptionSettingsStore(
            fileURL: appSupportBase
                .appendingPathComponent("NoteTakr", isDirectory: true)
                .appendingPathComponent("transcription-settings.json")
        )
        fluidAudioRuntime = FluidAudioRuntime()

        recordingManager = RecordingManager(store: store, recorder: NativeAudioRecorder())

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "NoteTakr")
            image?.isTemplate = true
            button.image = image
            button.title = "NoteTakr"
            button.imagePosition = .imageLeft
        }

        let meetingItem = NSMenuItem(title: "No upcoming meetings", action: nil, keyEquivalent: "")
        meetingItem.isEnabled = false
        nextMeetingMenuItem = meetingItem

        let quickItem = NSMenuItem(title: "Quick Recording", action: #selector(quickRecording), keyEquivalent: "")
        quickItem.target = self

        let recItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
        recItem.target = self
        recordingMenuItem = recItem

        let sessionsItem = NSMenuItem(title: "Sessions\u{2026}", action: #selector(showSessions), keyEquivalent: "")
        sessionsItem.target = self

        let openFolderItem = NSMenuItem(
            title: "Open Recordings Folder",
            action: #selector(openRecordingsFolder),
            keyEquivalent: ""
        )
        openFolderItem.target = self

        let openNoteItem = NSMenuItem(
            title: "Open Latest Note",
            action: #selector(openLatestNote),
            keyEquivalent: ""
        )
        openNoteItem.target = self

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let menu = NSMenu()
        menu.addItem(meetingItem)
        menu.addItem(.separator())
        menu.addItem(quickItem)
        menu.addItem(recItem)
        menu.addItem(sessionsItem)
        menu.addItem(.separator())
        menu.addItem(openFolderItem)
        menu.addItem(openNoteItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NoteTakr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        nextMeetingMenuItem?.title = "Grant Calendar Access in Settings"

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartRecordingFromNotification),
            name: .meetingNotificationStartRecording,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCalendarAccessGranted),
            name: .noteTakrCalendarAccessGranted,
            object: nil
        )
    }

    @objc private func handleStartRecordingFromNotification() {
        Task { @MainActor in
            guard !recordingManager.isRecording else { return }
            let title = nextCalendarMeeting?.title ?? "Meeting Recording"
            do {
                _ = try await recordingManager.startRecording(title: title)
                updateRecordingUI()
                showSessions()
            } catch {
                // Recording start failed — continue without recording.
            }
        }
    }

    @objc private func handleCalendarAccessGranted() {
        if calendarAdapter == nil {
            calendarAdapter = EventKitCalendarAdapter()
        }
        Task { await refreshNextMeeting() }
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .noteTakrShowSettingsWindow, object: nil)
    }

    @objc private func openRecordingsFolder() {
        let folder = store.baseURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func openLatestNote() {
        let sessions = ((try? store.loadAll()) ?? []).sorted { $0.date > $1.date }
        for session in sessions {
            let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
            if FileManager.default.fileExists(atPath: noteURL.path) {
                NSWorkspace.shared.open(noteURL)
                return
            }
        }
        openRecordingsFolder()
    }

    @objc private func quickRecording() {
        Task { @MainActor in
            guard !recordingManager.isRecording else { return }
            do {
                _ = try await recordingManager.startRecording(title: "Quick Recording")
                updateRecordingUI()
                showSessions()
            } catch {
                // Recording start failed — ignore silently.
            }
        }
    }

    @objc private func toggleRecording() {
        if recordingManager.isRecording {
            Task { @MainActor in
                _ = try? await recordingManager.stopRecording()
                updateRecordingUI()
                showSessions()
            }
        } else {
            Task { @MainActor in
                do {
                    let title = nextCalendarMeeting?.title ?? "Meeting Recording"
                    _ = try await recordingManager.startRecording(title: title)
                    updateRecordingUI()
                    showSessions()
                } catch {
                    // Recording start failed — ignore silently.
                }
            }
        }
    }

    @MainActor
    private func updateRecordingUI() {
        let isRecording = recordingManager.isRecording
        recordingMenuItem?.title = isRecording ? "Stop Recording" : "Start Recording"
        if let button = statusItem.button {
            let name = isRecording ? "mic.circle.fill" : "mic.circle"
            let image = NSImage(systemSymbolName: name, accessibilityDescription: "NoteTakr")
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = isRecording ? .systemRed : nil
        }
    }

    @objc private func showSessions() {
        if let existing = sessionsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        sessionsWindow?.close()
        let sessions = (try? store.loadAll()) ?? []
        let view = TodayView(
            sessions: sessions,
            nextMeeting: nextCalendarMeeting,
            isLoading: isCalendarLoading,
            errorMessage: calendarError
        ) { [weak self] session in
            guard let self else { return }
            self.showSessionDetail(session)
        } onStopRecording: { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                _ = try? await self.recordingManager.stopRecording()
                self.updateRecordingUI()
            }
        }
        let hostingController = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentViewController = hostingController
        window.title = "Sessions"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sessionsWindow = window
    }

    private func showSessionDetail(_ session: MeetingSession) {
        detailWindow?.close()
        var mutable = session
        let isActiveSession = recordingManager.activeSession?.id == session.id

        let coordinator = TranscriptionCoordinator()
        detailCoordinator = coordinator

        let onTranscribe: (() -> Void)? = mutable.audioFilePaths.isEmpty ? nil : { [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            let sessionSnapshot = mutable
            Task { @MainActor in
                let vocab = (try? self.vocabularyStore.enabledEntries()) ?? []
                let engine = FluidAudioAdapter(
                    settingsStore: self.transcriptionSettingsStore,
                    runtime: self.fluidAudioRuntime
                )
                let service = TranscriptionService(engine: engine, store: self.store)
                if let updated = await coordinator.transcribe(
                    session: sessionSnapshot, service: service, vocabulary: vocab
                ) {
                    self.detailWindow?.close()
                    self.showSessionDetail(updated)
                }
            }
        }
        let onGenerateNote: (() -> Void)? = { [weak self] in
            guard let self else { return }
            self.generateNote(for: mutable)
        }
        let onOpenNote: (() -> Void)? = { [weak self] in
            guard let self else { return }
            self.openNote(for: mutable)
        }

        let view = SessionDetailView(
            session: Binding(get: { mutable }, set: { [self] in mutable = $0; try? self.store.save($0) }),
            isActiveRecording: isActiveSession,
            onStopRecording: isActiveSession ? { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    _ = try? await self.recordingManager.stopRecording()
                    self.updateRecordingUI()
                }
            } : nil,
            onTranscribe: onTranscribe,
            onGenerateNote: onGenerateNote,
            onOpenNote: onOpenNote,
            transcriptionCoordinator: coordinator
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentViewController = hostingController
        window.title = session.title
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        detailWindow = window
    }

    private func generateNote(for session: MeetingSession) {
        let markdown = MarkdownNoteRenderer.render(session: session)
        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        do {
            try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(noteURL)
        } catch {
            // Note save failed — ignore silently.
        }
    }

    private func openNote(for session: MeetingSession) {
        let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
        if FileManager.default.fileExists(atPath: noteURL.path) {
            NSWorkspace.shared.open(noteURL)
        } else {
            generateNote(for: session)
        }
    }

    @MainActor
    private func refreshNextMeeting() async {
        isCalendarLoading = true
        calendarError = nil
        defer { isCalendarLoading = false }

        guard let adapter = calendarAdapter else { return }
        guard adapter.hasAccess else {
            nextCalendarMeeting = nil
            nextMeetingMenuItem?.title = "Grant Calendar Access in Settings"
            nextMeetingMenuItem?.isEnabled = false
            calendarError = "Calendar access not granted"
            return
        }

        do {
            let now = Date()
            let tomorrow = now.addingTimeInterval(86_400)
            let events = try await adapter.fetchUpcomingEvents(from: now, to: tomorrow)
            if let top = MeetingDetector.nextMeeting(from: events, after: now) {
                nextCalendarMeeting = top.event
                nextMeetingMenuItem?.title = top.event.title
                nextMeetingMenuItem?.isEnabled = false
                notificationScheduler.scheduleReminder(for: top.event)
            } else {
                nextCalendarMeeting = nil
                nextMeetingMenuItem?.title = "No upcoming meetings"
                nextMeetingMenuItem?.isEnabled = false
            }
        } catch {
            calendarError = "Calendar unavailable"
        }
    }
}
