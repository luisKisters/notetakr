/// Pure model for a settings row's interaction state.
/// Allows Linux-testable unit tests to verify that hover and selection are distinct,
/// and that a row's primary action fires regardless of the tap region.
public struct SettingsRowModel {
    public var isHovering: Bool

    public init(isHovering: Bool = false) {
        self.isHovering = isHovering
    }

    /// Background highlight is driven only by hover, never by selection or active state.
    public var showsHoverHighlight: Bool { isHovering }

    public mutating func setHover(_ inside: Bool) {
        isHovering = inside
    }
}

/// Models a toggle-style settings row.
/// The same activate() action fires regardless of which region of the row was tapped —
/// icon, label text, spacer area, or the switch control itself.
public struct SettingsToggleRowModel {
    public var isOn: Bool
    public var hoverState: SettingsRowModel

    public init(isOn: Bool = false) {
        self.isOn = isOn
        self.hoverState = SettingsRowModel()
    }

    public mutating func activate() {
        isOn.toggle()
    }
}
