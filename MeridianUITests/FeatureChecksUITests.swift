import XCTest

/// Walks the Mission 8 features on the simulator and saves screenshots for docs/screenshots/ui.
/// Skipped unless UI_SHOTS names an output folder (pass it to xcodebuild as TEST_RUNNER_UI_SHOTS).
final class FeatureChecksUITests: XCTestCase {
    let shotDir = ProcessInfo.processInfo.environment["UI_SHOTS"]
    var app: XCUIApplication!

    override func setUpWithError() throws {
        guard shotDir != nil else { throw XCTSkip("UI_SHOTS not set") }
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    func launch(_ args: [String]) {
        app.launchArguments = ["-nosound", "-uitest"] + args
        app.launch()
    }

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: shotDir!).appendingPathComponent(name + ".png"))
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    func center() -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)) }
    func hud() -> Bool { app.buttons["Army"].waitForExistence(timeout: 120) }

    func openPause() {
        let byLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'pause'")).firstMatch
        XCTAssertTrue(byLabel.waitForExistence(timeout: 5), "pause button")
        byLabel.tap()
    }

    // MARK: Setup screen

    func testSetupScreen() throws {
        launch(["-seed", "42"])
        XCTAssertTrue(app.buttons["PLAY"].waitForExistence(timeout: 30)); app.buttons["PLAY"].tap()
        let page = element("setupPage")
        XCTAssertTrue(page.waitForExistence(timeout: 10), "Commanders/Rules picker on the cover screen")
        sleep(1); shot("setup_01_commanders_page")
        XCTAssertTrue(app.buttons["DEPLOY"].isHittable, "Deploy bar should stay fixed on screen")
        page.buttons["RULES"].tap(); sleep(1)
        let preview = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Battlefield preview'")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "map preview on the Rules page")
        shot("setup_02_rules_page_preview")
        let before = preview.label
        let dice = app.buttons["New battlefield"]
        XCTAssertTrue(dice.waitForExistence(timeout: 3), "dice button"); dice.tap(); sleep(1)
        XCTAssertNotEqual(preview.label, before, "the dice should change the seed: \(before)")
        print("SETUP-PREVIEW \(before) -> \(preview.label)")
        shot("setup_03_rerolled")
        let seed = element("seedField")
        XCTAssertTrue(seed.waitForExistence(timeout: 3), "seed field")
        seed.tap()
        if let v = seed.value as? String { seed.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2)) }
        seed.typeText("777\n"); sleep(1)
        XCTAssertTrue(preview.label.contains("777"), "typed seed should reach the preview: \(preview.label)")
        shot("setup_04_seed_777")
        XCTAssertTrue(app.buttons["DEPLOY"].isHittable, "Deploy bar should stay fixed on the Rules page too")
    }

    // MARK: Teams HUD, game over, rematch

    func testTwoVTwoHUD() throws {
        launch(["-autostart", "-players", "4", "-teams", "0,0,1,1", "-map", "riverbend", "-seed", "3", "-warp", "300"])
        XCTAssertTrue(hud()); sleep(4)
        shot("teams_01_2v2_site_strip")
        // The ally (red on this map) is the lower-left base on the minimap: jump the camera there to see their rings.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.118, dy: 0.902)).tap(); sleep(2)
        shot("teams_02_ally_base_rings")
    }

    func testQuickGameOverTourAndRematch() throws {
        launch(["-autostart", "-quick", "-players", "4", "-teams", "0,0,1,1", "-victory", "annihilation", "-seed", "5", "-warp", "2400"])
        let rematch = app.buttons["Rematch"]
        XCTAssertTrue(rematch.waitForExistence(timeout: 120), "game-over panel")
        shot("gameover_01_tour_start"); sleep(4); shot("gameover_02_tour_later")
        let toggle = app.buttons["SHOW EVERY COMMANDER"]
        if toggle.waitForExistence(timeout: 3) {
            shot("gameover_03_team_table"); toggle.tap(); sleep(1); shot("gameover_04_every_commander")
            XCTAssertTrue(app.buttons["SHOW TEAMS"].exists, "toggle back to teams")
        } else { XCTFail("team table toggle missing") }
        rematch.tap()
        XCTAssertTrue(hud(), "rematch should start a new match"); sleep(3)
        shot("gameover_05_rematch_started")
    }

    // MARK: Pause

    func testPauseLineAndRestart() throws {
        launch(["-autostart", "-seed", "9", "-map", "highlands"])
        XCTAssertTrue(hud()); sleep(2)
        openPause(); sleep(1)
        shot("pause_01_match_line")
        let restart = app.buttons["Restart"]
        XCTAssertTrue(restart.waitForExistence(timeout: 3), "Restart button"); restart.tap()
        XCTAssertTrue(app.buttons["Restart?"].waitForExistence(timeout: 2), "first tap should ask")
        shot("pause_02_restart_confirm")
        app.buttons["Restart?"].tap()
        XCTAssertTrue(hud(), "restart should begin a fresh match"); sleep(2)
        shot("pause_03_after_restart")
    }

    // MARK: Fog memory

    func testFogLastSeen() throws {
        launch(["-autostart", "-seed", "4", "-fogcheck"])
        XCTAssertTrue(hud())
        let sub = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'last seen'")).firstMatch
        XCTAssertTrue(sub.waitForExistence(timeout: 10), "selected enemy HQ should say last seen")
        sleep(1); shot("fog_01_last_seen_hq")
    }

    // MARK: Beacon

    /// Configures a Beacon on a freshly held site and places a Drill Hall (barracks) 14 tiles away on ground nobody
    /// has scouted: the Beacon sees across its own build zone.
    func testBeaconForwardBase() throws {
        launch(["-autostart", "-seed", "4", "-beaconcheck"])
        XCTAssertTrue(hud())
        let beacon = element("cmd_inst4")
        XCTAssertTrue(beacon.waitForExistence(timeout: 10), "Beacon configure button"); sleep(1)
        shot("beacon_01_configure_menu")
        beacon.tap(); sleep(2)
        shot("beacon_02_configured")
        app.buttons["test_select_workers"].tap(); sleep(1)
        element("cmd_build").tap()
        let hall = app.descendants(matching: .any).matching(identifier: "cmd_b2").firstMatch
        XCTAssertTrue(hall.waitForExistence(timeout: 3)); hall.tap(); sleep(1)
        center().tap(); sleep(1)
        let reason = element("placementReason")
        XCTAssertTrue(reason.waitForExistence(timeout: 3))
        let label = reason.label
        print("BEACON-CHECK \(label)")
        shot("beacon_03_barracks_14_tiles")
        let confirm = app.buttons["confirmPlacement"]
        XCTAssertTrue(label.contains("14 tiles") && confirm.isEnabled, "a barracks 14 tiles from a Beacon should be placeable: \(label)")
        if confirm.isEnabled { confirm.tap(); sleep(2); shot("beacon_04_barracks_placed") }
    }

    // MARK: Replay round trip

    func testQuickMatchThenReplay() throws {
        launch(["-autostart", "-quick", "-seed", "12", "-map", "crossroads", "-faction", "humans", "-enemy", "machines", "-difficulty", "hard"])
        XCTAssertTrue(hud()); sleep(2)
        // A few real orders: train a worker at the HQ, send the workers out, then the army later.
        let title = app.staticTexts["selectionTitle"]
        for dy in stride(from: -80, through: -20, by: 15) {
            center().withOffset(CGVector(dx: 0, dy: dy)).tap()
            if title.waitForExistence(timeout: 1), title.label == "Command Hub" { break }
        }
        if element("cmd_u0").waitForExistence(timeout: 3) { element("cmd_u0").tap(); element("cmd_u0").tap() }
        app.buttons["test_select_workers"].tap(); sleep(1)
        center().withOffset(CGVector(dx: 90, dy: 60)).tap(); sleep(1)
        shot("replay_01_live_orders")
        openPause(); sleep(1)
        app.segmentedControls.buttons["2×"].tap()
        app.buttons["Resume"].tap()
        let back = app.buttons["RETURN TO COMMAND"]
        XCTAssertTrue(back.waitForExistence(timeout: 900), "the quick match should end")
        let result = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Match time'")).firstMatch.label
        print("LIVE-RESULT \(result)")
        shot("replay_02_live_game_over")
        back.tap()
        // A finished match returns to the title screen, where its recording is under REPLAYS.
        let replays = app.buttons["REPLAYS"]
        XCTAssertTrue(replays.waitForExistence(timeout: 20), "REPLAYS on the title screen"); replays.tap(); sleep(1)
        shot("replay_03_list")
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); print("REPLAY-ROW \(row.label)"); row.tap()
        XCTAssertTrue(app.buttons["FOLLOW ON"].waitForExistence(timeout: 60) || app.buttons["FOLLOW OFF"].exists, "replay viewer")
        sleep(3); shot("replay_04_playing")
        for s in ["8×", "4×"] { let b = app.buttons[s]; if b.exists { b.tap(); break } }
        let over = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Match time'")).firstMatch
        XCTAssertTrue(over.waitForExistence(timeout: 900), "the replay should reach its end")
        print("REPLAY-RESULT \(over.label)")
        shot("replay_05_replay_game_over")
        XCTAssertEqual(over.label, result, "replay should end at the same time as the live match")
    }
}
