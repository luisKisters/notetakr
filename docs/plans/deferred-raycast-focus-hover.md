# Plan (DEFERRED — not yet running): Raycast-style focus + hover-only close

User flagged as minor; behaviorally risky, so it's parked until the core fixes land.

## Goal
- Typing in NoteTakr should NOT steal focus from the previously-active app (Raycast notes style).
- The window close button should appear only when the window is hovered.

## Notes for when we pick this up
- `NotePanelController.show()` calls `NSApp.activate(ignoringOtherApps: true)` which yanks focus to NoteTakr. The panel is already `.nonactivatingPanel`. Removing/relaxing the explicit activate is the lever — but then verify the editor still receives keystrokes (a nonactivating panel can be key without activating the app). Test typing carefully; this is the risky part.
- Hover-only close: track window hover (an NSTrackingArea on the content view, or a SwiftUI `.onHover` on the chrome) and toggle `panel.standardWindowButton(.closeButton)?.isHidden`. `WindowChromeView` reserves the top-left space already.

## Checklist
- [x] Make the panel not steal focus from the active app while still accepting typing.
- [x] Show the close button only on window hover.
- [x] Verify typing + global hotkey still work in the worktree-built app.
