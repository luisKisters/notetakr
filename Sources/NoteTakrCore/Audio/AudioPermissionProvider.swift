import Foundation

public enum PermissionStatus: String, Sendable, Equatable, CaseIterable {
    case notDetermined
    case granted
    case denied
}
