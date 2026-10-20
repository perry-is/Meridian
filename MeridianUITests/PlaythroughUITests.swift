import XCTest

/// Drives the real app with touch input on the simulator: menu → match → select → train → box-select → build → move.
final class PlaythroughUITests: XCTestCase {
    var app: XCUIApplication!
    let shotDir = ProcessInfo.processInfo.environment["MERIDIAN_SHOTS"]

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-seed", "42", "-faction", "humans", "-enemy", "machines"]
        app.launch()
    }

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let d = shotDir { try? s.pngRepresentation.write(to: URL(fileURLWithPath: d).appendingPathComponent(name + ".png")) }
    }

    func point(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate {
        // Offsets in points from the screen centre.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: dx, dy: dy))
    }

    func testCorePlaythrough() throws {
        let deploy = app.buttons["DEPLOY"]
        if !deploy.waitForExistence(timeout: 10) { app.swipeUp(); }
        // The menu scrolls on the small cover screen.
        for _ in 0..<4 where !deploy.isHittable { app.swipeUp() }
        shot("01_menu")
        deploy.tap()
        XCTAssertTrue(app.buttons["Army"].waitForExistence(timeout: 20), "HUD did not appear")
        sleep(2)
        shot("02_match_start")

        // Tap the HQ (camera starts just below-right of it).
        let title = app.staticTexts["selectionTitle"]
        var found = false
        for dy in stride(from: -80, through: -20, by: 15) {
            point(0, CGFloat(dy)).tap()
            if title.waitForExistence(timeout: 1), title.label == "Command Hub" { found = true; break }
        }
        XCTAssertTrue(found, "Could not select the HQ by tapping it")
        shot("03_hq_selected")

        // Train a worker.
        let train = app.descendants(matching: .any)["cmd_u0"]
        XCTAssertTrue(train.waitForExistence(timeout: 3))
        train.tap()
        XCTAssertTrue(app.descendants(matching: .any)["queue_0"].waitForExistence(timeout: 3), "Production queue did not show the worker")
        shot("04_training")

        // Box-select workers around the HQ with touch-and-hold then drag.
        point(-145, -200).press(forDuration: 0.6, thenDragTo: point(60, 60))
        sleep(1)
        XCTAssertTrue(title.exists)
        XCTAssertTrue(title.label.contains("selected") || title.label == "Engineer", "Box select failed: \(title.label)")
        shot("05_box_select")

        // Build a Drill Hall.
        app.descendants(matching: .any)["cmd_build"].tap()
        let hall = app.descendants(matching: .any).matching(identifier: "cmd_b2").firstMatch
        XCTAssertTrue(hall.waitForExistence(timeout: 3))
        hall.tap()
        // Try a few spots until the placement is valid.
        let confirm = app.buttons["confirmPlacement"]
        var placed = false
        for (dx, dy) in [(110, 60), (140, -10), (60, 120), (-120, 110), (170, 90)] as [(CGFloat, CGFloat)] {
            point(dx, dy).tap()
            usleep(400_000)
            if confirm.isEnabled { shot("06_placement"); confirm.tap(); placed = true; break }
        }
        XCTAssertTrue(placed, "No valid placement found")
        sleep(1)
        XCTAssertFalse(app.staticTexts["placementReason"].exists, "Still in placement mode")
        shot("07_construction")

        // Select the HQ again and order a rally / select army; then move units.
        app.buttons["Army"].tap()
        point(-60, 40).tap()
        sleep(3)
        shot("08_after_orders")
    }
}
