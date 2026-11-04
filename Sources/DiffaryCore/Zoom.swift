/// Cmd-= / Cmd-- / Cmd-0 zoom for diffary's panels, mirroring Ghostty's
/// terminal font keys. The zoom is an offset on `appearance.font_size`.
public enum Zoom: Equatable, Sendable {
    case bigger, smaller, reset

    public static let sizes: ClosedRange<Double> = 6...72

    /// Which zoom a key press means, if any. Shift is allowed only for "+"
    /// (Cmd-Shift-= on US layouts).
    public static func step(characters: String, command: Bool, otherModifiers: Bool) -> Zoom? {
        guard command else { return nil }
        switch characters {
        case "+": return .bigger
        case "=": return otherModifiers ? nil : .bigger
        case "-": return otherModifiers ? nil : .smaller
        case "0": return otherModifiers ? nil : .reset
        default: return nil
        }
    }

    /// New offset after `step`, keeping base + offset within `sizes`.
    public static func apply(_ step: Zoom, offset: Double, base: Double) -> Double {
        let next: Double
        switch step {
        case .bigger: next = offset + 1
        case .smaller: next = offset - 1
        case .reset: return 0
        }
        return sizes.contains(base + next) ? next : offset
    }
}
