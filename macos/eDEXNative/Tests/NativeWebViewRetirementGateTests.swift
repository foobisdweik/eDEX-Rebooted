import XCTest
@testable import EdexDomainSupport

final class NativeWebViewRetirementGateTests: XCTestCase {
    func testBurnInIncompleteWhenAnyScenarioMissing() {
        var gate = WebViewRetirementGate()
        for scenario in TerminalBurnInScenario.allCases {
            gate.recordBurnIn(scenario, passed: scenario != .tmux)
        }
        XCTAssertFalse(gate.isBurnInComplete)
        XCTAssertEqual(gate.missingBurnIn, [.tmux])
    }

    func testBurnInCompleteWhenAllScenariosPass() {
        var gate = WebViewRetirementGate()
        for scenario in TerminalBurnInScenario.allCases {
            gate.recordBurnIn(scenario, passed: true)
        }
        XCTAssertTrue(gate.isBurnInComplete)
        XCTAssertTrue(gate.missingBurnIn.isEmpty)
    }

    func testSurfaceGateTreatsWaivedSurfacesAsSatisfied() {
        var gate = WebViewRetirementGate()
        for surface in WebViewRetirementGate.requiredSurfaces {
            gate.recordSurface(surface, passed: true)
        }
        XCTAssertTrue(gate.isSurfaceGateComplete)
        XCTAssertTrue(gate.missingSurfaces.isEmpty)
    }

    func testSurfaceGateBlocksWhenRequiredSurfaceFails() {
        var gate = WebViewRetirementGate()
        for surface in WebViewRetirementGate.requiredSurfaces {
            gate.recordSurface(surface, passed: surface != .terminalDailyUse)
        }
        XCTAssertFalse(gate.isSurfaceGateComplete)
        XCTAssertEqual(gate.missingSurfaces, [.terminalDailyUse])
    }

    func testDeletionReadyRequiresBurnInAndSurfaceGates() {
        var gate = WebViewRetirementGate()
        XCTAssertFalse(gate.isDeletionReady)

        for scenario in TerminalBurnInScenario.allCases {
            gate.recordBurnIn(scenario, passed: true)
        }
        XCTAssertFalse(gate.isDeletionReady)

        for surface in WebViewRetirementGate.requiredSurfaces {
            gate.recordSurface(surface, passed: true)
        }
        XCTAssertTrue(gate.isDeletionReady)
    }

    func testRecordingFailureClearsPriorPass() {
        var gate = WebViewRetirementGate()
        for scenario in TerminalBurnInScenario.allCases {
            gate.recordBurnIn(scenario, passed: true)
        }
        gate.recordBurnIn(.shell, passed: false)
        XCTAssertEqual(gate.missingBurnIn, [.shell])
    }

    func testBundledAssetPathsPointAtRepositoryAssetsRoot() {
        let themes = EdexBundledAssets.themesDirectory(from: #filePath)
        XCTAssertTrue(themes.path.hasSuffix("/assets/themes"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: themes.path),
            "themes directory should resolve to the repository assets root"
        )
        XCTAssertEqual(
            EdexBundledAssets.audioDirectory(from: #filePath).lastPathComponent,
            "audio"
        )
    }
}
