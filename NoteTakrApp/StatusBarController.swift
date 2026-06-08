import AppKit
import SwiftUI
import NoteTakrCore

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: SessionStore
    private let recordingManager: RecordingManager
    private let vocabularyStore: VocabularyStore
    private let notificationScheduler = MeetingNotificationScheduler()
    private var sessionsWindow: NSPanel?
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

        recordingManager = RecordingManager(store: store, recorder: NativeAudioRecorder())

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "NoteTakr")
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

        calendarAdapter = EventKitCalendarAdapter()
        Task { await refreshNextMeeting() }
        Task { await notificationScheduler.requestPermission() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartRecordingFromNotification),
            name: .meetingNotificationStartRecording,
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

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openRecordingsFolder() {
        let folder = store.baseURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func openLatestNote() {
        let sessions = (try? store.loadAll()) ?? []
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
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: "NoteTakr")
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
        var mutable = session
        let isActiveSession = recordingManager.activeSession?.id == session.id

        let onTranscribe: (() -> Void)? = mutable.audioFilePaths.isEmpty ? nil : { [weak self] in
            guard let self else { return }
            let copy = mutable
            self.transcribeSession(copy)
        }
        let onGenerateNote: (() -> Void)? = { [weak self] in
            guard let self else { return }
            self.generateNote(for: mutable)
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
            onGenerateNote: onGenerateNote
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
    }

    private func transcribeSession(_ session: MeetingSession) {
        let vocab = (try? vocabularyStore.enabledEntries()) ?? []
        Task { @MainActor in
            guard let audioPath = session.audioFilePaths.first else { return }
            let audioURL = URL(fileURLWithPath: audioPath)
            let appSupportBase = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            let modelDir = appSupportBase.appendingPathComponent("NoteTakr/Models")
            do {
                let segments = try await FluidAudioAdapter(modelDirectory: modelDir)
                    .transcribe(audioURL: audioURL, vocabulary: vocab)
                var updated = session
                updated.transcriptSegments = segments
                try? self.store.save(updated)
            } catch TranscriptionError.modelUnavailable {
                let segments = (try? await MockTranscriptionEngine()
                    .transcribe(audioURL: audioURL, vocabulary: vocab)) ?? []
                var updated = session
                updated.transcriptSegments = segments
                try? self.store.save(updated)
            } catch {
                // Transcription failed — leave existing state.
            }
        }
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

    @MainActor
    private func refreshNextMeeting() async {
        isCalendarLoading = true
        calendarError = nil
        defer { isCalendarLoading = false }

        guard let adapter = calendarAdapter else { return }
        do {
            try await adapter.requestAccess()
            let now = Date()
            let tomorrow = now.addingTimeInterval(86_400)
            let events = try await adapter.fetchUpcomingEvents(from: now, to: tomorrow)
            if let top = MeetingDetector.nextMeeting(from: events, after: now) {
                nextCalendarMeeting = top.event
                nextMeetingMenuItem?.title = top.event.title
                nextMeetingMenuItem?.isEnabled = false
                notificationScheduler.scheduleReminder(for: top.event)
            }
        } catch {
            calendarError = "Calendar unavailable"
        }
    }
}
