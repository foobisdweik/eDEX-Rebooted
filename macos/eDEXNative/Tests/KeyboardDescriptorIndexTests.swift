import XCTest
@testable import EdexDomainSupport

/// Finding #3 (List 3): `KeyboardDescriptorIndex` is the cached O(1) replacement
/// for `KeyboardPhysicalKeyMapper`'s per-keystroke matrix rebuild + linear
/// scans. These tests assert it returns *identical* ids to the reference
/// mapper for every input shape, so the optimization can't change behavior.
final class KeyboardDescriptorIndexTests: XCTestCase {
    private func enUSLayout() throws -> NativeKeyboardLayout {
        let file = EdexBundledAssets.keyboardsDirectory(from: #filePath)
            .appendingPathComponent("en-US.json")
        return try NativeKeyboardLayout(
            json: String(contentsOf: file, encoding: .utf8),
            name: "en-US"
        )
    }

    func testCharacterCombosMatchMapper() throws {
        let layout = try enUSLayout()
        let index = KeyboardDescriptorIndex(layout: layout)

        var characters: [Character] = []
        characters.append(contentsOf: "abcdefghijklmnopqrstuvwxyz")
        characters.append(contentsOf: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        characters.append(contentsOf: "0123456789")
        characters.append(contentsOf: "`-=[]\\;',./")
        // Specials handled by the dedicated switch arms.
        characters.append(contentsOf: ["\r", "\n", "\u{1B}", "\u{8}", "\u{7F}",
                                       "\u{F700}", "\u{F701}", "\u{F702}", "\u{F703}"])
        // Unmapped character must still agree (both nil).
        characters.append("☃")

        for character in characters {
            let combo = KeyCombo(modifiers: [], key: .character(character))
            XCTAssertEqual(
                index.id(for: combo),
                KeyboardPhysicalKeyMapper.descriptorID(for: combo, in: layout),
                "character \(String(reflecting: character))"
            )
        }
    }

    func testSpecialAndFunctionCombosMatchMapper() throws {
        let layout = try enUSLayout()
        let index = KeyboardDescriptorIndex(layout: layout)

        let specials: [KeyCombo] = [
            KeyCombo(modifiers: [], key: .special(.space)),
            KeyCombo(modifiers: [], key: .special(.tab)),
        ]
        for combo in specials {
            XCTAssertEqual(
                index.id(for: combo),
                KeyboardPhysicalKeyMapper.descriptorID(for: combo, in: layout)
            )
        }

        for number in 1...12 {
            let combo = KeyCombo(modifiers: [], key: .function(number))
            XCTAssertEqual(
                index.id(for: combo),
                KeyboardPhysicalKeyMapper.descriptorID(for: combo, in: layout),
                "F\(number)"
            )
        }
    }

    func testModifierLookupsMatchMapper() throws {
        let layout = try enUSLayout()
        let index = KeyboardDescriptorIndex(layout: layout)

        for modifier in KeyboardModifier.allCases {
            XCTAssertEqual(
                index.id(for: modifier),
                KeyboardPhysicalKeyMapper.descriptorID(for: modifier, in: layout),
                "\(modifier)"
            )
        }

        let physical: [KeyboardPhysicalModifier] = [
            .leftShift, .rightShift, .capsLock, .leftControl, .rightControl,
            .leftOption, .rightOption, .leftCommand, .rightCommand, .fn,
        ]
        for modifier in physical {
            XCTAssertEqual(
                index.id(for: modifier),
                KeyboardPhysicalKeyMapper.descriptorID(for: modifier, in: layout),
                "\(modifier)"
            )
        }
    }

    func testCachedRowsMatchDirectBuild() throws {
        let layout = try enUSLayout()
        let index = KeyboardDescriptorIndex(layout: layout)
        let direct = KeyboardViewModel.macBookDescriptors(for: layout)
        XCTAssertEqual(index.rows.map { $0.map(\.id) }, direct.map { $0.map(\.id) })
    }
}
