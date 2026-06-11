import Foundation

public struct LayoutSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width.isFinite ? max(0, width) : 0
        self.height = height.isFinite ? max(0, height) : 0
    }
}

public struct LayoutRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let isHidden: Bool

    public init(x: Double, y: Double, width: Double, height: Double, isHidden: Bool = false) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
        self.width = width.isFinite ? max(0, width) : 0
        self.height = height.isFinite ? max(0, height) : 0
        self.isHidden = isHidden
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func intersects(_ other: LayoutRect) -> Bool {
        guard !isHidden, !other.isHidden else { return false }
        guard width > 0, height > 0, other.width > 0, other.height > 0 else { return false }
        return x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }
}

public struct KeyboardLayoutMetrics: Equatable, Sendable {
    public let frame: LayoutRect
    public let rowHeight: Double
    public let rowGap: Double
    public let keySide: Double
    public let spacebarWidth: Double

    public var x: Double { frame.x }
    public var y: Double { frame.y }
    public var width: Double { frame.width }
    public var height: Double { frame.height }
    public var isHidden: Bool { frame.isHidden }
}

public struct EdexLayout: Equatable, Sendable {
    public let viewport: LayoutSize
    public let statusRibbon: LayoutRect
    public let leftColumn: LayoutRect
    public let mainShell: LayoutRect
    public let rightColumn: LayoutRect
    public let filesystem: LayoutRect
    public let keyboard: KeyboardLayoutMetrics

    public var fixedReservedRects: [LayoutRect] {
        [statusRibbon, leftColumn, mainShell, rightColumn, filesystem, keyboard.frame].filter {
            !$0.isHidden && $0.width > 0 && $0.height > 0
        }
    }
}

public struct EdexLayoutEngine: Sendable {
    public init() {}

    public func layout(in size: LayoutSize) -> EdexLayout {
        let width = size.width
        let height = size.height
        let vw = width / 100
        let vh = height / 100
        let aspect = height > 0 ? width / height : 0
        let isSixteenTen = abs(aspect - 1.6) < 0.02
        let isClassicNarrow = aspect > 0 && aspect <= 1.34
        let isUltraWide = abs(aspect - (64.0 / 27.0)) < 0.04

        let gap = max(8, 0.8 * vw)
        let edgeInset = max(8, 0.5 * vw)
        let statusWidth = min(max(220, 14 * vw), max(0, width - (2 * edgeInset)))
        let statusHeight = max(30, 3.6 * vh)
        let statusRibbon = LayoutRect(
            x: edgeInset,
            y: edgeInset,
            width: statusWidth,
            height: statusHeight
        )
        let columnWidth = min(width * (isSixteenTen ? 0.175 : 0.17), max(0, (width - (4 * gap)) / 3))
        let columnY = max(2.5 * vh, statusRibbon.maxY + gap)
        let columnBleed = 0.555 * vh
        let leftColumnX = -columnBleed
        let rightColumnX = width - columnWidth + columnBleed
        let centerMinX = max(0, leftColumnX + columnWidth + gap)
        let centerMaxX = max(centerMinX, rightColumnX - gap)
        let centerWidth = max(0, centerMaxX - centerMinX)

        let preferredKeyboardWidth = 55.5 * vw
        let baseKeyboardWidth = isClassicNarrow
            ? min(preferredKeyboardWidth, centerWidth)
            : min(preferredKeyboardWidth, centerWidth * 0.48)
        let filesystemWidth = isClassicNarrow ? 0 : max(0, centerWidth - baseKeyboardWidth - gap)
        let keyboardRowHeight = 5.28 * vh
        let keyboardRowGap = 0.92 * vh
        let keyboardHeight = (6 * keyboardRowHeight) + (6 * keyboardRowGap)
        let filesystemHeight = isClassicNarrow ? 0 : keyboardHeight
        let keySide = min(keyboardRowHeight * 0.85, (isSixteenTen ? 2.9 : 3.0) * vw)
        let spacebarWidth: Double
        if isClassicNarrow {
            spacebarWidth = 36 * vw
        } else if isUltraWide {
            spacebarWidth = 60 * vh
        } else if isSixteenTen {
            spacebarWidth = 45 * vh
        } else {
            spacebarWidth = 47.68 * vh
        }
        let bottomBandHeight = max(keyboardHeight, filesystemHeight)
        let bottomBandY = max(columnY, height - bottomBandHeight - edgeInset)
        let keyboardAndFilesystemWidth = isClassicNarrow
            ? baseKeyboardWidth
            : baseKeyboardWidth + gap + filesystemWidth
        let bottomBandX = centerMinX + max(0, (centerWidth - keyboardAndFilesystemWidth) / 2)
        let filesystem = LayoutRect(
            x: isClassicNarrow ? 0 : bottomBandX,
            y: isClassicNarrow ? 0 : bottomBandY + max(0, (bottomBandHeight - filesystemHeight) / 2),
            width: filesystemWidth,
            height: filesystemHeight,
            isHidden: isClassicNarrow
        )
        let keyboardX = isClassicNarrow ? bottomBandX : filesystem.maxX + gap
        let keyboardRightEdge = isClassicNarrow
            ? min(width - edgeInset, keyboardX + baseKeyboardWidth)
            : max(keyboardX, width - edgeInset)
        let keyboardFrame = LayoutRect(
            x: keyboardX,
            y: bottomBandY + max(0, (bottomBandHeight - keyboardHeight) / 2),
            width: max(0, keyboardRightEdge - keyboardX),
            height: keyboardHeight
        )

        let dashboardBottom = max(columnY, bottomBandY - gap)
        let columnHeight = max(0, height - columnY - edgeInset)
        let rightColumnHeight = isClassicNarrow ? columnHeight : max(0, keyboardFrame.y - gap - columnY)
        let shellTop = columnY
        let shellBottom = dashboardBottom
        let shellHeight = max(0, shellBottom - shellTop)
        let shellWidth = min(65 * vw, centerWidth)
        let shell = LayoutRect(
            x: centerMinX + max(0, (centerWidth - shellWidth) / 2),
            y: shellTop,
            width: shellWidth,
            height: shellHeight
        )

        return EdexLayout(
            viewport: size,
            statusRibbon: statusRibbon,
            leftColumn: LayoutRect(
                x: leftColumnX,
                y: columnY,
                width: columnWidth,
                height: columnHeight
            ),
            mainShell: shell,
            rightColumn: LayoutRect(
                x: rightColumnX,
                y: columnY,
                width: columnWidth,
                height: rightColumnHeight
            ),
            filesystem: filesystem,
            keyboard: KeyboardLayoutMetrics(
                frame: keyboardFrame,
                rowHeight: keyboardRowHeight,
                rowGap: keyboardRowGap,
                keySide: keySide,
                spacebarWidth: spacebarWidth
            )
        )
    }

    private func centered(_ child: Double, in parent: Double) -> Double {
        max(0, (parent - child) / 2)
    }
}
