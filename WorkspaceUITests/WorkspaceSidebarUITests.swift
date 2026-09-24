//
//  WorkspaceSidebarUITests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import XCTest

/**
 What the sidebar actually shows, asserted against the running app.

 This target exists because the alternative was reading the live view tree under lldb and
 inferring the answer from row counts and disclosure-triangle counts. That worked, but it
 answers "how many things are there" when the question is "which folder is open" — and it
 gets less trustworthy with every row added.

 XCUITest is the supported way to ask, and it works on this machine: it drives the app through
 `testmanagerd` under Xcode's automation entitlement, which is not one of the paths that a
 scripted AppleScript session finds closed here.

 Still XCTest rather than Swift Testing, deliberately: Swift Testing does not replace
 XCUITest, and `XCUIApplication` needs the `XCTestCase` lifecycle. The module's unit tests are
 the ones that moved.
 */
final class WorkspaceSidebarUITests: XCTestCase {
  /// The one that proves the target works at all: a signed, sandboxed app, launched and
  /// attached to. Everything else here depends on this and nothing else does.
  func testLaunchesAndShowsAWindow() {
    let app = launchApp(root: nil)
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Constants.timeout))
  }

  func testListsTheFoldersContents() throws {
    let root = try makeFixture([
      "alpha.md",
      "beta.md",
      "notes/nested.md",
    ])

    let app = launchApp(root: root)
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Constants.timeout))

    // Folders first, then files, each found by its own identifier rather than by position
    for name in ["notes", "alpha.md", "beta.md"] {
      let row = app.descendants(matching: .any)["workspace.row.\(name)"]
      XCTAssertTrue(row.waitForExistence(timeout: Constants.timeout), "no row for \(name)")
    }

    // The nested file is inside a collapsed folder, so it must not be showing yet
    let nested = app.descendants(matching: .any)["workspace.row.nested.md"]
    XCTAssertFalse(nested.exists, "a collapsed folder should not reveal its children")
  }

  /// Reading the open folder's name straight out of the app — the thing that used to take an
  /// lldb dump and a count of disclosure triangles.
  func testFooterNamesTheOpenFolder() throws {
    let root = try makeFixture(["only.md"])
    let app = launchApp(root: root)

    let footer = app.descendants(matching: .any)["workspace.footer.root"]
    XCTAssertTrue(footer.waitForExistence(timeout: Constants.timeout), "no root control")
    XCTAssertEqual(text(of: footer), root.lastPathComponent)
  }

  func testShowsAPlaceholderWithNoFolder() {
    let app = launchApp(root: .none, forcesEmpty: true)
    let placeholder = app.descendants(matching: .any)["workspace.placeholder"]
    XCTAssertTrue(placeholder.waitForExistence(timeout: Constants.timeout))
  }

  // MARK: - M6

  /// Expanding lists the directory, which is the whole of the lazy scan seen from outside:
  /// before the triangle is clicked the app has never read that folder.
  func testExpandingAFolderListsIt() throws {
    let root = try makeFixture(["alpha.md", "notes/nested.md"])
    let app = launchApp(root: root)

    let nested = app.descendants(matching: .any)["workspace.row.nested.md"]
    XCTAssertTrue(app.descendants(matching: .any)["workspace.row.notes"].waitForExistence(timeout: Constants.timeout))
    XCTAssertFalse(nested.exists, "a collapsed folder should not have been listed yet")

    let folder = try XCTUnwrap(row(named: "notes", in: app), "no outline row for notes")
    folder.disclosureTriangles.firstMatch.click()
    XCTAssertTrue(nested.waitForExistence(timeout: Constants.timeout), "expanding did not list the folder")

    folder.disclosureTriangles.firstMatch.click()
    XCTAssertTrue(waitForAbsence(of: nested), "collapsing did not hide the folder's contents")
  }

  /**
   A file created while the app is running appears, with nothing asking it to.

   M6's headline, and the one assertion that can only be made against a running app: the file
   is created by this process, out of band, and the app is never told.
   */
  func testPicksUpAFileCreatedWhileRunning() throws {
    let root = try makeFixture(["alpha.md"])
    let app = launchApp(root: root)

    XCTAssertTrue(app.descendants(matching: .any)["workspace.row.alpha.md"].waitForExistence(timeout: Constants.timeout))

    let added = app.descendants(matching: .any)["workspace.row.gamma.md"]
    XCTAssertFalse(added.exists)

    try Data().write(to: root.appending(path: "gamma.md"))
    XCTAssertTrue(added.waitForExistence(timeout: Constants.timeout), "the sidebar did not notice a new file")

    try FileManager.default.removeItem(at: root.appending(path: "gamma.md"))
    XCTAssertTrue(waitForAbsence(of: added), "the sidebar did not notice a file being deleted")
  }

  /// View ▸ Show Sidebar, and the title that says which way it will go.
  func testTheMenuItemTogglesTheSidebarAndNamesItself() throws {
    let root = try makeFixture(["alpha.md"])
    let app = launchApp(root: root)

    let alpha = app.descendants(matching: .any)["workspace.row.alpha.md"]
    XCTAssertTrue(alpha.waitForExistence(timeout: Constants.timeout))

    let item = app.menuBars.menuItems[Constants.toggleSidebarIdentifier]
    XCTAssertTrue(item.waitForExistence(timeout: Constants.timeout), "no sidebar menu item")
    XCTAssertEqual(text(of: item), "Hide Sidebar")

    item.click()
    XCTAssertTrue(waitForAbsence(of: alpha), "the sidebar did not hide")
    XCTAssertEqual(text(of: app.menuBars.menuItems[Constants.toggleSidebarIdentifier]), "Show Sidebar")

    app.menuBars.menuItems[Constants.toggleSidebarIdentifier].click()
    XCTAssertTrue(alpha.waitForExistence(timeout: Constants.timeout), "the sidebar did not come back")
  }

  /// Every verb the context menu offers, on a file. A folder gets the same menu without Open
  /// in New Window, which is the only difference between the two.
  func testTheContextMenuOffersTheFileActions() throws {
    let root = try makeFixture(["alpha.md"])
    let app = launchApp(root: root)

    // The row view, not the `OutlineRow` around it: an element dump reports the row itself as
    // Disabled, and right-clicking it fails with "Not hittable".
    let file = app.descendants(matching: .any)["workspace.row.alpha.md"]
    XCTAssertTrue(file.waitForExistence(timeout: Constants.timeout), "no row for alpha.md")
    file.rightClick()

    // Every verb, in the order the menu draws them. Tabbing Mode defaults to `.automatic`, so
    // Open in New Tab is showing; it is the one item the menu leaves out when tabs are off.
    let items = [
      "openInNewTab", "openInNewWindow",
      "newFile", "newFolder",
      "rename", "duplicate", "moveToTrash",
      "copyPath", "revealInFinder",
    ].map { "workspace.menu.\($0)" }
    for identifier in items {
      XCTAssertTrue(
        app.menuItems[identifier].waitForExistence(timeout: Constants.timeout),
        "the context menu is missing \(identifier)"
      )
    }

    app.menuItems["workspace.menu.rename"].click()

    // The alert comes up on the window, prefilled with the name it is about to change
    let field = app.windows.firstMatch.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: Constants.timeout), "no rename field")
    XCTAssertEqual(field.value as? String, "alpha.md")

    app.typeKey(.escape, modifierFlags: [])

    // Open in New Tab's *effect*, asserted here rather than in a test of its own because this
    // suite sits at SwiftLint's `type_body_length` ceiling. What tells a tab from a window:
    // the app gains a tab group and does **not** gain a window. Measured 2026-09-24 — before
    // the click `tabGroups` is 0 and `windows` is 1; after it, both are 1.
    file.rightClick()
    XCTAssertTrue(app.menuItems[Constants.openInNewTabIdentifier].waitForExistence(timeout: Constants.timeout))
    app.menuItems[Constants.openInNewTabIdentifier].click()

    let tabbed = expectation(for: NSPredicate(format: "count == 1"), evaluatedWith: app.tabGroups)
    XCTAssertEqual(
      XCTWaiter().wait(for: [tabbed], timeout: Constants.timeout),
      .completed,
      "Open in New Tab produced no tab group"
    )

    XCTAssertEqual(app.windows.count, 1, "Open in New Tab opened a window instead of a tab")
  }

  /// The sidebar cannot be dragged narrower than its footer needs: at the 144pt a previous
  /// launch restored, the folder's name truncated to an ellipsis.
  func testTheSidebarHasAMinimumWidth() throws {
    let root = try makeFixture(["alpha.md"])
    let app = launchApp(root: root)

    let outline = app.outlines.firstMatch
    XCTAssertTrue(outline.waitForExistence(timeout: Constants.timeout))
    XCTAssertGreaterThanOrEqual(outline.frame.width, Constants.minimumSidebarWidth)
  }

  /**
   Every tab highlights the file *it* is showing, including after cycling between them.

   The regression this exists for: `makeWindowControllers` builds the split view controller
   before it assigns `representedObject`, so a window's sidebar model was created while the
   window had no document. The selection was then only ever set by a click in that window's
   own sidebar, so a tab opened any other way highlighted nothing — measured here as
   `window=beta.md` with no selected row.
   */
  func testEachTabHighlightsItsOwnFile() throws {
    let root = try makeFixture(["alpha.md", "beta.md"])
    let app = launchApp(root: root)

    let alpha = app.descendants(matching: .any)["workspace.row.alpha.md"]
    XCTAssertTrue(alpha.waitForExistence(timeout: Constants.timeout))
    alpha.click()
    assertWindow(app, shows: "alpha.md", withRowSelected: "alpha.md")

    // Neither "open it elsewhere" item is offered for the file this window is already showing:
    // both would find the open document and just bring it forward. Asserted here because this is
    // the test that has a window showing a known file; the menu-contents test right-clicks one
    // the window is *not* showing, which is why all nine items appear there.
    alpha.rightClick()
    XCTAssertTrue(app.menuItems[Constants.newFileIdentifier].waitForExistence(timeout: Constants.timeout))
    let shown = "window=\(app.windows.firstMatch.title) row=\(selectedRowIdentifier(in: app) ?? "nil")"
    XCTAssertFalse(app.menuItems[Constants.openInNewTabIdentifier].exists, "offered a tab for the open file (\(shown))")
    XCTAssertFalse(app.menuItems[Constants.openInNewWindowIdentifier].exists, "offered a window for the open file (\(shown))")
    app.typeKey(.escape, modifierFlags: [])

    // A second tab, opened the way that used to leave it unhighlighted
    app.descendants(matching: .any)["workspace.row.beta.md"].rightClick()
    XCTAssertTrue(app.menuItems[Constants.openInNewWindowIdentifier].waitForExistence(timeout: Constants.timeout))
    app.menuItems[Constants.openInNewWindowIdentifier].click()
    assertWindow(app, shows: "beta.md", withRowSelected: "beta.md")

    // Cycling is when the disagreement was noticed, and is also what the fix hangs off:
    // the sidebar re-reads its window's document every time that window becomes key.
    bringForward("alpha.md", in: app)
    assertWindow(app, shows: "alpha.md", withRowSelected: "alpha.md")

    bringForward("beta.md", in: app)
    assertWindow(app, shows: "beta.md", withRowSelected: "beta.md")
  }

  /**
   The toolbar's sidebar button: that it is there, that it works, and where it sits.

   The position is asserted rather than left to the eye because it was wrong first. The button
   arrived hard against the traffic lights — which is what `.toggleSidebar` does on its own —
   and macOS puts it at the *trailing* edge of the sidebar's section of the titlebar, beside
   the divider. A leading `.flexibleSpace` is what moves it, and this is the assertion that
   says so.
   */
  func testTheToolbarButtonTogglesTheSidebar() throws {
    let root = try makeFixture(["alpha.md"])
    let app = launchApp(root: root)

    let alpha = app.descendants(matching: .any)["workspace.row.alpha.md"]
    XCTAssertTrue(alpha.waitForExistence(timeout: Constants.timeout))

    let button = app.toolbars.buttons[Constants.toolbarSidebarLabel]
    XCTAssertTrue(button.waitForExistence(timeout: Constants.timeout), "no sidebar button in the toolbar")

    let sidebar = app.outlines.firstMatch
    XCTAssertTrue(sidebar.waitForExistence(timeout: Constants.timeout))
    XCTAssertGreaterThan(button.frame.midX, sidebar.frame.midX, "the sidebar button is not right-aligned")
    XCTAssertLessThanOrEqual(button.frame.maxX, sidebar.frame.maxX + Constants.alignmentSlack, "the sidebar button escaped its section")

    button.click()
    XCTAssertTrue(waitForAbsence(of: alpha), "the toolbar button did not hide the sidebar")

    app.toolbars.buttons[Constants.toolbarSidebarLabel].click()
    XCTAssertTrue(alpha.waitForExistence(timeout: Constants.timeout), "the toolbar button did not bring the sidebar back")
  }

  // MARK: - Private

  private enum Constants {
    static let timeout: TimeInterval = 30
    static let minimumSidebarWidth: Double = 180
    static let toggleSidebarIdentifier = "workspace.menu.toggleSidebar"

    /// AppKit's own label for `NSToolbarItem.Identifier.toggleSidebar`, read off the running
    /// app rather than guessed — it is "Sidebar", not "Show Sidebar" like the menu item.
    static let toolbarSidebarLabel = "Sidebar"

    /// How far past the sidebar's trailing edge the button may sit. It is laid out against
    /// the split view's divider, which the outline's own frame does not include.
    static let alignmentSlack: Double = 24
    static let openInNewWindowIdentifier = "workspace.menu.openInNewWindow"
    static let openInNewTabIdentifier = "workspace.menu.openInNewTab"
    static let newFileIdentifier = "workspace.menu.newFile"
  }

  /**
   The outline row holding the row view with `name`'s identifier.

   XCUITest has no parent accessor, and the disclosure triangle is the row's sibling of the
   label rather than its child, so the row has to be found by looking for the one that
   contains the identifier. Measured from an element dump: `List(.sidebar)` is an `Outline` of
   `OutlineRow`s, each with an `NSOutlineViewDisclosureButtonKey` triangle and a `Cell`.
   */
  private func row(named name: String, in app: XCUIApplication) -> XCUIElement? {
    let rows = app.outlines.firstMatch.outlineRows
    for index in 0..<rows.count {
      let row = rows.element(boundBy: index)
      if row.descendants(matching: .any)["workspace.row.\(name)"].exists {
        return row
      }
    }

    return nil
  }

  /// `waitForExistence` has no opposite, and `exists` alone races anything animated — a
  /// sidebar collapsing, a row leaving after a file is deleted.
  private func waitForAbsence(of element: XCUIElement) -> Bool {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: element
    )

    return XCTWaiter().wait(for: [gone], timeout: Constants.timeout) == .completed
  }

  /**
   Bring the window showing `title` to the front, through the Window menu.

   Not Show Next Tab: **Open in New Window makes a window, not a tab**, on purpose — it turns
   `allowsAutomaticWindowTabbing` off precisely so the file does not join the group. The
   Window menu lists every open window by title, so naming the one wanted is deterministic
   where a cycle key would depend on how many there are and which way it goes.
   */
  private func bringForward(_ title: String, in app: XCUIApplication) {
    // Scoped to the Window menu: a bare query for a file name across the menu bar also finds
    // the Open Recent entry, and XCUITest refuses to click a query matching more than one.
    let windowMenu = app.menuBars.menuBarItems["Window"]
    XCTAssertTrue(windowMenu.waitForExistence(timeout: Constants.timeout), "no Window menu")
    windowMenu.click()

    let item = windowMenu.menuItems[title]
    XCTAssertTrue(item.waitForExistence(timeout: Constants.timeout), "no Window menu entry for \(title)")
    item.click()
  }

  /// What the window is showing, and what its sidebar says it is showing. Asserting both
  /// together is the point: the bug was the two disagreeing.
  private func assertWindow(
    _ app: XCUIApplication,
    shows title: String,
    withRowSelected name: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let window = app.windows.firstMatch
    let showing = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "title == %@", title),
      object: window
    )

    XCTAssertEqual(
      XCTWaiter().wait(for: [showing], timeout: Constants.timeout),
      .completed,
      "expected the key window to show \(title), it shows \(window.title)",
      file: file,
      line: line
    )

    // The highlight arrives a runloop turn after the window does
    let expected = "workspace.row.\(name)"
    let deadline = Date(timeIntervalSinceNow: Constants.timeout)
    while Date() < deadline && selectedRowIdentifier(in: app) != expected {
      Thread.sleep(forTimeInterval: 0.2)
    }

    XCTAssertEqual(
      selectedRowIdentifier(in: app),
      expected,
      "the sidebar highlights the wrong row while the window shows \(title)",
      file: file,
      line: line
    )
  }

  /**
   Launch the app with the sidebar showing, and optionally rooted at `root`.

   `DEBUG_WORKSPACE_ROOT` opens a folder for the launch without remembering it, which is
   exactly what a test wants: no bookmark is written, so one test cannot decide what the next
   one sees. `DEBUG_WORKSPACE_SIDEBAR` starts it open, so that a test asserting on rows does
   not begin by working the toggle it is not testing.
   */
  private func launchApp(root: URL?, forcesEmpty: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    // Window restoration *and* document persistence off, for every launch in this target.
    // Without them each run inherits the previous run's windows, and this app leaves an
    // untitled draft behind on every launch by design — so the next launch restored that draft
    // *and* opened its own, and an app-wide query for a sidebar row then matched two windows
    // ("Multiple matching elements found"). A document opened by hand outside the suite came
    // back as the key window too. Tests must depend on their own state, not on the last thing
    // that ran. `-ApplePersistence NO` is what stops the draft half; restoration the other.
    app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO", "-ApplePersistence", "NO"]
    app.launchEnvironment["DEBUG_WORKSPACE_SIDEBAR"] = "YES"

    if let root {
      app.launchEnvironment["DEBUG_WORKSPACE_ROOT"] = root.path
    } else if forcesEmpty {
      // Empty means "no folder", which is not the same as saying nothing: saying nothing
      // restores whatever folder was last chosen in a real launch
      app.launchEnvironment["DEBUG_WORKSPACE_ROOT"] = ""
    }

    app.launch()
    return app
  }
}

// MARK: - Shared

/**
 The helpers both workspace suites need.

 An extension rather than a copy in each file: `text(of:)` in particular encodes a measured
 fact about where XCUITest puts a control's text, and two copies of that would drift the moment
 one of them was corrected. It lives here, with the suite that came first, because a third file
 would cost `project.pbxproj` lines for two functions.
 */
extension XCTestCase {
  /**
   The text a control is showing, whichever attribute it lands in.

   Measured rather than guessed, because all three are in play here and the wrong one reads as
   an empty string rather than an error: the footer is a `MenuButton` and its folder name
   arrives in `title`, while a sidebar row is a `StaticText` whose name arrives in `value`.
   `label` is what an `Image`-only control tends to use. Trying all three keeps a test failure
   meaning "wrong folder" instead of "wrong attribute".
   */
  func text(of element: XCUIElement) -> String {
    if !element.title.isEmpty {
      return element.title
    }

    if let value = element.value as? String, !value.isEmpty {
      return value
    }

    return element.label
  }

  /// The identifier of whichever row the key window's sidebar is drawing as selected.
  ///
  /// `isSelected` belongs to the `OutlineRow`, not to the row view inside it — asserting on
  /// the row view instead reads false for every row, including the selected one.
  func selectedRowIdentifier(in app: XCUIApplication) -> String? {
    let rows = app.outlines.firstMatch.outlineRows
    for index in 0..<rows.count {
      let row = rows.element(boundBy: index)
      if row.isSelected {
        return row.descendants(matching: .staticText).firstMatch.identifier
      }
    }

    return nil
  }

  /**
   A folder of files for one test, inside the home directory.

   Under `~` on purpose: the app is sandboxed, and upstream's home-relative-path entitlement
   is what lets it read a fixture it was never granted through a panel. A fixture in
   `/tmp` would not be readable, and the test would fail for a reason that has nothing to do
   with the sidebar.
   */
  func makeFixture(_ paths: [String]) throws -> URL {
    let root = URL(filePath: NSHomeDirectory())
      .appending(path: ".writie-uitests")
      .appending(path: UUID().uuidString)

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: root)
    }

    for path in paths {
      let url = root.appending(path: path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: url)
    }

    return root
  }
}
