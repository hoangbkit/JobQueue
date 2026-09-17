//
//  JobQueueDemoUITests.swift
//  JobQueueDemoUITests
//
//  Created by Hoang Nguyen on 2/6/26.
//

import XCTest

final class JobQueueDemoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQueueBadgeOpensEmptyQueuePopover() throws {
        let app = launchApp()

        app.buttons["demo-queue-badge-button"].click()

        XCTAssertTrue(app.staticTexts["Queue Empty"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["serial-job-queue-empty-state"].exists)
    }

    @MainActor
    func testSeedJobsShowsQueueTable() throws {
        let app = launchApp()

        app.buttons["demo-seed-jobs-button"].click()

        XCTAssertTrue(app.tables["serial-job-queue-table"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Task"].exists)
        XCTAssertTrue(app.staticTexts["Status"].exists)
        XCTAssertTrue(app.staticTexts["Added"].exists)
    }

    @MainActor
    func testBrokenJSONShowsPersistenceRecoveryActions() throws {
        let app = launchApp()

        app.buttons["demo-break-json-button"].click()

        XCTAssertTrue(app.otherElements["serial-job-queue-persistence-banner"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Saved queue data could not be loaded."].exists)
        XCTAssertTrue(app.buttons["serial-job-queue-persistence-retryPersistence"].exists)
        XCTAssertTrue(app.buttons["serial-job-queue-persistence-resetPersistence"].exists)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }
}
