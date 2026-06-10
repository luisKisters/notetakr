# NoteTakr Redesign — Design Ideas & Open Questions

> **STATUS: DECIDED.** The final locked design lives in `final-editor.html`,
> `final-switcher.html`, `final-settings.html` (round 5). Everything below is the
> exploration history. Locked spec summary:
>
> - **Window**: one floating panel, compact portrait ~420×620, radius 16, global hotkey toggle.
> - **Identity**: monochrome + purple accent (#8B5CF6 / #A78BFA), red dot only for REC,
>   green/orange only in permission rows. Inline SVG icons (SF-style, 1.5px stroke), no emojis,
>   no badges, no word count. Subtle film grain. NOT a Raycast clone.
> - **Appearance setting (3-way)**: Glass (blur 40px + saturate 1.5, hairline top highlight) /
>   Dark (solid purple-tinted #151417) / Light (warm paper).
> - **Editor**: no chrome title, dimmed traffic lights, hover-only gear top-right. H1 title,
>   then frontmatter as a row of quiet chips (clock·time, camera·Zoom, people·avatar initials,
>   REC·red dot + timer) that click-expands into a soft property panel (Date, Calendar event,
>   Participants, Location, In-person toggle, Transcript). Footer = ONLY three bare text tabs:
>   Private Notes · Summary · Transcript (active = purple, inactive 45%, no separators).
> - **⌘K switcher**: "Timeline Lite" — palette rows (icon + title + right-aligned time) grouped
>   by day, threaded by a barely-there 1px vertical line that fades at both ends; node dots on
>   EVERY row (hollow purple = upcoming, filled purple glow = current, neutral 30% = past);
>   ghost dashed "Create note" rows for upcoming calendar events; appears as a frost layer over
>   the blurred note; footer kbd hints.
> - **Settings**: bottom sheet (~85%, no grabber) over the blurred note with icon tabs:
>   This Meeting · General · Recording · Vocabulary · Permissions. "This Meeting" shows a
>   purple-tinted scope banner ("…applies only to this note") and per-meeting controls
>   (transcribe toggle + live timer, language, in-person, linked event, per-meeting vocabulary).
>   "General" = same options as defaults for new meetings (transcribe ON, language Auto-detect
>   with a warning when a fixed language is chosen, in-person default) + app settings (hotkey,
>   launch at login, Appearance trio, notes folder). Bottom row: quiet "Close" + esc kbd pill.

Concept: **Raycast Notes, but built for meetings.** One floating window, toggled with a
global hotkey (currently ⌥⌘N). Markdown notes with meeting *frontmatter* (metadata above
the body). ⌘K switches between meeting notes. Settings live behind a gear at the
bottom-right with two scopes: **Meeting settings** (per-note) and **General settings**.

Mockups (5 variations each, open in a browser):

- `01-editor.html` — main note editor
- `02-switcher.html` — ⌘K meeting switcher
- `03-settings.html` — settings surface

---

## Screen 1: Editor (`01-editor.html`)

| # | Name | Core idea | Frontmatter | Recording |
|---|------|-----------|-------------|-----------|
| 1 | Raycast Twin | Closest to Raycast Notes | Collapsed one-line strip → expands to property table | Red-dot pill in the strip |
| 2 | Glass | Liquid-glass / vibrancy panel | Glass chips row under title | Pulsing REC chip |
| 3 | Paper | Light, paper-like notepad | Always-visible property table (Obsidian style) | Thin waveform + timer in footer |
| 4 | Split Live | Notes + live transcript side by side | In recording header strip | First-class: header w/ stop button |
| 5 | Zen + ⓘ | Pure black, chrome hidden until hover | Fully hidden, ⓘ reveals glass overlay | 2px red glow on window edge |

Open questions this screen should answer:
- [ ] How visible should frontmatter be by default? (strip vs. table vs. hidden)
- [ ] Is the transcript part of the note window or hidden behind a toggle?
- [ ] Dark-only, light-only, or follow system?
- [ ] Does recording state belong in the chrome, the frontmatter, or the footer?

## Screen 2: ⌘K Switcher (`02-switcher.html`)

| # | Name | Core idea |
|---|------|-----------|
| 1 | Palette Overlay | Raycast-style palette over dimmed editor, grouped by day, upcoming events on top |
| 2 | Sidebar Slide-in | 260px notes list slides in next to the editor |
| 3 | Card Grid | Searchable grid of meeting cards with excerpts (light variant) |
| 4 | Agenda Timeline | Calendar events + notes merged chronologically; doubles as meeting prep |
| 5 | Mini Bar + Preview | Spotlight-style bar + frontmatter preview pane |

Open questions:
- [ ] Should upcoming calendar events (no note yet) appear in the switcher with "Create note"?
- [ ] Is ⌘K a transient overlay (palette) or a persistent panel (sidebar)?
- [ ] Pinning? Grouping by day vs. flat fuzzy search?

## Screen 3: Settings (`03-settings.html`)

| # | Name | Core idea |
|---|------|-----------|
| 1 | Gear Popover | Compact popover at the gear, [Meeting \| General] segmented |
| 2 | Morph In-Window | Window morphs into a full settings page with icon sidebar |
| 3 | Bottom Sheet | Sheet slides up over dimmed editor |
| 4 | Native Tabs, Glassy | System-Settings-style toolbar tabs, glass material |
| 5 | Footer Drawer | Footer expands into a quick-settings drawer, note stays visible |

Open questions:
- [ ] Are "Meeting settings" frequent enough to deserve one-click access (popover/drawer),
      or rare enough for a full page (morph/tabs)?
- [ ] Where do permissions live — General settings or a first-run flow?

---

## Frontmatter schema (draft)

Stored as YAML frontmatter at the top of each note's markdown file (Obsidian-compatible),
replacing/extending today's `session.json`:

```yaml
---
title: Weekly Sync — Acme GmbH
date: 2026-06-09T14:00
end: 2026-06-09T14:45
calendar_event: <eventkit-identifier>
participants: [Luis Kisters, Sarah Chen, Tom Müller]
location: zoom            # zoom | meet | teams | in-person | none
in_person: false
recording: true
transcript: transcript.md  # or embedded
---
```

Decisions needed:
- [ ] One file per meeting (`note.md` with frontmatter) vs. keeping `session.json` alongside?
      Frontmatter-in-markdown wins for portability/Obsidian interop.
- [ ] Participants as plain strings now; CRM-linked objects later (see `ideas/participants-crm.md`).

## Migration notes (current app → redesign)

- Today: menu-bar app + two NSPanels (`TodayView`, `SessionDetailView`) + Settings scene.
- Redesign collapses these into one NSPanel; menu bar item stays as a secondary toggle.
- `SessionStore` folders can stay; `note.md` becomes the source of truth with frontmatter.
- Existing pieces that carry over: FluidAudio transcription, `MeetingDetector`,
  `EventKitCalendarAdapter`, vocabulary boosting, notification scheduler.
