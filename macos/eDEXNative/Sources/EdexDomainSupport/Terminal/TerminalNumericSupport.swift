import Foundation

enum TerminalNumericSupport {
    static func clampedDimension(_ value: Double?, default defaultValue: UInt16) -> UInt16 {
        guard let value else { return max(1, defaultValue) }
        if value.isNaN || (value.isInfinite && value > 0) {
            return max(1, defaultValue)
        }
        if value.isInfinite && value < 0 {
            return 1
        }
        if value > Double(UInt16.max) {
            return max(1, defaultValue)
        }
        if value < 1 {
            return 1
        }
        return UInt16(value)
    }
}
