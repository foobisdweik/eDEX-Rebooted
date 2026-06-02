import Foundation

public struct LayoutSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width.isFinite ? max(0, width) : 0
        self.height = height.isFinite ? max(0, height) : 0
    }
}

public struct LayoutRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var isHidden: Bool

    public init(x: Double, y: Double, width: Double, height: Double, isHidden: Bool = false) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
        self.width = width.isFinite ? max(0, width) : 0
        self.height = height.isFinite ? max(0, height) : 0
        self.isHidden = isHidden
    }
}

public struct KeyboardLayoutMetrics: Equatable, Sendable {
    public var frame: LayoutRect
    public var rowHeight: Double
    public var rowGap: Double
    public var keySide: Double
    public var spacebarWidth: Double

    public var x: Double { frame.x }
    public var y: Double { frame.y }
    public var width: Double { frame.width }
    public var height: Double { frame.height }
    public var isHidden: Bool { frame.isHidden }
}

public struct EdexLayout: Equatable, Sendable {
    public var viewport: LayoutSize
    public var leftColumn: LayoutRect
    public var mainShell: LayoutRect
    public var rightColumn: LayoutRect
    public var filesystem: LayoutRect
    public var keyboard: KeyboardLayoutMetrics
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

        let columnWidth = width * (isSixteenTen ? 0.175 : 0.17)
        let columnHeight = height * 0.96
        let columnY = 2.5 * vh
        let columnBleed = 0.555 * vh

        let shellWidth = 65 * vw
        let shellHeight = 60.3 * vh
        let shell = LayoutRect(
            x: centered(shellWidth, in: width),
            y: centered(shellHeight, in: height),
            width: shellWidth,
            height: shellHeight
        )

        let filesystemWidth = 43 * vw
        let filesystemHeight = 30 * vh
        let filesystem = LayoutRect(
            x: max(0, width - filesystemWidth - (0.5 * vw)),
            y: max(0, height - filesystemHeight - (0.925 * vh)),
            width: filesystemWidth,
            height: filesystemHeight,
            isHidden: isClassicNarrow
        )

        let keyboardWidth = 55.5 * vw
        let keyboardRowHeight = 5.28 * vh
        let keyboardRowGap = 0.92 * vh
        let keyboardHeight = (5 * keyboardRowHeight) + (5 * keyboardRowGap)
        let keySide = (isSixteenTen ? 2.5 : 2.7) * vw
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
        let keyboardFrame = LayoutRect(
            x: centered(keyboardWidth, in: width),
            y: max(0, height - keyboardHeight - (0.925 * vh)),
            width: keyboardWidth,
            height: keyboardHeight
        )

        return EdexLayout(
            viewport: size,
            leftColumn: LayoutRect(
                x: -columnBleed,
                y: columnY,
                width: columnWidth,
                height: columnHeight
            ),
            mainShell: shell,
            rightColumn: LayoutRect(
                x: width - columnWidth + columnBleed,
                y: columnY,
                width: columnWidth,
                height: columnHeight
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
