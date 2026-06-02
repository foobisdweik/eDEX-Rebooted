import Foundation

public enum NativeKeyboardRowID: String, CaseIterable, Sendable {
    case numbers = "row_numbers"
    case row1 = "row_1"
    case row2 = "row_2"
    case row3 = "row_3"
    case space = "row_space"
}

public struct NativeKeyboardLayout: Equatable, Sendable {
    public var name: String
    public var rows: [NativeKeyboardRow]

    public var keyCount: Int {
        rows.reduce(0) { $0 + $1.keys.count }
    }

    public init(name: String, rows: [NativeKeyboardRow]) {
        self.name = name
        self.rows = rows
    }

    public init(json: String, name: String) throws {
        let data = Data(json.utf8)
        let raw = try JSONDecoder().decode(RawKeyboardLayout.self, from: data)
        let orderedRows = NativeKeyboardRowID.allCases.compactMap { id -> NativeKeyboardRow? in
            guard let rawKeys = raw.rows[id], !rawKeys.isEmpty else {
                return nil
            }
            return NativeKeyboardRow(
                id: id,
                keys: rawKeys.map(NativeKeyboardKey.init(raw:))
            )
        }

        guard !orderedRows.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Keyboard layout has no usable key rows")
            )
        }

        self.init(name: name, rows: orderedRows)
    }

    public func key(name: String) -> NativeKeyboardKey? {
        rows.lazy.flatMap(\.keys).first { $0.name == name }
    }

    public func key(iconName: String) -> NativeKeyboardKey? {
        rows.lazy.flatMap(\.keys).first { $0.iconName == iconName }
    }
}

public struct NativeKeyboardRow: Equatable, Sendable {
    public var id: NativeKeyboardRowID
    public var keys: [NativeKeyboardKey]

    public init(id: NativeKeyboardRowID, keys: [NativeKeyboardKey]) {
        self.id = id
        self.keys = keys
    }
}

public struct NativeKeyboardKey: Equatable, Sendable {
    public var name: String
    public var command: String
    public var shiftName: String?
    public var shiftCommand: String?
    public var controlCommand: String?
    public var alternateName: String?
    public var alternateCommand: String?
    public var alternateShiftName: String?
    public var alternateShiftCommand: String?
    public var functionName: String?
    public var functionCommand: String?
    public var capsLockCommand: String?
    public var iconName: String?

    public init(
        name: String,
        command: String,
        shiftName: String? = nil,
        shiftCommand: String? = nil,
        controlCommand: String? = nil,
        alternateName: String? = nil,
        alternateCommand: String? = nil,
        alternateShiftName: String? = nil,
        alternateShiftCommand: String? = nil,
        functionName: String? = nil,
        functionCommand: String? = nil,
        capsLockCommand: String? = nil,
        iconName: String? = nil
    ) {
        self.name = name
        self.command = command
        self.shiftName = shiftName
        self.shiftCommand = shiftCommand
        self.controlCommand = controlCommand
        self.alternateName = alternateName
        self.alternateCommand = alternateCommand
        self.alternateShiftName = alternateShiftName
        self.alternateShiftCommand = alternateShiftCommand
        self.functionName = functionName
        self.functionCommand = functionCommand
        self.capsLockCommand = capsLockCommand
        self.iconName = iconName
    }

    fileprivate init(raw: RawKeyboardKey) {
        self.init(
            name: raw.name,
            command: NativeKeyboardKey.expandControlSequences(raw.command),
            shiftName: raw.shiftName,
            shiftCommand: NativeKeyboardKey.expandControlSequences(raw.shiftCommand),
            controlCommand: NativeKeyboardKey.expandControlSequences(raw.controlCommand),
            alternateName: raw.alternateName,
            alternateCommand: NativeKeyboardKey.expandControlSequences(raw.alternateCommand),
            alternateShiftName: raw.alternateShiftName,
            alternateShiftCommand: NativeKeyboardKey.expandControlSequences(raw.alternateShiftCommand),
            functionName: raw.functionName,
            functionCommand: NativeKeyboardKey.expandControlSequences(raw.functionCommand),
            capsLockCommand: NativeKeyboardKey.expandControlSequences(raw.capsLockCommand),
            iconName: NativeKeyboardKey.iconName(from: raw.name)
        )
    }

    private static func iconName(from name: String) -> String? {
        let prefix = "ESCAPED|-- ICON: "
        guard name.hasPrefix(prefix) else { return nil }
        return String(name.dropFirst(prefix.count))
    }

    private static func expandControlSequences(_ value: String) -> String {
        var expanded = value
        for index in 1..<controlSequences.count {
            expanded = expanded.replacingOccurrences(
                of: "~~~CTRLSEQ\(index)~~~",
                with: controlSequences[index]
            )
        }
        return expanded
    }

    private static func expandControlSequences(_ value: String?) -> String? {
        guard let value else { return nil }
        return expandControlSequences(value)
    }

    private static let controlSequences = [
        "",
        "\u{001B}",
        "\u{001C}",
        "\u{001D}",
        "\u{001E}",
        "\u{001F}",
        "\u{0011}",
        "\u{0017}",
        "\u{0012}",
        "\u{0012}",
        "\u{0019}",
        "\u{0015}",
        "\u{0010}",
        "\u{0001}",
        "\u{0013}",
        "\u{0004}",
        "\u{0006}",
        "\u{001A}",
        "\u{0018}",
        "\u{0003}",
        "\u{0016}",
        "\u{0002}"
    ]
}

private struct RawKeyboardLayout: Decodable {
    var rows: [NativeKeyboardRowID: [RawKeyboardKey]]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var decoded = [NativeKeyboardRowID: [RawKeyboardKey]]()
        for rowID in NativeKeyboardRowID.allCases {
            let key = DynamicCodingKey(stringValue: rowID.rawValue)
            if container.contains(key) {
                decoded[rowID] = try container.decode([RawKeyboardKey].self, forKey: key)
            }
        }
        rows = decoded
    }
}

private struct RawKeyboardKey: Decodable {
    var name: String
    var command: String
    var shiftName: String?
    var shiftCommand: String?
    var controlCommand: String?
    var alternateName: String?
    var alternateCommand: String?
    var alternateShiftName: String?
    var alternateShiftCommand: String?
    var functionName: String?
    var functionCommand: String?
    var capsLockCommand: String?

    enum CodingKeys: String, CodingKey {
        case name
        case command = "cmd"
        case shiftName = "shift_name"
        case shiftCommand = "shift_cmd"
        case controlCommand = "ctrl_cmd"
        case alternateName = "alt_name"
        case alternateCommand = "alt_cmd"
        case alternateShiftName = "altshift_name"
        case alternateShiftCommand = "altshift_cmd"
        case functionName = "fn_name"
        case functionCommand = "fn_cmd"
        case capsLockCommand = "capslck_cmd"
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
