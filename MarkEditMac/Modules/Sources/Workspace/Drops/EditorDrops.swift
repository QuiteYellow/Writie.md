//
//  EditorDrops.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/**
 The two drops onto the editor that cannot be answered while the mouse button is still up.

 `NSView.performDragOperation` is synchronous and returns a `Bool`, which is fine for a file
 dragged out of Finder: the file is on disk, the link can be written immediately. Two drops are
 not like that, and both of them used to insert nothing at all:

 - **A file promise.** A screenshot, a Mail attachment, a Transmit or SFTP drag — the source
   undertakes to *produce* the file at a destination the receiver names, so at drag time there
   is no file and the pasteboard's URL has an empty or `/` last path component. Upstream filters
   those out on purpose (`EditorWebView.performDragOperation`) because a link like `[](../../..)`
   is worse than nothing; the consequence is that dragging a screenshot into this editor does
   nothing whatsoever.
 - **A drop onto an untitled document.** Every link this app writes is relative, and a document
   with no location has nothing for a relative link to be relative *to*. Upstream writes an
   absolute path, which names one machine and one account and breaks the moment the file moves
   — and which would put a home directory path inside a document heading for a git repository.
   So the document is saved first and the drop replayed. Cancelling the panel means the drop did
   not happen, which is the same bargain the fork's document switch already makes at its save
   sheet. `drops.md` §1.3.

 Everything else is left exactly as it was: `takesOver` answers false and upstream's own path
 runs. The fork adds a branch, it does not replace one.
 */
@MainActor
public enum EditorDrops {
  /**
   Take the drag over when it cannot be answered synchronously, and call `deliver` with real
   files on disk once it can be.

   Returns false — having done nothing — for every drag upstream can already handle, which is
   what keeps this additive. `deliver` is called at most once, and never with an empty array:
   nothing to insert means nothing is inserted.
   */
  public static func takesOver(
    _ info: any NSDraggingInfo,
    in window: NSWindow?,
    then deliver: @escaping ([URL]) -> Void
  ) -> Bool {
    // No document means no editor; whatever this drag is, it is not the fork's business
    guard let document = window?.windowController?.document as? NSDocument else {
      return false
    }

    let pasteboard = info.draggingPasteboard
    let receivers = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? []

    guard receivers.isEmpty else {
      let host = window?.contentViewController as? (any WorkspaceHost)
      DropSession(document: document, host: host, deliver: deliver).receive(receivers)
      return true
    }

    return takesOver(files: droppedFiles(on: pasteboard), in: window, then: deliver)
  }

  /**
   The same decision, for files that are already in hand.

   Two callers: the drag above, once its pasteboard has been read, and the debug menu item that
   stands in for a drag on a machine where one cannot be synthesized. They share this rather
   than each having their own copy, because a debug path that answers differently from the real
   one is worse than no debug path at all.
   */
  public static func takesOver(
    files fileURLs: [URL],
    in window: NSWindow?,
    then deliver: @escaping ([URL]) -> Void
  ) -> Bool {
    guard let document = window?.windowController?.document as? NSDocument, !fileURLs.isEmpty else {
      return false
    }

    // A note is opened, a folder becomes the sidebar's root, and only what is left over is an
    // attachment. Doing this first is what keeps a dropped `.md` from being copied into
    // `assets/` and linked, which is what it used to do and is nobody's idea of a drop.
    let host = window?.contentViewController as? (any WorkspaceHost)
    let attachments = route(fileURLs, host: host)
    guard attachments.count == fileURLs.count else {
      if !attachments.isEmpty {
        deliver(attachments)
      }

      return true
    }

    // Nothing was opened, so this is an ordinary attachment drop: upstream's own path handles
    // it, unless the document has nowhere to put an asset and nothing to be relative to.
    guard document.fileURL == nil else {
      return false
    }

    DropSession(document: document, host: host, deliver: deliver).saveThenDeliver(fileURLs)
    return true
  }

  /**
   The same decision again, for files that are already in hand *and* came from somewhere
   temporary — which is what a promise drag produces.

   One caller: the debug menu item that stands in for a drag. It exists because the difference
   between a Finder drop and a promise drop is exactly the behaviour this pass had to fix — one
   may fall back to linking the file where it lies, the other may not — and a debug hook that
   can only reproduce the forgiving half would leave the half that broke untestable.
   */
  public static func takesOver(
    received fileURLs: [URL],
    in window: NSWindow?,
    then deliver: @escaping ([URL]) -> Void
  ) -> Bool {
    guard let document = window?.windowController?.document as? NSDocument, !fileURLs.isEmpty else {
      return false
    }

    let host = window?.contentViewController as? (any WorkspaceHost)
    DropSession(document: document, host: host, deliver: deliver).adopt(fileURLs)
    return true
  }

  /**
   Open what should be opened, and hand back what should be attached.

   Three kinds of thing can land on an editor, and only one of them is an attachment:

   - **A folder** becomes the sidebar's root, the same as choosing it in the footer. It is the
     app's central gesture, and the alternative was copying a whole directory tree into
     `assets/`, which nobody wants and which would happen silently.
   - **A file the app can open** — Markdown, text, a `.textbundle` — is a file you want to
     read. The first replaces this window's document, the way clicking a row in the sidebar
     does; any others open in windows of their own, because a single window cannot show three
     files and dropping three is asking for three.
   - **Anything else** is an attachment: copied into `assets/` beside the document and linked.

   **Two modifiers turn all of this off**, so the old behaviour is still reachable. **⇧** is
   upstream's own "inline this file's contents", which must keep working for text files.
   **⌥** is the fork's, and it means "attach it, do not open it" — the only way to write a link
   to another note by dragging it, now that a plain drop opens it instead.
   */
  static func route(_ fileURLs: [URL], host: (any WorkspaceHost)?, roots: BookmarkStore = .shared) -> [URL] {
    guard let host, !NSEvent.modifierFlags.contains(.shift), !NSEvent.modifierFlags.contains(.option) else {
      return fileURLs
    }

    var attachments = [URL]()
    var opened = [URL]()

    for url in fileURLs {
      if FolderDrop.isFolder(url) {
        roots.open(url)
      } else if host.canOpen(url) {
        opened.append(url)
      } else {
        attachments.append(url)
      }
    }

    for (index, url) in opened.enumerated() {
      if index == 0 {
        host.openInPlace(url)
      } else {
        host.openInNewWindow(url)
      }
    }

    return attachments
  }
}

// MARK: - Private

private extension EditorDrops {
  /// The same filter upstream applies, spelled here because the module cannot see it: a
  /// promise drag's placeholder URL has an empty or `/` last path component.
  static func droppedFiles(on pasteboard: NSPasteboard) -> [URL] {
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL]

    return (urls ?? []).filter { !$0.lastPathComponent.isEmpty && $0.lastPathComponent != "/" }
  }
}

/**
 One drag, from the moment the fork takes it over to the moment its files are inserted.

 An object rather than a chain of closures because both halves need something kept alive across
 a callback AppKit owns: `NSFilePromiseReceiver` calls back per file on a queue of its own, and
 `NSDocument.save(withDelegate:didSave:contextInfo:)` is an Objective-C selector callback, which
 needs an `NSObject` to send it to. `active` is what holds the session until it is finished with;
 without it the receiver's callbacks arrive at a deallocated target.
 */
@MainActor
final class DropSession: NSObject {
  init(document: NSDocument, host: (any WorkspaceHost)?, deliver: @escaping ([URL]) -> Void) {
    self.document = document
    self.host = host
    self.deliver = deliver
    super.init()

    Self.active.insert(self)
  }

  /**
   Ask each promise for its files, into a folder of our own.

   **Received into a temporary directory, never straight into `assets/`** — `drops.md` §3.3. The
   sidebar watches directories and coalesces their events over 120 ms, a window tuned for a save
   burst rather than a multi-second SFTP fetch, so a file written in place would appear in the
   tree half-downloaded; and a fetch that failed halfway would leave debris inside someone's
   notes folder. What lands here is copied on by `AssetFolder` once it is whole.

   The temporary copies are deliberately **not** cleaned up afterwards. They live in the app's
   own container, the system reclaims them, and deleting them would break the one case that
   needs them most: a copy into `assets/` that the sandbox refuses, where the link written is a
   relative path to the file exactly where it landed.
   */
  func receive(_ receivers: [NSFilePromiseReceiver]) {
    guard let destination = temporaryDirectory() else {
      return finish(with: [])
    }

    // `fileNames` is the source's own promise of what it will produce; a source that names
    // nothing still delivers one callback, so one is the floor rather than zero
    awaitFiles(expecting: receivers.reduce(0) { $0 + max($1.fileNames.count, 1) }, buckets: receivers.count)

    let queue = OperationQueue()
    for (index, receiver) in receivers.enumerated() {
      receiver.receivePromisedFiles(
        atDestination: destination,
        options: [:],
        operationQueue: queue,
        reader: Self.reader(for: self, at: index)
      )
    }
  }

  /// How many callbacks to expect, and how many sources they will arrive from. Split out of
  /// `receive` so that a test can drive `reader` without an `NSFilePromiseReceiver`, which
  /// cannot be constructed by hand — and it is what marks the session as holding *received*
  /// files, which are the ones that must never be linked where they lie.
  func awaitFiles(expecting count: Int, buckets: Int) {
    isReceived = true
    expected = count
    received = Array(repeating: [], count: max(buckets, 1))
  }

  /**
   The block AppKit calls as each promised file lands.

   **This shape exists because the obvious one crashed the app.** Written inline inside
   `receive`, the closure captured `self` — a `@MainActor` class — so Swift inferred main-actor
   isolation for it and compiled in an executor check. `receivePromisedFiles` then called it on
   the operation queue it had been handed, the check tripped `dispatch_assert_queue`, and the
   process died: `EXC_BREAKPOINT` in `swift_task_isCurrentExecutorWithFlags`, one frame below
   `closure #2 in Session.receive(_:)`, reported from a real Transmit drag.

   **What fixes it is that this closure captures a parameter rather than an isolated `self`**,
   so no isolation is inferred and the hop to the main actor is explicit. `@Sendable` and
   `nonisolated` are what stop that being an accident: with them, a later edit that reaches for
   main-actor state in here is a compile error rather than another crash report.
   */
  nonisolated static func reader(for session: DropSession, at index: Int) -> @Sendable (URL, (any Error)?) -> Void {
    { url, error in
      // `error` is deliberately not carried across the hop: it is not `Sendable`, and all that
      // matters on the other side is whether a file arrived.
      let failed = error != nil
      Task { @MainActor in
        session.didReceive(url, failed: failed, from: index)
      }
    }
  }

  /// Take these files as though a promise had just produced them: they live somewhere
  /// temporary, so they are copied in rather than linked where they lie.
  func adopt(_ fileURLs: [URL]) {
    isReceived = true
    finish(with: fileURLs)
  }

  /// Save the document, then deliver. A cancelled save means the drop did not happen.
  func saveThenDeliver(_ fileURLs: [URL]) {
    pending = fileURLs
    document.save(
      withDelegate: self,
      didSave: #selector(document(_:didSave:contextInfo:)),
      contextInfo: nil
    )
  }

  // MARK: - Private

  private static var active = Set<DropSession>()

  private let document: NSDocument
  private let host: (any WorkspaceHost)?
  private let deliver: ([URL]) -> Void

  private var expected = 0
  private var received = [[URL]]()
  private var pending = [URL]()

  /// A source that produces more files than it promised would otherwise finish the session
  /// twice, inserting the same drop again.
  private var hasFinished = false

  /// Whether these files came from a promise, and therefore live somewhere temporary.
  private var isReceived = false

  func didReceive(_ url: URL, failed: Bool, from index: Int) {
    // A failed promise still calls back, with a URL for a file that was never written
    if !failed, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
      received[index].append(url)
    }

    expected -= 1
    guard expected <= 0 else {
      return
    }

    // Flattened in the order the pasteboard listed the promises, so that dropping three files
    // inserts three links in the order they were dragged rather than the order they arrived
    finish(with: received.flatMap { $0 })
  }

  private func finish(with fileURLs: [URL]) {
    guard !hasFinished else {
      return
    }

    hasFinished = true

    // A promise can produce a note as easily as an image — a `.md` dragged out of another
    // editor, say — so what arrives is routed exactly as a Finder drop would be
    let attachments = EditorDrops.route(fileURLs, host: host)
    guard !attachments.isEmpty else {
      return done()
    }

    // The drop still needs somewhere to be relative to, so an untitled document is saved here
    // as well — after the fetch rather than during it, so that a panel and a download are never
    // waiting on each other.
    guard document.fileURL != nil else {
      return saveThenDeliver(attachments)
    }

    deliverAttachments(attachments)
  }

  /**
   Hand the files on to be linked — copying a *received* one into `assets/` first.

   **A file that came from a promise lives in a temporary folder the system reaps**, so the
   ordinary fallback — "if the copy fails, link the file where it lies" — writes a link that is
   guaranteed to rot, into a path naming this machine's container. Measured on a real Transmit
   drag, which inserted
   `../../…/Containers/…/Data/tmp/TemporaryItems/NSIRD_…/photo.jpg`.

   So the copy is not optional here: it either lands in `assets/` or the drop says so and
   inserts nothing. A file dragged from Finder still falls back, because the original is a real
   file that stays where it is — that path is `AssetFolder.staged`, one step later.
   */
  private func deliverAttachments(_ urls: [URL]) {
    guard isReceived, let directory = document.fileURL?.deletingLastPathComponent() else {
      deliver(urls)
      return done()
    }

    stage(urls, into: directory, mayAskForAccess: true)
  }

  /**
   Copy what can be copied, deliver that, and deal with what could not.

   The failure this is shaped around is the sandbox: a document's *file* is what the user
   granted, not the directory holding it, so a note opened from outside the workspace folder
   answers a copy with *"you don’t have permission to access “assets”"*. macOS's own way out is
   a folder the user picks in a panel, so that is what is offered — once. A second failure after
   a grant is a real file system error, and it gets the plain alert.
   */
  private func stage(_ urls: [URL], into directory: URL, mayAskForAccess: Bool) {
    var staged = [URL]()
    var unstaged = [URL]()
    var failure: String?

    for url in urls {
      do {
        staged.append(try AssetFolder.stage(url, in: directory))
      } catch {
        WorkspaceLog.drops.error("Could not stage a received file into \(directory.path(percentEncoded: false), privacy: .public): \(error.localizedDescription, privacy: .public)")
        unstaged.append(url)
        failure = failure ?? error.localizedDescription
      }
    }

    if !staged.isEmpty {
      deliver(staged)
    }

    guard let failure, !unstaged.isEmpty else {
      return done()
    }

    guard mayAskForAccess, host != nil else {
      report(failure, offeringAccessTo: nil)
      return done()
    }

    report(failure, offeringAccessTo: directory) { [weak self] granted in
      guard let self else {
        return
      }

      if granted {
        stage(unstaged, into: directory, mayAskForAccess: false)
      } else {
        done()
      }
    }
  }

  /**
   Say that the file could not be brought in, rather than inserting a link that will break.

   A sheet on the document's own window, which is where the drop happened — and **only** when
   there is one. A document with no window is a document nobody is looking at, and an app-modal
   alert there would be a dialog with nothing behind it; the log line is already written by
   then, which is what that case actually needs.
   */
  private func report(
    _ message: String,
    offeringAccessTo directory: URL?,
    then resume: ((Bool) -> Void)? = nil
  ) {
    guard let window = document.windowControllers.first?.window else {
      return resume?(false) ?? ()
    }

    let alert = NSAlert()
    alert.messageText = WorkspaceStrings.dropFailed
    alert.informativeText = message

    guard let directory, let host, let resume else {
      alert.beginSheetModal(for: window)
      return
    }

    alert.addButton(withTitle: WorkspaceStrings.grantAccess)
    alert.addButton(withTitle: WorkspaceStrings.cancel)

    alert.beginSheetModal(for: window) { response in
      guard response == .alertFirstButtonReturn else {
        return resume(false)
      }

      Task { @MainActor in
        resume(await host.grantAccess(to: directory))
      }
    }
  }

  private func done() {
    Self.active.remove(self)
  }

  @objc private func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
    // Cancelled, or the save failed: the drop is off, and nothing has been written into the
    // document. The received files stay in the temporary folder for the system to reclaim.
    guard didSave, document.fileURL != nil else {
      return done()
    }

    deliverAttachments(pending)
  }

  private func temporaryDirectory() -> URL? {
    try? FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: document.fileURL ?? URL(filePath: NSTemporaryDirectory()),
      create: true
    )
  }
}
