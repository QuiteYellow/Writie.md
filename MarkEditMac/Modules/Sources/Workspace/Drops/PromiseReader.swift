//
//  PromiseReader.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/// Something waiting on promised files: the editor's `DropSession`, and the sidebar's
/// `FolderImportSession`. `index` is which promise the file came from, so a drag of three
/// files can be reassembled in the order they were dragged rather than the order they landed.
@MainActor
protocol PromiseReceiving: AnyObject, Sendable {
  func didReceive(_ url: URL, failed: Bool, from index: Int)
}

/**
 The block AppKit calls as each promised file lands.

 **This shape exists because the obvious one crashed the app.** Written inline inside the
 method that calls `receivePromisedFiles`, the closure captured `self` — a `@MainActor` class —
 so Swift inferred main-actor isolation for it and compiled in an executor check.
 `receivePromisedFiles` then called it on the operation queue it had been handed, the check
 tripped `dispatch_assert_queue`, and the process died: `EXC_BREAKPOINT` in
 `swift_task_isCurrentExecutorWithFlags`, one frame below `closure #2 in Session.receive(_:)`,
 reported from a real Transmit drag.

 **What fixes it is that this closure captures a parameter rather than an isolated `self`**, so
 no isolation is inferred and the hop to the main actor is explicit. `@Sendable` and
 `nonisolated` are what stop that being an accident: with them, a later edit that reaches for
 main-actor state in here is a compile error rather than another crash report.

 One copy, shared by both sessions. Two would be two chances to reintroduce the crash, and the
 one that was reintroduced would be the one nobody had dragged from Transmit that week.
 */
enum PromiseReader {
  nonisolated static func reader(
    for target: some PromiseReceiving,
    at index: Int
  ) -> @Sendable (URL, (any Error)?) -> Void {
    { url, error in
      // `error` is deliberately not carried across the hop: it is not `Sendable`, and all that
      // matters on the other side is whether a file arrived.
      let failed = error != nil
      Task { @MainActor in
        target.didReceive(url, failed: failed, from: index)
      }
    }
  }
}
