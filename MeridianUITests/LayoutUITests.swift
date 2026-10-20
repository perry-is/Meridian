import XCTest

/// Captures the HUD in portrait and landscape mid-match to verify adaptive layout.
final class LayoutUITests: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["MERIDIAN_SHOTS"]

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let d = shotDir { try? s.pngRepresentation.write(to: URL(fileURLWithPath: d).appendingPathComponent(name + ".png")) }
    }

    func testPortraitAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["-autostart", "-spectate", "-warp", "360", "-seed", "11", "-enemy", "aliens"]
        app.launch()
        XCTAssertTrue(app.buttons["Army"].waitForExistence(timeout: 30))
        XCUIDevice.shared.orientation = .portrait
        sleep(3)
        shot("layout_portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        XCTAssertTrue(app.buttons["Army"].exists)
        shot("layout_landscape")
        // Select something so the command card shows in landscape.
        app.buttons["Army"].tap()
        sleep(1)
        shot("layout_landscape_selected")
        XCUIDevice.shared.orientation = .portrait
    }
}
