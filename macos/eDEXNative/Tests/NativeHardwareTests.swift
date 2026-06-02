import XCTest
@testable import HardwareSupport

final class NativeHardwareTests: XCTestCase {
    private let formatter = EdexHardwareFormatter()

    // MARK: - Manufacturer (no filters → first two space-split words)

    func testManufacturerKeepsFirstTwoWords() {
        let info = formatter.format(manufacturer: "Dell Inc Corporation", model: "x", chassisType: "Laptop")
        XCTAssertEqual(info.manufacturer, "Dell Inc")
    }

    func testManufacturerIsTrimmed() {
        let info = formatter.format(manufacturer: "  Apple  ", model: "x", chassisType: "Laptop")
        XCTAssertEqual(info.manufacturer, "Apple")
    }

    // MARK: - Model (strips words equal to manufacturer or chassis type, then first two)

    func testModelStripsManufacturerWord() {
        let info = formatter.format(manufacturer: "Apple", model: "Apple MacBookPro18,3", chassisType: "Laptop")
        XCTAssertEqual(info.model, "MacBookPro18,3")
    }

    func testModelStripsManufacturerAndChassisWordsThenKeepsTwo() {
        let info = formatter.format(manufacturer: "Apple", model: "Apple Laptop Pro Max", chassisType: "Laptop")
        XCTAssertEqual(info.model, "Pro Max")
    }

    func testModelFilterMatchesWholeWordsOnly() {
        // Manufacturer "Apple Inc" is a two-word string; it never equals a single
        // model word, so nothing is stripped and the first two words remain.
        let info = formatter.format(manufacturer: "Apple Inc", model: "Apple MacBook Air", chassisType: "Laptop")
        XCTAssertEqual(info.model, "Apple MacBook")
    }

    func testModelEmptyStaysEmpty() {
        let info = formatter.format(manufacturer: "Apple", model: "", chassisType: "Laptop")
        XCTAssertEqual(info.model, "")
    }

    // MARK: - Chassis (raw, untrimmed)

    func testChassisIsUsedRaw() {
        let info = formatter.format(manufacturer: "Apple", model: "x", chassisType: "Laptop")
        XCTAssertEqual(info.chassis, "Laptop")
    }
}
