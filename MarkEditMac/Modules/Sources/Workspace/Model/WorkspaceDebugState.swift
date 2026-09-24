//
//  WorkspaceDebugState.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 The UI suite's undo: put back the preferences a test launch overwrote.

 **Why this exists, and the damage that produced it.** `WorkspaceUITests` drives the app
 *installed on this machine*, which shares one sandboxed `UserDefaults` with every real launch
 — so a test that pins a folder, remembers one, or ticks a filter is writing the user's own
 preferences. The undo used to be `clearPinnedFolder()` + `BookmarkStore.shared.clear()`, which
 is not an undo at all: it wipes whatever was there rather than restoring it. On 2026-09-24 a
 test run did exactly that to a real folder someone was working in, and the symptom was the app
 opening a file panel on every launch — the fork's launch rule reads "no folder is remembered",
 which is true, and answers with upstream's behaviour, which is a panel.

 The lost value was a **security-scoped bookmark**, and nothing can recreate one but the user
 choosing that folder again. So the fix is to stop destroying it.

 **What it captures: every `workspace.` key.** The fork owns that namespace, so a snapshot of
 the prefix covers the root bookmark, the launch folder and its pin, the sidebar's width and
 its filters — and covers whatever is added later without anyone remembering to come back here.
 Duplicating the key names would have been the version that silently stops covering things.

 The snapshot is taken once per pristine state: a second test launch finds the marker and
 leaves the first snapshot alone, so what comes back is what existed before the *suite* ran,
 not what the previous test left behind.

 **A restored launch is not a usable launch.** `BookmarkStore.shared` and `LaunchFolder.shared`
 have already read their values by the time this runs, so the process doing the restoring keeps
 the state it started with. That is fine for what it is for — the reset launch quits
 immediately — but it is why nothing here tries to re-open the restored folder.
 */
public enum WorkspaceDebugState {
  /// Take a snapshot, unless one is already waiting to be put back.
  public static func captureIfNeeded(defaults: UserDefaults = .standard) {
    guard defaults.dictionary(forKey: Constants.backupKey) == nil else {
      return
    }

    defaults.set(snapshot(of: defaults), forKey: Constants.backupKey)
  }

  /// Put the snapshot back, exactly — including keys that were absent, which are removed
  /// again. Does nothing when no snapshot was taken, which is the case on every real launch.
  public static func restore(defaults: UserDefaults = .standard) {
    guard let backup = defaults.dictionary(forKey: Constants.backupKey) else {
      return
    }

    for key in snapshot(of: defaults).keys where backup[key] == nil {
      defaults.removeObject(forKey: key)
    }

    for (key, value) in backup {
      defaults.set(value, forKey: key)
    }

    defaults.removeObject(forKey: Constants.backupKey)
  }

  /**
   Treat whatever is stored now as the state to go back to.

   One caller, and it is a test: there is no way to write a security-scoped bookmark without a
   panel or one of these overrides, so a test that wants to prove the undo *restores* has no
   other way to establish a "this was here before the suite" precondition. Dropping the
   snapshot is what makes the current state pristine.
   */
  public static func adopt(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: Constants.backupKey)
  }

  // MARK: - Private

  private enum Constants {
    /// The fork's namespace. Everything it writes starts with this.
    static let prefix = "workspace."

    /// Deliberately outside the prefix, so that a snapshot can never contain itself.
    static let backupKey = "writie.debug-state-backup"
  }

  private static func snapshot(of defaults: UserDefaults) -> [String: Any] {
    defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(Constants.prefix) }
  }
}
