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

    func testModelStripsManufacturerEvenWhenManufacturerHasStrayWhitespace() {
        // The manufacturer filter is compared against the *formatted* (trimmed)
        // manufacturer, so a padded "  Apple  " still strips "Apple" from model.
        let info = formatter.format(manufacturer: "  Apple  ", model: "Apple MacBook", chassisType: "Laptop")
        XCTAssertEqual(info.model, "MacBook")
    }

    func testEmptyManufacturerDoesNotFilterModelWords() {
        // An empty manufacturer/chassis must not inject an empty-string filter.
        let info = formatter.format(manufacturer: "", model: "MacBook Pro", chassisType: "")
        XCTAssertEqual(info.model, "MacBook Pro")
    }

    // MARK: - Chassis (raw, untrimmed)

    func testChassisIsUsedRaw() {
        let info = formatter.format(manufacturer: "Apple", model: "x", chassisType: "Laptop")
        XCTAssertEqual(info.chassis, "Laptop")
    }
}
