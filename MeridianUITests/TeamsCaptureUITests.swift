import XCTest

/// Captures the multi-commander battlefields (spectator, after a short warp) for docs/screenshots/teams.
/// Skipped unless TEAM_SHOTS names an output folder (pass it to xcodebuild as TEST_RUNNER_TEAM_SHOTS).
final class TeamsCaptureUITests: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["TEAM_SHOTS"]

    func capture(_ name: String, _ args: [String]) throws {
        guard let d = shotDir else { throw XCTSkip("TEAM_SHOTS not set") }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-autostart", "-spectate", "-victory", "annihilation", "-map", "riverbend", "-seed", "3",
                               "-warp", "180", "-perf", "nosound", "-nosave"] + args
        app.launch()
        XCTAssertTrue(app.buttons["FOLLOW ON"].waitForExistence(timeout: 90), "Spectator HUD missing")
        sleep(5)
        for (suffix, zoom) in [("", nil), ("_wide", "4.5")] as [(String, String?)] {
            if let z = zoom {
                app.terminate()
                app.launchArguments += ["-zoom", z]
                app.launch()
                XCTAssertTrue(app.buttons["FOLLOW ON"].waitForExistence(timeout: 90))
                sleep(5)
            }
            let s = XCUIScreen.main.screenshot()
            let a = XCTAttachment(screenshot: s); a.name = name + suffix; a.lifetime = .keepAlways; add(a)
            try s.pngRepresentation.write(to: URL(fileURLWithPath: d).appendingPathComponent(name + suffix + ".png"))
        }
        app.terminate()
    }

    func testFourPlayerTeams() throws { try capture("riverbend_4p_2v2", ["-players", "4", "-teams", "0,0,1,1"]) }
    func testThreePlayerRound() throws { try capture("riverbend_3p_ffa", ["-players", "3"]) }
}
