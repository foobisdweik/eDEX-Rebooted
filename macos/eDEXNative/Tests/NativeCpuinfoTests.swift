import XCTest
@testable import EdexDomainSupport

final class NativeCpuinfoTests: XCTestCase {
    private let formatter = EdexCpuinfoFormatter()

    // MARK: - CPU name (manufacturer + brand, truncated to 30 chars)

    func testCpuNameConcatenatesManufacturerAndBrand() {
        XCTAssertEqual(formatter.cpuName(manufacturer: "Apple ", brand: "M1 Pro"), "Apple M1 Pro")
    }

    func testCpuNameTruncatesToThirtyCharacters() {
        let name = formatter.cpuName(manufacturer: "VeryLongManufacturerName ", brand: "WithAnEvenLongerBrandString")
        XCTAssertEqual(name.count, 30)
        XCTAssertEqual(name, String(("VeryLongManufacturerName WithAnEvenLongerBrandString").prefix(30)))
    }

    // MARK: - Core split

    func testDivideIsFloorOfHalfCores() {
        XCTAssertEqual(formatter.divide(cores: 10), 5)
        XCTAssertEqual(formatter.divide(cores: 9), 4)
        XCTAssertEqual(formatter.divide(cores: 8), 4)
    }

    func testChartIndexSplitsLowerHalfToZeroUpperToOne() {
        // divide = 4: cores 0..3 -> chart 0, cores 4..7 -> chart 1
        XCTAssertEqual(formatter.chartIndex(forCore: 0, divide: 4), 0)
        XCTAssertEqual(formatter.chartIndex(forCore: 3, divide: 4), 0)
        XCTAssertEqual(formatter.chartIndex(forCore: 4, divide: 4), 1)
        XCTAssertEqual(formatter.chartIndex(forCore: 7, divide: 4), 1)
    }

    // MARK: - Average (rounded mean of a half's loads)

    func testAverageRoundsMean() {
        XCTAssertEqual(formatter.average(loads: [10, 20, 30]), 20)
        XCTAssertEqual(formatter.average(loads: [10, 11]), 11) // 10.5 rounds up
    }

    func testAverageOfEmptyIsZero() {
        XCTAssertEqual(formatter.average(loads: []), 0)
    }

    func testAverageIgnoresNonFiniteLoads() {
        // NaN/inf must not crash the Int(mean.rounded()) cast.
        XCTAssertEqual(formatter.average(loads: [.nan, 10, 20]), 15)
        XCTAssertEqual(formatter.average(loads: [.infinity, -.infinity]), 0)
    }

    // MARK: - Footer cell formatting

    func testTemperatureTextDropsTrailingZeroAndAddsUnit() {
        XCTAssertEqual(formatter.temperatureText(45), "45°C")
        XCTAssertEqual(formatter.temperatureText(45.5), "45.5°C")
    }

    func testSpeedTextAppendsGHz() {
        XCTAssertEqual(formatter.speedText("3.20"), "3.20GHz")
    }

    func testTemperatureTextHandlesNonFiniteWithoutCrashing() {
        // A non-finite sensor read must not crash the Int(value) cast.
        XCTAssertEqual(formatter.temperatureText(.infinity), "inf°C")
        XCTAssertEqual(formatter.temperatureText(.nan), "nan°C")
    }

    func testTasksTextIsCount() {
        XCTAssertEqual(formatter.tasksText(431), "431")
    }

    // MARK: - Sample ring buffer

    func testBufferInitialisesOneSeriesPerCore() {
        let buffer = CpuSeriesBuffer(coreCount: 4, capacity: 8)
        XCTAssertEqual(buffer.series.count, 4)
        XCTAssertTrue(buffer.series.allSatisfy(\.isEmpty))
    }

    func testBufferAppendsOneSamplePerCore() {
        var buffer = CpuSeriesBuffer(coreCount: 3, capacity: 8)
        buffer.append(loads: [1, 2, 3])
        buffer.append(loads: [4, 5, 6])
        XCTAssertEqual(buffer.series[0], [1, 4])
        XCTAssertEqual(buffer.series[2], [3, 6])
    }

    func testBufferEvictsOldestBeyondCapacity() {
        var buffer = CpuSeriesBuffer(coreCount: 1, capacity: 3)
        for value in [1.0, 2, 3, 4, 5] {
            buffer.append(loads: [value])
        }
        XCTAssertEqual(buffer.series[0], [3, 4, 5])
    }

    func testBufferPadsMissingCoresWithZero() {
        var buffer = CpuSeriesBuffer(coreCount: 3, capacity: 8)
        buffer.append(loads: [9]) // only one core reported
        XCTAssertEqual(buffer.series[0], [9])
        XCTAssertEqual(buffer.series[1], [0])
        XCTAssertEqual(buffer.series[2], [0])
    }

    func testBufferSanitizesNonFiniteAndClampsLoads() {
        var buffer = CpuSeriesBuffer(coreCount: 3, capacity: 8)
        buffer.append(loads: [.nan, 150, -5])
        XCTAssertEqual(buffer.series[0], [0])   // NaN → 0
        XCTAssertEqual(buffer.series[1], [100]) // 150 clamped to 100
        XCTAssertEqual(buffer.series[2], [0])   // -5 clamped to 0
    }

    // MARK: - Scroll geometry (offset-animated graph, replaces the 30 Hz redraw)

    func testGraphPointsPlaceNewestSampleAtRightEdgeWithLegacySpacing() {
        let points = CpuGraphScrollGeometry.points(samples: [10, 20, 30], width: 100, height: 34)
        // millisPerPixel = 50 in the legacy → 20 px per 1 s sample.
        XCTAssertEqual(points.map(\.x), [60, 80, 100])
    }

    func testGraphPointsMapLoadToInvertedY() {
        let points = CpuGraphScrollGeometry.points(samples: [0, 50, 100], width: 100, height: 34)
        XCTAssertEqual(points.map(\.y), [34, 17, 0])
    }

    func testGraphPointsClampOutOfRangeAndNonFiniteLoads() {
        let points = CpuGraphScrollGeometry.points(samples: [-5, 250, .nan, .infinity], width: 100, height: 34)
        XCTAssertEqual(points.map(\.y), [34, 0, 34, 34]) // clamped low, clamped high, non-finite → 0 load
    }

    func testGraphPointsRejectDegenerateSizesAndShortSeries() {
        XCTAssertTrue(CpuGraphScrollGeometry.points(samples: [1, 2], width: 0, height: 34).isEmpty)
        XCTAssertTrue(CpuGraphScrollGeometry.points(samples: [1, 2], width: 100, height: -1).isEmpty)
        XCTAssertTrue(CpuGraphScrollGeometry.points(samples: [1, 2], width: .nan, height: 34).isEmpty)
        XCTAssertTrue(CpuGraphScrollGeometry.points(samples: [1, 2], width: 100, height: .infinity).isEmpty)
        XCTAssertTrue(CpuGraphScrollGeometry.points(samples: [1], width: 100, height: 34).isEmpty)
        XCTAssertTrue(CpuGraphScrollGeometry.points(samples: [], width: 100, height: 34).isEmpty)
    }

    func testScrollDistanceMatchesLegacySampleSpacing() {
        XCTAssertEqual(CpuGraphScrollGeometry.scrollDistance, 20)
    }

    // MARK: - Graph frame lines (single shape replaces the nested border overlays)

    func testBorderLineYsCenterUnitStrokeInsideBounds() {
        XCTAssertEqual(CpuGraphScrollGeometry.borderLineYs(height: 34, lineWidth: 1), [0.5, 33.5])
    }

    func testBorderLineYsRejectDegenerateHeights() {
        XCTAssertTrue(CpuGraphScrollGeometry.borderLineYs(height: 0, lineWidth: 1).isEmpty)
        XCTAssertTrue(CpuGraphScrollGeometry.borderLineYs(height: .nan, lineWidth: 1).isEmpty)
        XCTAssertTrue(CpuGraphScrollGeometry.borderLineYs(height: -10, lineWidth: 1).isEmpty)
        XCTAssertTrue(CpuGraphScrollGeometry.borderLineYs(height: 34, lineWidth: .nan).isEmpty)
    }
}
