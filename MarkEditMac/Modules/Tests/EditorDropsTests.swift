//
//  EditorDropsTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit
import Testing
@testable import Workspace

/**
 What a drop onto the editor does with each kind of thing that can land on it.

 The decision, not the drag: a drag between two applications cannot be synthesized on this
 machine, and `NSDraggingInfo` is an AppKit protocol with a dozen members that a test would have
 to stub before it could ask the one question worth asking. `route` is that question, factored
 out — it is what `takesOver` and the promise receiver both call.
 */
@MainActor
struct EditorDropsTests {
  /// The report that started this: a `.md` dropped on the editor was copied into `assets/` and
  /// linked, when what anyone means by it is "open this note".
  @Test
  func opensANoteInsteadOfAttachingIt() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md"])
    let host = RecordingHost()

    let attachments = EditorDrops.route([folder.appending(path: "note.md")], host: host, roots: scratch.store())
    #expect(attachments.isEmpty, "a note was treated as an attachment")
    #expect(host.openedInPlace == [folder.appending(path: "note.md")])
  }

  /// One window cannot show three files, and dropping three is asking for three.
  @Test
  func opensTheFirstInPlaceAndTheRestInWindowsOfTheirOwn() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["one.md", "two.md", "three.md"])
    let urls = ["one.md", "two.md", "three.md"].map { folder.appending(path: $0) }
    let host = RecordingHost()

    #expect(EditorDrops.route(urls, host: host, roots: scratch.store()).isEmpty)
    #expect(host.openedInPlace == [urls[0]])
    #expect(host.openedInNewWindow == [urls[1], urls[2]])
  }

  /// An image is an attachment, which is the case group D was built for in the first place.
  @Test
  func leavesAnImageToTheAssetsPath() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["photo.png"])
    let photo = folder.appending(path: "photo.png")
    let host = RecordingHost()

    #expect(EditorDrops.route([photo], host: host, roots: scratch.store()) == [photo])
    #expect(host.openedInPlace.isEmpty)
  }

  /// A folder dropped on the editor opens as the sidebar's root. The alternative was copying a
  /// whole directory tree into `assets/`, silently.
  @Test
  func opensAFolderAsTheWorkspaceRoot() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md"])
    let store = scratch.store()
    let host = RecordingHost()

    #expect(EditorDrops.route([folder], host: host, roots: store).isEmpty)
    try expectSameFolder(store.url, folder)
    #expect(host.openedInPlace.isEmpty, "the folder was opened as a document")
  }

  /// A drop of several things is sorted rather than decided as a whole: the note opens, the
  /// image is still attached.
  @Test
  func sortsAMixedDropRatherThanChoosingOneAnswer() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md", "photo.png"])
    let note = folder.appending(path: "note.md")
    let photo = folder.appending(path: "photo.png")
    let host = RecordingHost()

    #expect(EditorDrops.route([note, photo], host: host, roots: scratch.store()) == [photo])
    #expect(host.openedInPlace == [note])
  }

  /**
   A promised file arrives from the queue AppKit hands it to, and does not take the app down.

   **Written after a real crash**: dragging an image out of Transmit killed the app, because the
   reader closure captured a `@MainActor` `self` and so carried an executor check into a call
   AppKit makes on its own queue. An `NSFilePromiseReceiver` cannot be constructed by hand, so
   this does what the receiver does — calls the reader from a background queue — and asserts the
   file comes out the other side.

   **Being honest about what it does and does not cover:** it exercises the off-main path, and
   it would have caught a hop that never arrives. It would *not* have caught the original crash,
   because the fix was structural — the closure takes its session as a parameter now instead of
   capturing `self`, which is what removes the isolation inference. `@Sendable` on the return
   type is what keeps that from being reintroduced, and the compiler enforces it.
   */
  @Test
  func acceptsAPromisedFileDeliveredOffTheMainThread() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md", "photo.png"])
    let photo = folder.appending(path: "photo.png")

    let document = NSDocument()
    document.fileURL = folder.appending(path: "note.md")

    let delivery = Delivery()
    let session = DropSession(document: document, host: nil) { delivery.urls = $0 }
    session.awaitFiles(expecting: 1, buckets: 1)

    let reader = DropSession.reader(for: session, at: 0)
    let queue = OperationQueue()
    queue.addOperation { reader(photo, nil) }

    let deadline = Date(timeIntervalSinceNow: 2)
    while Date() < deadline && delivery.urls.isEmpty {
      try await Task.sleep(for: .milliseconds(10))
    }

    // What comes out is the copy beside the document, not the file that arrived: a received
    // file lives somewhere temporary, so the session brings it in before anything is linked
    #expect(delivery.urls == [folder.appending(path: "assets").appending(path: "photo.png")])
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "assets/photo.png").path(percentEncoded: false)))
  }

  /**
   A received file that cannot be copied in is not linked from the temporary folder it landed in.

   **The bug the user reported**, reduced to its mechanism: the promise arrived, the copy into
   `assets/` failed, and the fallback — right for a file dragged out of Finder, whose original
   stays put — wrote a link into the app's own container, which the system reaps. Nothing
   inserted is worse than a working link and far better than one that rots, and the alert that
   goes with it carries whatever the file system said.

   The copy is made to fail the way the file system can fail it: `assets` already exists, as a
   *file*.
   */
  @Test
  func doesNotLinkAReceivedFileItCouldNotCopyIn() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md"])
    try Data().write(to: folder.appending(path: "assets"))

    let document = NSDocument()
    document.fileURL = folder.appending(path: "note.md")

    let delivery = Delivery()
    let session = DropSession(document: document, host: nil) { delivery.urls = $0 }
    session.awaitFiles(expecting: 1, buckets: 1)

    let received = try scratch.folder(["photo.png"]).appending(path: "photo.png")
    DropSession.reader(for: session, at: 0)(received, nil)

    try await Task.sleep(for: .milliseconds(100))
    #expect(delivery.urls.isEmpty, "a file in a temporary folder was linked from where it lay")
  }

  /// A promise that fails still calls back, with a URL for a file that was never written —
  /// so what arrives has to be checked rather than trusted.
  @Test
  func ignoresAPromiseThatFailed() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md"])
    let document = NSDocument()
    document.fileURL = folder.appending(path: "note.md")

    let delivery = Delivery()
    let session = DropSession(document: document, host: nil) { delivery.urls = $0 }
    session.awaitFiles(expecting: 1, buckets: 1)

    DropSession.reader(for: session, at: 0)(folder.appending(path: "never-written.png"), nil)
    try await Task.sleep(for: .milliseconds(50))
    #expect(delivery.urls.isEmpty, "a file that was never written was linked")
  }

  /// With no host there is nothing to open into, so everything falls through to the path that
  /// existed before any of this — which is also what happens with ⇧ or ⌥ held.
  @Test
  func attachesEverythingWhenThereIsNoHost() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md"])
    let note = folder.appending(path: "note.md")

    #expect(EditorDrops.route([note], host: nil, roots: scratch.store()) == [note])
  }
}

// MARK: - Private

/// Somewhere for the delivered URLs to land that a closure can write to from the main actor.
@MainActor
private final class Delivery {
  var urls = [URL]()
}
