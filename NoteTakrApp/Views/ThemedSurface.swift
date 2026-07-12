import AppKit
import SwiftUI
import NoteTakrKit

/// Unified themed surface used for window body, ⌘K palette, settings, and menus.
/// Glass: real macOS backdrop blur (no purple tint, no scrim) + a faint white lift.
/// Dark/Light: solid themed background.
struct ThemedSurface: View {
    let appearance: Appearance

    var body: some View {
        ZStack {
            switch appearance {
            case .glass:
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                Theme.glass.background.swiftUIColor
            case .dark:
                Theme.dark.background.swiftUIColor
            case .light:
                Theme.light.background.swiftUIColor
            }
            SubtleGrainOverlay()
        }
    }
}

private struct SubtleGrainOverlay: View {
    var body: some View {
        Image(nsImage: Self.image)
            .resizable(resizingMode: .tile)
            .interpolation(.none)
            .opacity(0.035)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }

    private static let image: NSImage = {
        let size = 160
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        for y in 0..<size {
            for x in 0..<size {
                let hash = UInt32(truncatingIfNeeded: x &* 73_856_093)
                    ^ UInt32(truncatingIfNeeded: y &* 19_349_663)
                let white = CGFloat(hash & 0xff) / 255.0
                rep.setColor(NSColor(calibratedWhite: white, alpha: 1), atX: x, y: y)
            }
        }

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }()
}
