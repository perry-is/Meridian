import XCTest

/// Captures the HUD in portrait and landscape mid-match to verify adaptive layout.
final class LayoutUITests: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["MERIDIAN_SHOTS"]

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let d = shotDir { try? s.pngRepresentation.write(to: URL(fileURLWithPath: d).appendingPathComponent(name + ".png")) }
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testPortraitAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["-autostart", "-warp", "360", "-seed", "11", "-enemy", "aliens"]
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

    /// Observer mode: Battle Lab shows the spectator HUD and its controls respond.
    func testSpectatorBattle() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-battle", "50"]
        app.launch()
        let follow = app.buttons["FOLLOW ON"]
        XCTAssertTrue(follow.waitForExistence(timeout: 30), "Spectator HUD missing")
        sleep(6)
        shot("spectator_battle")
        follow.tap()
        XCTAssertTrue(app.buttons["FOLLOW OFF"].waitForExistence(timeout: 3))
        app.buttons["½×"].tap()
        app.buttons["CINEMA"].tap()
        XCTAssertFalse(app.buttons["FOLLOW OFF"].exists, "Cinema mode should hide the observer HUD")
        sleep(2)
        shot("spectator_cinema")
    }
}
