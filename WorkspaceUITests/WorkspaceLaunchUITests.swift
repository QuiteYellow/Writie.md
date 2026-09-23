//
//  WorkspaceLaunchUITests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import XCTest

/**
 What opening the app fresh does, asserted against the running app.

 Separate from `WorkspaceSidebarUITests` because these tests are the only ones that drive the
 launch rule *through* its persisted state rather than around it. The sidebar suite uses
 `DEBUG_WORKSPACE_ROOT`, which opens a folder and deliberately forgets it; nothing here may do
 that, because what a launch remembers is the whole subject.

 That makes them the only tests that write state outliving the process, into the `UserDefaults`
 of the app installed on this machine — so every launch here books its own undo first. See
 `launchApp(pinnedRoot:savedRoot:clearsPin:)`.
 */
final class WorkspaceLaunchUITests: XCTestCase {
  /**
   A launch with a folder opens an untitled document, not a file panel.

   Upstream's default is the panel, and this is the assertion that the fork's rule overrides
   it. The panel is checked for by its Cancel button rather than by a window count, because a
   panel that did appear would be modal and every later query in the test would time out
   against it — a failure that reads as "the app hung" instead of "the panel is back".

   `DEBUG_WORKSPACE_SIDEBAR` is deliberately not set here: the sidebar showing is *part of*
   what a folder-rooted launch is supposed to do, so forcing it would assert nothing.
   */
  func testAFolderRootedLaunchOpensAnUntitledDocument() throws {
    let root = try makeFixture(["alpha.md"])
    let app = launchApp(root: root)

    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: Constants.timeout))
    XCTAssertFalse(app.sheets.buttons["Cancel"].exists, "a file panel is in the way")
    XCTAssertFalse(app.dialogs.buttons["Cancel"].exists, "a file panel is in the way")

    // An untitled document, which is what "no document" means in a document-based app
    XCTAssertTrue(
      window.title.contains(Constants.untitledTitle),
      "expected an untitled document, window is titled \(window.title)"
    )

    // And the sidebar came with it, unforced
    let alpha = app.descendants(matching: .any)["workspace.row.alpha.md"]
    XCTAssertTrue(alpha.waitForExistence(timeout: Constants.timeout), "the folder's sidebar did not open with it")
  }

  /**
   Clicking a file from the launch draft switches the window, with no save panel.

   The regression this exists for, and it was found by measurement rather than by reading:
   once a launch started opening an untitled document, the *first* sidebar click of every
   session raised a save panel — a blank document the user had never typed in, asking to be
   saved before the fork's central gesture could happen.

   The cause was that a brand-new document is neither empty nor unedited: traced off the
   running app as `fileURL=nil edited=true len=1`, the one character being a line break the
   editor adds itself. See `WorkspaceDocumentSwitcher.discardDraftThenPerform`.

   The sheet is asserted absent as well as the title being right, because those are two
   different failures: a wrong title alone means the switch did not happen, while a sheet means
   it stopped to ask.
   */
  func testClickingAFileFromTheLaunchDraftAsksNothing() throws {
    let root = try makeFixture(["alpha.md"])
    let app = launchApp(root: root)

    let alpha = app.descendants(matching: .any)["workspace.row.alpha.md"]
    XCTAssertTrue(alpha.waitForExistence(timeout: Constants.timeout))
    alpha.click()

    let window = app.windows.firstMatch
    let titled = expectation(description: "the window shows alpha.md")
    let observer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
      if window.title.contains("alpha.md") {
        titled.fulfill()
      }
    }

    defer { observer.invalidate() }
    XCTAssertEqual(XCTWaiter.wait(for: [titled], timeout: Constants.timeout), .completed, "the window still shows \(window.title)")
    XCTAssertEqual(app.sheets.count, 0, "the switch stopped to ask about a draft nobody typed in")
  }

  /**
   A launch with a pinned folder opens the pin, not the folder that was last used.

   The whole point of Custom mode, and the one thing about it a unit test cannot show: that the
   pin survives a real process boundary into a signed sandboxed app, through the same
   `UserDefaults` a person's own launch reads.
   */
  func testAPinnedFolderIsWhatALaunchOpens() throws {
    let pinned = try makeFixture(["pinned.md"])
    let app = launchApp(pinnedRoot: pinned)

    let footer = app.descendants(matching: .any)["workspace.footer.root"]
    XCTAssertTrue(footer.waitForExistence(timeout: Constants.timeout), "no root control")
    XCTAssertEqual(text(of: footer), pinned.lastPathComponent)
  }

  /**
   Custom mode with nothing pinned falls back rather than opening nothing.

   Reachable by choosing Custom and cancelling the panel, and the failure it guards against is
   an app that looks broken while working perfectly: a folder is configured, so the sidebar
   should still be there, listing the last folder.
   */
  func testCustomModeWithNoPinFallsBackToTheLastFolder() throws {
    let last = try makeFixture(["last.md"])

    // A launch that leaves a folder behind as the last used one, the way a person's would
    launchApp(pinnedRoot: nil, savedRoot: last).terminate()

    let app = launchApp(pinnedRoot: nil, clearsPin: true)
    let footer = app.descendants(matching: .any)["workspace.footer.root"]
    XCTAssertTrue(footer.waitForExistence(timeout: Constants.timeout), "no root control")
    XCTAssertEqual(text(of: footer), last.lastPathComponent, "Custom with no pin should fall back")
  }

  /**
   A pinned folder that has been deleted leaves the app running, with the sidebar explaining
   itself.

   This is the requirement that nothing about a folder may stop the app loading. The folder is
   removed between the launch that pins it and the launch that tries to open it, so the second
   launch resolves a bookmark to something that is not there — and what it must produce is a
   window with an empty sidebar, not a hang and not a file panel.
   */
  func testAPinnedFolderThatIsGoneStillLaunches() throws {
    let pinned = try makeFixture(["gone.md"])
    launchApp(pinnedRoot: pinned).terminate()
    try FileManager.default.removeItem(at: pinned)

    let app = launchApp(pinnedRoot: nil)
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Constants.timeout), "the app did not launch")

    let placeholder = app.descendants(matching: .any)["workspace.placeholder"]
    XCTAssertTrue(placeholder.waitForExistence(timeout: Constants.timeout), "no sidebar to explain the missing folder")
    XCTAssertFalse(app.dialogs.buttons["Cancel"].exists, "a file panel is in the way")
  }

  /// The Settings row, and that it names the pinned folder. The panel behind Choose Folder…
  /// is the half no test here can drive, so this asserts on everything up to it.
  func testSettingsNamesThePinnedFolder() throws {
    let pinned = try makeFixture(["pinned.md"])
    let app = launchApp(pinnedRoot: pinned)
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Constants.timeout))

    app.typeKey(",", modifierFlags: .command)

    // Settings opens on the Editor tab — `AppDelegate.showPreferences` lists the tabs as
    // editor, assistant, general, window — so the tab has to be selected before the row it
    // holds can exist. Measured by the test failing with "no pinned folder row" against a
    // Settings window that was open and perfectly fine.
    let general = app.toolbars.buttons[Constants.generalTabLabel]
    XCTAssertTrue(general.waitForExistence(timeout: Constants.timeout), "no General tab in Settings")
    general.click()

    let name = app.descendants(matching: .any)[Constants.pinnedFolderIdentifier]
    XCTAssertTrue(name.waitForExistence(timeout: Constants.timeout), "no pinned folder row in Settings")
    XCTAssertEqual(text(of: name), pinned.lastPathComponent)
    XCTAssertTrue(
      app.descendants(matching: .any)[Constants.choosePinnedFolderIdentifier].exists,
      "no way to change the pinned folder"
    )
  }

  // MARK: - Private

  private enum Constants {
    static let timeout: TimeInterval = 30

    /// What AppKit titles a document with no file. Not localised here: the suite runs against
    /// the app's own language, which is the one this string is read in.
    static let untitledTitle = "Untitled"

    /// Upstream's own title for the Settings tab the fork's rows live on.
    static let generalTabLabel = "General"

    static let pinnedFolderIdentifier = "workspace.settings.pinned-folder"
    static let choosePinnedFolderIdentifier = "workspace.settings.choose-pinned-folder"
  }

  /**
   A launch driven through the launch-folder rule rather than around it.

   The sidebar suite's `DEBUG_WORKSPACE_ROOT` opens a folder and deliberately forgets it, which
   is exactly wrong here. So this writes real state — a pin, or a last-used folder — the same
   way the panels would, and then lets the rule decide.

   Nothing forces the sidebar open either. Whether it appears is part of what is being tested.

   - Parameters:
     - pinnedRoot: pinned as the Custom folder, and Custom selected. Nil leaves the pin as it is.
     - savedRoot: remembered as the last used folder, as the sidebar's own picker would.
     - clearsPin: select Custom with *nothing* pinned, which is the fallback case.
   */
  @discardableResult
  private func launchApp(pinnedRoot: URL?, savedRoot: URL? = nil, clearsPin: Bool = false) -> XCUIApplication {
    // The state these launches write outlives the test — that is the point of them — and the
    // app under test is the one installed on this machine, sharing its `UserDefaults` with
    // every real launch. So each of them books its own undo before writing anything: without
    // it, a test that pins a fixture and then deletes it leaves the app pinned to nothing.
    addTeardownBlock {
      let reset = XCUIApplication()
      reset.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO", "-ApplePersistence", "NO"]
      reset.launchEnvironment["DEBUG_WORKSPACE_LAUNCH_RESET"] = "YES"
      reset.launch()
      reset.terminate()
    }

    let app = XCUIApplication()
    // Window restoration *and* document persistence off, for every launch in this target.
    // Without them each run inherits the previous run's windows, and this app leaves an
    // untitled draft behind on every launch by design — so the next launch restored that draft
    // *and* opened its own, and an app-wide query for a sidebar row then matched two windows
    // ("Multiple matching elements found"). A document opened by hand outside the suite came
    // back as the key window too. Tests must depend on their own state, not on the last thing
    // that ran. `-ApplePersistence NO` is what stops the draft half; restoration the other.
    app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO", "-ApplePersistence", "NO"]

    if let pinnedRoot {
      app.launchEnvironment["DEBUG_WORKSPACE_PIN_ROOT"] = pinnedRoot.path
    } else if clearsPin {
      app.launchEnvironment["DEBUG_WORKSPACE_PIN_ROOT"] = ""
    }

    if let savedRoot {
      app.launchEnvironment["DEBUG_WORKSPACE_SAVE_ROOT"] = savedRoot.path
    }

    app.launch()
    return app
  }

  /// A folder opened for this launch only, for the tests that want a folder without caring
  /// how it was remembered. No `DEBUG_WORKSPACE_SIDEBAR`: the sidebar appearing is part of
  /// what a folder-rooted launch is being asked to do.
  private func launchApp(root: URL) -> XCUIApplication {
    let app = XCUIApplication()
    // Window restoration *and* document persistence off, for every launch in this target.
    // Without them each run inherits the previous run's windows, and this app leaves an
    // untitled draft behind on every launch by design — so the next launch restored that draft
    // *and* opened its own, and an app-wide query for a sidebar row then matched two windows
    // ("Multiple matching elements found"). A document opened by hand outside the suite came
    // back as the key window too. Tests must depend on their own state, not on the last thing
    // that ran. `-ApplePersistence NO` is what stops the draft half; restoration the other.
    app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO", "-ApplePersistence", "NO"]
    app.launchEnvironment["DEBUG_WORKSPACE_ROOT"] = root.path
    app.launch()
    return app
  }
}
