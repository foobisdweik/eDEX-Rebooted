import Foundation

public enum AugmentedCorner: CaseIterable, Hashable, Sendable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

public struct AugmentedPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
    }
}

public struct AugmentedSegment: Equatable, Sendable {
    public let start: AugmentedPoint
    public let end: AugmentedPoint

    public init(start: AugmentedPoint, end: AugmentedPoint) {
        self.start = start
        self.end = end
    }
}

public struct AugmentedBorderSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width.isFinite ? max(0, width) : 0
        self.height = height.isFinite ? max(0, height) : 0
    }
}

public struct AugmentedBorderStyle: Equatable, Sendable {
    public let corners: Set<AugmentedCorner>
    public let clipLength: Double
    public let borderWidth: Double
    public let borderOpacity: Double
    public let tickLength: Double
    public let tickOpacity: Double

    public init(
        corners: Set<AugmentedCorner>,
        clipLength: Double,
        borderWidth: Double,
        borderOpacity: Double,
        tickLength: Double,
        tickOpacity: Double
    ) {
        self.corners = corners
        self.clipLength = clipLength.sanitizedPositive
        self.borderWidth = borderWidth.sanitizedPositive
        self.borderOpacity = borderOpacity.clamped01
        self.tickLength = tickLength.sanitizedPositive
        self.tickOpacity = tickOpacity.clamped01
    }

    public static func mainShell(vh: Double) -> AugmentedBorderStyle {
        AugmentedBorderStyle(
            corners: [.topRight, .bottomLeft],
            clipLength: 0.5 * vh.sanitizedPositive,
            borderWidth: 0.18 * vh.sanitizedPositive,
            borderOpacity: 0.5,
            tickLength: 2.4 * vh.sanitizedPositive,
            tickOpacity: 0.62
        )
    }

    public static func panel(vh: Double) -> AugmentedBorderStyle {
        AugmentedBorderStyle(
            corners: [],
            clipLength: 0,
            borderWidth: 0.092 * vh.sanitizedPositive,
            borderOpacity: 0.3,
            tickLength: 1.8 * vh.sanitizedPositive,
            tickOpacity: 0.58
        )
    }

    public static func settingsButton(vh: Double) -> AugmentedBorderStyle {
        AugmentedBorderStyle(
            corners: [.topLeft, .bottomRight],
            clipLength: 0.5 * vh.sanitizedPositive,
            borderWidth: 0.092 * vh.sanitizedPositive,
            borderOpacity: 0.6,
            tickLength: 1.2 * vh.sanitizedPositive,
            tickOpacity: 0.62
        )
    }

    public static func modal(vh: Double) -> AugmentedBorderStyle {
        AugmentedBorderStyle(
            corners: [.topRight, .bottomLeft],
            clipLength: 0.5 * vh.sanitizedPositive,
            borderWidth: 0.2 * vh.sanitizedPositive,
            borderOpacity: 0.78,
            tickLength: 2.2 * vh.sanitizedPositive,
            tickOpacity: 0.68
        )
    }
}

public struct AugmentedBorderGeometry: Equatable, Sendable {
    public let size: AugmentedBorderSize
    public let style: AugmentedBorderStyle

    public init(size: AugmentedBorderSize, style: AugmentedBorderStyle) {
        self.size = size
        self.style = style
    }

    public var effectiveClipLength: Double {
        min(style.clipLength, min(size.width, size.height) / 2)
    }

    public var outlinePoints: [AugmentedPoint] {
        let clip = effectiveClipLength
        let width = size.width
        let height = size.height

        var points = [AugmentedPoint]()
        if style.corners.contains(.topLeft) {
            points.append(AugmentedPoint(x: clip, y: 0))
        } else {
            points.append(AugmentedPoint(x: 0, y: 0))
        }

        if style.corners.contains(.topRight) {
            points.append(AugmentedPoint(x: width - clip, y: 0))
            points.append(AugmentedPoint(x: width, y: clip))
        } else {
            points.append(AugmentedPoint(x: width, y: 0))
        }

        if style.corners.contains(.bottomRight) {
            points.append(AugmentedPoint(x: width, y: height - clip))
            points.append(AugmentedPoint(x: width - clip, y: height))
        } else {
            points.append(AugmentedPoint(x: width, y: height))
        }

        if style.corners.contains(.bottomLeft) {
            points.append(AugmentedPoint(x: clip, y: height))
            points.append(AugmentedPoint(x: 0, y: height - clip))
        } else {
            points.append(AugmentedPoint(x: 0, y: height))
        }

        return points
    }

    public var tickSegments: [AugmentedSegment] {
        let tickLength = min(style.tickLength, max(0, size.width / 2))
        guard tickLength > 0 else { return [] }

        return [
            AugmentedSegment(
                start: AugmentedPoint(x: leftTopInset, y: 0),
                end: AugmentedPoint(x: leftTopInset + tickLength, y: 0)
            ),
            AugmentedSegment(
                start: AugmentedPoint(x: max(0, size.width - rightBottomInset - tickLength), y: size.height),
                end: AugmentedPoint(x: size.width - rightBottomInset, y: size.height)
            )
        ]
    }

    private var leftTopInset: Double {
        style.corners.contains(.topLeft) ? effectiveClipLength : 0
    }

    private var rightBottomInset: Double {
        style.corners.contains(.bottomRight) ? effectiveClipLength : 0
    }
}

private extension Double {
    var sanitizedPositive: Double {
        isFinite ? max(0, self) : 0
    }

    var clamped01: Double {
        guard isFinite else { return 0 }
        return min(1, max(0, self))
    }
}
