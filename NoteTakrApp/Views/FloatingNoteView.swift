import SwiftUI
import NoteTakrCore

/// The contents of the floating note panel: an editable meeting title and
/// calendar-event / mode selectors over a markdown scratchpad, with a word
/// count and an edit/preview toggle along the bottom.
struct FloatingNoteView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var titleFocused: Bool
    @State private var isPreviewing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            editorOrPreview
            Divider().opacity(0.4)
            footer
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 360, minHeight: 420)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Editable meeting title. Auto-filled from the calendar event but
            // overridable; empty shows the "Unnamed Meeting" placeholder.
            TextField("Unnamed Meeting", text: $model.floatingMeetingName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
                .focused($titleFocused)
                .accessibilityIdentifier("floatingMeetingTitle")

            HStack(spacing: 8) {
                eventPicker
                modePicker
                Spacer(minLength: 8)
                recordButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28) // clear the transparent title bar
        .padding(.bottom, 12)
    }

    private var eventPicker: some View {
        Menu {
            Button("No calendar event") {
                model.selectFloatingEvent(nil)
            }
            if !model.upcomingEvents.isEmpty {
                Divider()
                ForEach(model.upcomingEvents) { event in
                    Button {
                        model.selectFloatingEvent(event)
                    } label: {
                        Text(eventLabel(event))
                    }
                }
            }
        } label: {
            Label(currentEventLabel, systemImage: "calendar")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Link a calendar event")
        .accessibilityIdentifier("floatingEventPicker")
    }

    private var modePicker: some View {
        Menu {
            ForEach(MeetingMode.allCases, id: \.self) { mode in
                Button {
                    model.floatingMode = mode
                } label: {
                    if model.floatingMode == mode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            Label(model.floatingMode.displayName, systemImage: modeIcon)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("In-person meetings record the microphone only and separate speakers automatically")
        .accessibilityIdentifier("floatingModePicker")
    }

    private var recordButton: some View {
        Button {
            Task {
                if model.isRecording {
                    await model.stopRecording()
                } else {
                    await model.startFloatingRecording()
                }
            }
        } label: {
            Label(
                model.isRecording ? "Stop" : "Record",
                systemImage: model.isRecording ? "stop.circle.fill" : "record.circle"
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isRecording ? .red : .accentColor)
        .controlSize(.small)
        .accessibilityIdentifier("floatingRecordButton")
    }

    // MARK: - Editor / preview

    @ViewBuilder
    private var editorOrPreview: some View {
        if isPreviewing {
            MarkdownPreview(text: model.floatingNoteText)
        } else {
            TextEditor(text: $model.floatingNoteText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .onChange(of: model.floatingNoteText) { _ in
                    model.syncFloatingNote()
                }
                .accessibilityIdentifier("floatingNoteEditor")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(wordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                isPreviewing.toggle()
            } label: {
                Image(systemName: isPreviewing ? "pencil" : "textformat")
            }
            .buttonStyle(.borderless)
            .help(isPreviewing ? "Edit" : "Preview formatting")
            .accessibilityIdentifier("floatingPreviewToggle")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var wordCount: Int {
        model.floatingNoteText
            .split { $0 == " " || $0 == "\n" || $0 == "\t" }
            .count
    }

    private var modeIcon: String {
        model.floatingMode == .inPerson ? "person.2.wave.2" : "video"
    }

    private var currentEventLabel: String {
        if let event = model.floatingSelectedEvent {
            return event.title
        }
        return "No event"
    }

    private func eventLabel(_ event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return "\(event.title) · \(formatter.string(from: event.startDate))"
    }
}

/// A lightweight markdown preview: renders headings, bullets and inline
/// emphasis line-by-line so the scratchpad's formatting is visible without a
/// full markdown engine.
struct MarkdownPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    rendered(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var lines: [String] {
        text.components(separatedBy: "\n")
    }

    @ViewBuilder
    private func rendered(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# ") {
            Text(inline(String(trimmed.dropFirst(2))))
                .font(.title.bold())
        } else if trimmed.hasPrefix("## ") {
            Text(inline(String(trimmed.dropFirst(3))))
                .font(.title2.bold())
        } else if trimmed.hasPrefix("### ") {
            Text(inline(String(trimmed.dropFirst(4))))
                .font(.title3.bold())
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                Text(inline(String(trimmed.dropFirst(2))))
            }
        } else if trimmed.isEmpty {
            Text(" ").font(.system(size: 6))
        } else {
            Text(inline(line))
        }
    }

    private func inline(_ content: String) -> AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
    }
}
