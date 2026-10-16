//
//  SettingsViewModelTests.swift
//  MoonforgeTests
//
//  Created by Codex on 19.03.26.
//

import XCTest
@testable import Moonforge

final class SettingsViewModelTests: XCTestCase {
    func testLoadsInitialSettings() {
        let service = InMemorySettingsService(
            initial: Settings(isDarkModeEnabled: true, targetFrameRate: 30)
        )

        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertTrue(viewModel.isDarkModeEnabled)
        XCTAssertEqual(viewModel.targetFrameRate, 30)
    }

    func testAutoSavesOnChange() {
        let service = InMemorySettingsService(
            initial: Settings(isDarkModeEnabled: false, targetFrameRate: 60)
        )
        let expectation = XCTestExpectation(description: "Auto-save triggered")
        service.onSave = { _ in
            expectation.fulfill()
        }

        let viewModel = SettingsViewModel(settingsService: service)
        viewModel.targetFrameRate = 120

        wait(for: [expectation], timeout: 0.2)

        let saved = service.load()
        XCTAssertEqual(saved.targetFrameRate, 120)
        XCTAssertEqual(saved.isDarkModeEnabled, false)
    }

    func testLoadSettingsDoesNotTriggerSave() {
        let service = InMemorySettingsService(
            initial: Settings(isDarkModeEnabled: true, targetFrameRate: 30)
        )

        var saveCount = 0
        service.onSave = { _ in
            saveCount += 1
        }

        let viewModel = SettingsViewModel(settingsService: service)
        viewModel.loadSettings()

        XCTAssertEqual(saveCount, 0)
        XCTAssertTrue(viewModel.isDarkModeEnabled)
        XCTAssertEqual(viewModel.targetFrameRate, 30)
    }

    func testInvalidFrameRateFallsBackToDefault() {
        let service = InMemorySettingsService(
            initial: Settings(isDarkModeEnabled: false, targetFrameRate: 999)
        )

        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertEqual(viewModel.targetFrameRate, Settings.default.targetFrameRate)
    }
}
