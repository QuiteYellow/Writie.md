//
//  LaunchFolder.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 Which folder the sidebar opens with, on a launch that restores nothing.

 Two answers, because two people want different ones from the same app. **Last Used** is the
 project editor: whatever folder you were in is the folder you come back to. **Custom** is the
 notes app: one folder, always, whatever you wandered into last time.

 `BookmarkStore.shared` already holds the folder that is open *now*, and remembers it as the
 last used one. This adds the second slot — the pin — and decides which of the two a launch
 reads. A pin cannot be a stored path, for the same reason the last used folder is not one: a
 sandboxed app gets a folder back only through a security-scoped bookmark, so the pin is a
 second `BookmarkStore` rather than a string.

 **The pin is a pin.** Choosing a different folder from the sidebar's footer while in Custom
 mode changes the folder for that session and leaves the pin alone, so the next launch comes
 back to the pinned one. The last used folder is still recorded underneath, which is what
 makes switching back to Last Used mean something. Picking a pin in Settings is the exception
 that opens a folder immediately: it is a folder-choosing gesture with its own panel, and one
 that visibly did nothing would read as broken.

 **Only the sidebar's own picker writes the last used folder.** Neither opening the pin at
 launch nor choosing it in Settings does, which keeps one rule where there could have been
 two: Last Used means the folder you last browsed to, so switching the mode back lands you
 where you were rather than on the pin you had been using instead.

 **Nothing here can hold up a launch.** `restore()` spends at most one bounded wait — never
 two, so a slow pin is not followed by a slow fallback — and every failure has an answer that
 leaves the app running: see the cases in `restore()`.
 */
@MainActor
@Observable
public final class LaunchFolder {
  public enum Mode: String, Sendable {
    /// Whatever folder was open when the app last quit.
    case lastUsed
    /// One folder, pinned in Settings, whatever was open last.
    case custom
  }

  /// The one the app uses. Tests make their own against a scratch `UserDefaults`.
  public static let shared = LaunchFolder(defaults: .standard, prefix: Constants.prefix)

  /// Which folder the next launch opens with. Changing it alone changes nothing about this
  /// session — it is a launch rule, and the sidebar's footer is what changes the folder now.
  public var mode: Mode {
    didSet {
      guard mode != oldValue else {
        return
      }

      defaults.set(mode.rawValue, forKey: key(.mode))
    }
  }

  /// The pinned folder, opened. Nil when nothing is pinned, and also when the pin exists but
  /// cannot be resolved — a volume that is not mounted, a folder that has been deleted.
  public var pinnedFolder: URL? {
    pin.url
  }

  /// What to call the pinned folder in the interface, kept even while it cannot be opened, so
  /// that a pin on a disconnected volume reads as "Archive, unavailable" rather than as
  /// nothing at all. Display only: a name cannot open a folder, the bookmark does that.
  public private(set) var pinnedFolderName: String?

  /// Whether a folder is pinned at all, resolvable or not.
  public var hasPinnedFolder: Bool {
    pin.hasSavedFolder
  }

  /**
   Whether this app is being used with a folder at all.

   True as soon as any folder has ever been chosen, **whether or not one can be opened right
   now**, which is the distinction that matters: a pin on a volume that has gone away, or a
   folder that resolved too slowly for the launch deadline, should still give the folder-rooted
   answer — an empty sidebar offering Choose Folder… — rather than reverting to the file panel
   of an app the user stopped using two versions ago.

   It reads both stores because Custom mode writes only the pin, so a launch that has only ever
   been pinned has no last-used folder to find.
   */
  public var isFolderRooted: Bool {
    current.url != nil || current.hasSavedFolder || pin.hasSavedFolder
  }

  /// Set when a folder could not be pinned, for the interface to show and then clear. The one
  /// measured cause is a folder the sandbox refuses to bookmark — a symlink to one, at M5.
  public var failure: String?

  public init(defaults: UserDefaults, prefix: String, current: BookmarkStore = .shared) {
    self.defaults = defaults
    self.prefix = prefix
    self.current = current
    self.pin = BookmarkStore(defaults: defaults, key: "\(prefix).pin-bookmark")
    self.mode = Mode(rawValue: defaults.string(forKey: "\(prefix).mode") ?? "") ?? .lastUsed
    self.pinnedFolderName = defaults.string(forKey: "\(prefix).pin-name")

    observePin()
  }

  /**
   Open whichever folder this launch should start with.

   Called before `NSApplicationMain`, which is what makes the failure cases the interesting
   part of it. Every one of them leaves the app launching:

   - **Nothing pinned, in Custom mode.** The last used folder is a better answer than an empty
     sidebar, and the Settings row is where the unset pin is visible.
   - **A pin that resolves slowly.** `BookmarkStore.restore` gives up after its deadline and
     keeps resolving in the background, so the sidebar fills in late rather than not at all.
   - **A pin that does not resolve.** The sidebar shows its empty state and the pin stays
     stored for the next launch. It is deliberately *not* replaced by the last used folder:
     silently opening a different folder than the one somebody pinned is worse than opening
     none, and it would also be a second wait.
   */
  public func restore() {
    switch mode {
    case .lastUsed:
      current.restore()
    case .custom:
      guard pin.hasSavedFolder else {
        current.restore()
        return
      }

      if let folder = pin.restore() {
        current.useWithoutSaving(folder)
      }
    }
  }

  /**
   Whether a launch with nothing to restore should open an untitled document rather than a
   file panel.

   Upstream's answer is its `newWindowBehavior` preference, which defaults to putting an
   `NSOpenPanel` in front of a cold launch. That is right for a document-centric app and wrong
   for this one on two counts: the panel cannot choose a *folder*, which is the gesture this
   fork is built around, and the sidebar it would be covering is the file picker already.

   So when the app has a folder this is true, and the window opens on a fresh untitled document
   with the tree beside it. The last file is deliberately **not** reopened —
   `NSQuitAlwaysKeepsWindows` already restores the documents that were open, which is the
   mechanism for "carry on where I was", and reaching into the recent-documents list on top of
   it would second-guess a setting the user owns.

   With no folder it is true as well, which is the first-run case and the reason any of this was
   looked at: a fresh install has no folder, so deferring to the preference would put the file
   panel in front of the one gesture that makes the fork work. An untitled document with an
   empty sidebar beside it is the answer, because that sidebar is showing Choose Folder….

   **The exception is a preference the user actually set**, which is what
   `hasExplicitPreference` carries. Upstream's default is "show the panel", so *wants a panel*
   and *has never opened Settings* are the same stored value — and overriding the second
   silently would override the first too. An explicit choice wins. That is the only reading
   under which a preference the fork did not remove still means what it says.

   **It adds no preference of its own.** Which folder a launch opens is this type's business;
   whether a *document* is opened is not worth a second control when the answer is always "a
   blank one".
   */
  public func opensUntitledFile(hasExplicitPreference: Bool) -> Bool {
    isFolderRooted || !hasExplicitPreference
  }

  /// Pick the folder to pin. Cancelling the panel leaves the current pin in place.
  public func choosePinnedFolder() {
    Task { [weak self] in
      guard let self, let folder = await FolderPicker.chooseFolder(startingAt: pin.url ?? current.url) else {
        return
      }

      pinFolder(folder)
    }
  }

  /**
   Pin `folder`, and open it now.

   Split from the panel so that the pin can be set by something other than a click: the tests,
   and the debug override that stands in for a panel nobody can click from a scripted session.
   */
  public func pinFolder(_ folder: URL) {
    do {
      try pin.save(folder)
      pinnedFolderName = folder.lastPathComponent
      defaults.set(pinnedFolderName, forKey: key(.name))
      failure = nil
      mode = .custom

      // Opened here rather than left to `observePin`, which is a `Task` and therefore a
      // moment later: choosing a folder is a click, and a click whose effect arrives after
      // the next line of code has read the state is a race waiting to be relied on. The
      // observer stays for the case it is actually for — a pin that resolves late.
      //
      // `pin.url` rather than `folder`: the bookmark's own spelling of the folder is the one
      // every later launch will use, and matching it now means the sidebar's selection and
      // its root comparisons do not change under it on the next launch.
      current.useWithoutSaving(pin.url ?? folder)
    } catch {
      // A folder the sandbox will not bookmark cannot be pinned: it would come back as a pin
      // that quietly fails every launch. So the pin is left as it was and the folder is
      // opened for this session only — the same answer the sidebar's own picker gives — and
      // the row says why, because a control that appears to do nothing reads as broken.
      failure = error.localizedDescription
      current.useWithoutSaving(folder)
    }
  }

  /// Forget the pin. The mode is left alone — a Custom launch with nothing pinned falls back
  /// to the last used folder, which is what `restore()` does and what the row says it does.
  public func clearPinnedFolder() {
    pin.clear()
    pinnedFolderName = nil
    failure = nil
    defaults.removeObject(forKey: key(.name))
  }

  // MARK: - Private

  private enum Constants {
    static let prefix = "workspace.launch-folder"
  }

  private enum Key: String {
    case mode
    case name = "pin-name"
  }

  private let defaults: UserDefaults
  private let prefix: String
  private let current: BookmarkStore
  private let pin: BookmarkStore

  private func key(_ key: Key) -> String {
    "\(prefix).\(key.rawValue)"
  }

  /**
   Follow the pin's own folder into the live one.

   Two moments need this and neither is the timely case, which `restore()` handles directly.
   A pin that resolved *after* the launch deadline arrives here, so a slow volume costs a
   sidebar that fills in a second late. And a pin chosen in Settings arrives here too, which
   is what opens it immediately instead of next launch.

   `withObservationTracking` fires once and has to be re-armed, and it fires before the new
   value lands — so the reaction hops to the main actor, reads what was actually set, and
   re-arms. Missing the re-arm is the silent failure: the first change works and every one
   after it is ignored. Same shape, and same reason, as `WorkspaceModel.observeRoot`.
   */
  private func observePin() {
    withObservationTracking {
      _ = pin.url
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.observePin()
        self?.pinDidChange()
      }
    }
  }

  private func pinDidChange() {
    guard mode == .custom, let folder = pin.url, folder != current.url else {
      return
    }

    current.useWithoutSaving(folder)
  }
}
