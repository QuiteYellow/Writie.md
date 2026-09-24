//
//  WorkspaceDropUITests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import XCTest

/**
 What a file dropped on the editor does to the folder around it.

 **Why a debug menu item and not a drag.** A drag between two applications cannot be
 synthesized here: AppleScript, the accessibility API and `CGEvent` are all refused on this
 machine, and XCUITest drives one app rather than the space between two. So the item calls the
 same delegate method `EditorWebView.performDragOperation` calls, one step inside the drag, and
 what these tests assert is everything after that point — the copy into `assets/`, the file
 left where it was, the second file that does not overwrite the first.

 **What it therefore does not cover**, and what has to be checked by hand on a machine someone
 is sitting at: the promise branch, which needs a real promise drag (a screenshot, a Mail
 attachment, an SFTP drag), and the save panel an untitled document raises. `TRACKER.md` has
 the recipe.

 A file of its own, which costs **4 `project.pbxproj` lines**: the sidebar suite is at
 SwiftLint's `type_body_length` ceiling and the launch suite is about launching. Group D has
 two more passes to come, and they belong here rather than in either of those.
 */
final class WorkspaceDropUITests: XCTestCase {
  /// The whole of D10's file half: the dropped file is copied in beside the document, under
  /// `assets/`, and the original is still where it was.
  func testADroppedFileIsCopiedIntoAssetsBesideTheDocument() throws {
    let root = try makeFixture(["note.md"])
    let source = try makeFixture(["photo.png"]).appending(path: "photo.png")
    let app = launchApp(root: root, dropping: [source])

    openNote(in: app)
    drop(in: app)

    XCTAssertTrue(waitForFile(at: root.appending(path: "assets").appending(path: "photo.png")), "nothing landed in assets/")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: source.path(percentEncoded: false)),
      "the original was moved rather than copied"
    )

    // And the link that went into the document is the relative one, read back off disk rather
    // than out of the web view: the whole point of the copy is that `assets/photo.png` resolves
    // wherever the note travels to.
    app.typeKey("s", modifierFlags: .command)
    XCTAssertTrue(
      waitForContents(of: root.appending(path: "note.md"), containing: "](assets/photo.png)"),
      "the document does not carry a relative link to the copy"
    )
  }

  /**
   A note dropped on the editor opens; it is not copied into `assets/` and linked.

   Reported by the user against the first build of D10, and they are right: a `.md` is a file
   you want to read, and the old answer — copy it into the folder's `assets/` and write a link
   to the copy — is nobody's idea of what dropping a note means. Everything the app can open
   behaves this way now; an image still becomes an attachment, which the test above asserts.
   */
  func testADroppedNoteIsOpenedInsteadOfAttached() throws {
    let root = try makeFixture(["note.md"])
    let dropped = try makeFixture(["dropped.md"]).appending(path: "dropped.md")
    let app = launchApp(root: root, dropping: [dropped])

    openNote(in: app)
    drop(in: app)

    let window = app.windows.firstMatch
    let showing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "title == %@", "dropped.md"), object: window)
    XCTAssertEqual(
      XCTWaiter().wait(for: [showing], timeout: Constants.timeout),
      .completed,
      "the window shows \(window.title) rather than the note that was dropped on it"
    )

    XCTAssertFalse(
      FileManager.default.fileExists(atPath: root.appending(path: "assets").path(percentEncoded: false)),
      "a note was copied into assets/ as well as opened"
    )
  }

  /**
   Opening a file that is not in the folder being listed leaves nothing highlighted.

   Reported by the user against the first build of this pass, and it is a sidebar that lies:
   the row for the *previously* open note stayed highlighted while the window showed something
   else entirely. Every other route into a window is caught by `didBecomeKey`, and an in-place
   switch is the one that never fires it — the window was already key. That was harmless while
   a sidebar click was the only thing that could switch in place, because the click had set the
   highlight itself; a dropped note is not a click.
   */
  func testOpeningAFileOutsideTheFolderClearsTheHighlight() throws {
    let root = try makeFixture(["note.md"])
    let outside = try makeFixture(["outside.md"]).appending(path: "outside.md")
    let app = launchApp(root: root, dropping: [outside])

    openNote(in: app)
    XCTAssertEqual(selectedRowIdentifier(in: app), "workspace.row.note.md", "clicking a row did not highlight it")

    drop(in: app)
    let window = app.windows.firstMatch
    let showing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "title == %@", "outside.md"), object: window)
    XCTAssertEqual(XCTWaiter().wait(for: [showing], timeout: Constants.timeout), .completed, "the drop did not open the note")

    // The highlight moves a runloop turn after the document does
    let deadline = Date(timeIntervalSinceNow: 5)
    while Date() < deadline && selectedRowIdentifier(in: app) != nil {
      Thread.sleep(forTimeInterval: 0.2)
    }

    XCTAssertNil(
      selectedRowIdentifier(in: app),
      "the sidebar still highlights a file the window is not showing"
    )
  }

  /**
   A file that came from a promise and cannot be copied in says so, and links nothing.

   **The end-to-end version of the bug the user found by keeping notes outside the home
   directory.** A file dragged out of Transmit was received into the app's container, the copy
   into `assets/` was refused, and the fallback — right for a Finder drop, whose original stays
   put — wrote a link into a temporary folder the system reaps.

   The refusal is reproduced by the file system rather than by the sandbox: `assets` already
   exists here, as a *file*. The sandbox version needs a folder outside the home directory,
   which the app cannot even list, so it cannot be set up from a test at all — which is the
   other half of why this bug survived a green suite. **Every fixture in this target lives under
   `~`, the one place the app's entitlement makes writes succeed.**
   */
  func testAReceivedFileThatCannotBeCopiedInSaysSoAndLinksNothing() throws {
    let root = try makeFixture(["note.md", "assets"])
    let source = try makeFixture(["photo.png"]).appending(path: "photo.png")
    let app = launchApp(root: root, dropping: [source], asReceived: true)

    openNote(in: app)
    drop(in: app)

    let sheet = app.windows.firstMatch.sheets.firstMatch
    XCTAssertTrue(sheet.waitForExistence(timeout: Constants.timeout), "the drop failed silently")
    XCTAssertTrue(sheet.buttons["Grant Access…"].exists, "the alert offers no way to fix it")

    sheet.buttons["Cancel"].click()
    app.typeKey("s", modifierFlags: .command)

    // Nothing at all, rather than a link into the folder the file happened to be sitting in
    Thread.sleep(forTimeInterval: 1)
    let text = try String(contentsOf: root.appending(path: "note.md"), encoding: .utf8)
    XCTAssertFalse(text.contains("photo.png"), "a file that could not be brought in was linked anyway")
  }

  /// A second file of the same name is a second file. Overwriting someone's attachment because
  /// two screenshots share a name is the kind of loss nothing announces.
  func testASecondDropOfTheSameNameDoesNotOverwriteTheFirst() throws {
    let root = try makeFixture(["note.md"])
    let first = try makeFixture(["photo.png"]).appending(path: "photo.png")
    let second = try makeFixture(["photo.png"]).appending(path: "photo.png")
    let app = launchApp(root: root, dropping: [first, second])

    openNote(in: app)
    drop(in: app)

    let assets = root.appending(path: "assets")
    XCTAssertTrue(waitForFile(at: assets.appending(path: "photo-1.png")), "the second drop did not land")
    XCTAssertTrue(FileManager.default.fileExists(atPath: assets.appending(path: "photo.png").path(percentEncoded: false)))
  }

  /// A file that is already in the document's own folder is linked where it lies. Copying it
  /// would leave two of it in a folder someone curates, and it is already as portable.
  func testAFileAlreadyBesideTheDocumentIsNotCopied() throws {
    let root = try makeFixture(["note.md", "photo.png"])
    let app = launchApp(root: root, dropping: [root.appending(path: "photo.png")])

    openNote(in: app)
    drop(in: app)

    // Nothing to wait for, so give the drop the same chance the other tests give it
    Thread.sleep(forTimeInterval: 2)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: root.appending(path: "assets").path(percentEncoded: false)),
      "a file already beside the document was copied into assets/"
    )
  }

  // MARK: - D11a, the sidebar

  /**
   A file dropped on a folder row lands in that folder.

   The half the module's own tests cannot reach. They plant `rowFrames` and prove the
   arithmetic over it; this drives the **live** view, so what it establishes is that the rows
   report their frames at all and that a point inside one resolves to the folder it names. The
   hook returns false rather than falling back to the root when a row has reported nothing, so
   a sidebar that never measured itself fails here instead of passing quietly.

   Still not covered, and still a manual check: whether the point AppKit hands a real drag
   lands inside those same frames.
   */
  func testAFileDroppedOnAFolderRowLandsInThatFolder() throws {
    let root = try makeFixture(["sub/inner.md", "note.md"])
    let source = try makeFixture(["photo.png"]).appending(path: "photo.png")
    let app = launchApp(root: root, droppingOnSidebar: [source], row: "sub")

    waitForSidebar(in: app, row: "sub")
    dropOnSidebar(in: app)

    XCTAssertTrue(waitForFile(at: root.appending(path: "sub").appending(path: "photo.png")), "nothing landed in sub/")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: root.appending(path: "photo.png").path(percentEncoded: false)),
      "the file landed in the root rather than in the folder it was dropped on"
    )
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: source.path(percentEncoded: false)),
      "the original was moved rather than copied"
    )
  }

  /// Empty space under the last row is still a drop, and it means the folder being shown.
  func testAFileDroppedOnTheSidebarItselfLandsInTheRoot() throws {
    let root = try makeFixture(["sub/inner.md", "note.md"])
    let source = try makeFixture(["photo.png"]).appending(path: "photo.png")
    let app = launchApp(root: root, droppingOnSidebar: [source], row: nil)

    waitForSidebar(in: app, row: "note.md")
    dropOnSidebar(in: app)

    XCTAssertTrue(waitForFile(at: root.appending(path: "photo.png")), "nothing landed in the root")
  }

  /// ⌘ moves rather than copies. The modifier cannot be held across a gesture XCUITest is not
  /// performing, so the environment stands in for it — which is the one thing about this test
  /// that is not the real path.
  func testTheMoveModifierTakesTheFileOutOfWhereItWas() throws {
    let root = try makeFixture(["sub/inner.md"])
    let elsewhere = try makeFixture(["photo.png"])
    let source = elsewhere.appending(path: "photo.png")
    let app = launchApp(root: root, droppingOnSidebar: [source], row: "sub", moving: true)

    waitForSidebar(in: app, row: "sub")
    dropOnSidebar(in: app)

    XCTAssertTrue(waitForFile(at: root.appending(path: "sub").appending(path: "photo.png")), "nothing landed in sub/")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: source.path(percentEncoded: false)),
      "a move left the original where it was"
    )
  }
}

// MARK: - Private

private extension WorkspaceDropUITests {
  enum Constants {
    static let timeout: TimeInterval = 30
  }

  /// The app, rooted at `root`, with `files` queued behind the debug menu's drop item.
  /// `asReceived` makes the drop behave as a promise drag's output — the half that may not fall
  /// back to linking a file where it lies.
  func launchApp(root: URL, dropping files: [URL], asReceived: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    // Window restoration and document persistence off, as every launch in this target has
    // them: otherwise a run inherits the previous run's windows and its untitled draft.
    app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO", "-ApplePersistence", "NO"]
    app.launchEnvironment["DEBUG_WORKSPACE_SIDEBAR"] = "YES"
    app.launchEnvironment["DEBUG_WORKSPACE_ROOT"] = root.path
    app.launchEnvironment["DEBUG_WORKSPACE_DROP_PATHS"] = files.map(\.path).joined(separator: ":")

    if asReceived {
      app.launchEnvironment["DEBUG_WORKSPACE_DROP_RECEIVED"] = "YES"
    }

    app.launch()
    return app
  }

  /// Click `note.md`, and wait for the window to actually be showing it — the drop goes to
  /// whichever document the editor holds, so asserting on the folder afterwards is only
  /// meaningful once the switch has happened.
  func openNote(in app: XCUIApplication) {
    let note = app.descendants(matching: .any)["workspace.row.note.md"]
    XCTAssertTrue(note.waitForExistence(timeout: Constants.timeout), "no note.md row in the sidebar")
    note.click()

    let window = app.windows.firstMatch
    let showing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "title == %@", "note.md"), object: window)
    XCTAssertEqual(
      XCTWaiter().wait(for: [showing], timeout: Constants.timeout),
      .completed,
      "the window shows \(window.title) rather than note.md"
    )
  }

  /// ⌘⌃0, the debug menu's drop item.
  func drop(in app: XCUIApplication) {
    app.typeKey("0", modifierFlags: [.command, .control])
  }

  /// The app, rooted at `root`, with `files` queued behind the debug menu's **sidebar** drop
  /// item. `row` names the row to drop on, by file name; nil means the sidebar itself.
  func launchApp(root: URL, droppingOnSidebar files: [URL], row: String?, moving: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO", "-ApplePersistence", "NO"]
    app.launchEnvironment["DEBUG_WORKSPACE_SIDEBAR"] = "YES"
    app.launchEnvironment["DEBUG_WORKSPACE_ROOT"] = root.path
    app.launchEnvironment["DEBUG_WORKSPACE_SIDEBAR_DROP_PATHS"] = files.map(\.path).joined(separator: ":")

    if let row {
      app.launchEnvironment["DEBUG_WORKSPACE_SIDEBAR_DROP_ROW"] = row
    }

    if moving {
      app.launchEnvironment["DEBUG_WORKSPACE_SIDEBAR_DROP_MOVE"] = "YES"
    }

    app.launch()
    return app
  }

  /// Wait for the tree to be listed. The drop reads the frames the rows report, so a drop sent
  /// before there are any rows would be measuring an empty sidebar.
  func waitForSidebar(in app: XCUIApplication, row name: String) {
    let row = app.descendants(matching: .any)["workspace.row.\(name)"]
    XCTAssertTrue(row.waitForExistence(timeout: Constants.timeout), "no \(name) row in the sidebar")
  }

  /// ⌘⌀9, the debug menu's sidebar drop item.
  func dropOnSidebar(in app: XCUIApplication) {
    app.typeKey("9", modifierFlags: [.command, .control])
  }

  /// The document, saved and read back, because what was inserted is the thing being asserted
  /// on — and a web view's text is not reliably reachable from here.
  func waitForContents(of url: URL, containing snippet: String) -> Bool {
    let deadline = Date(timeIntervalSinceNow: Constants.timeout)
    while Date() < deadline {
      if let text = try? String(contentsOf: url, encoding: .utf8), text.contains(snippet) {
        return true
      }

      Thread.sleep(forTimeInterval: 0.2)
    }

    return false
  }

  func waitForFile(at url: URL) -> Bool {
    let deadline = Date(timeIntervalSinceNow: Constants.timeout)
    while Date() < deadline {
      if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
        return true
      }

      Thread.sleep(forTimeInterval: 0.2)
    }

    return false
  }
}
