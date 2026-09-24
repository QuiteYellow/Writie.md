//
//  BookmarkStore.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 The folder the sidebar is rooted at, remembered across launches.

 A sandboxed app loses a folder the moment it quits, and a security-scoped bookmark is what
 buys it back. The scope that bookmark opens has to stay open for as long as the app might
 read through it — not just for the duration of the scan — because every file the sidebar
 opens is reached through it. So it is started once, on restore, and stopped only when the
 folder stops being the root.

 This is the mechanism upstream's Grant Folder Access menu item already uses
 (`AppDelegate+FileSystem.swift`), and the app restores this from the same place, at the same
 moment: before `NSApplicationMain`, which is early enough to cover documents restored into
 windows at launch.

 One folder, app-wide. `shared` is what every window reads, so a folder chosen in one window
 is the folder the next window's sidebar shows, and the scope is held once rather than once
 per window.
 */
@MainActor
@Observable
public final class BookmarkStore {
  public enum Failure: Error, Equatable {
    /// The folder could not be turned into bookmark data, so it cannot outlive this launch.
    case notBookmarkable(URL)
  }

  /// The one the app uses. Tests make their own against a scratch `UserDefaults`.
  public static let shared = BookmarkStore(defaults: .standard, key: Constants.defaultsKey)

  /// The folder currently open, however it was chosen. Nil means the sidebar has no root.
  public private(set) var url: URL?

  /// Whether a folder is remembered at all, whether or not it can be resolved right now.
  /// The launch rule asks this to tell "no folder was ever chosen" from "the folder is gone",
  /// which are the same empty sidebar but not the same answer.
  public var hasSavedFolder: Bool {
    defaults.data(forKey: key) != nil
  }

  public init(defaults: UserDefaults, key: String) {
    self.defaults = defaults
    self.key = key
  }

  /// Remember `url` as the folder, and open it.
  public func save(_ url: URL) throws(Failure) {
    guard let data = try? url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) else {
      throw Failure.notBookmarkable(url)
    }

    defaults.set(data, forKey: key)

    // Open the bookmark rather than the URL that made it, so that this launch and every
    // later one name the folder identically — by construction, not by canonicalising and
    // hoping. They do not otherwise agree: a resolved directory URL carries a trailing
    // slash, and `resolvingSymlinksInPath` normalises `/private/var` *to* `/var` while a
    // bookmark resolves the other way. Measured, after the round-trip test caught both.
    //
    // Resolved on the calling thread rather than through `restore`'s deadline: this is a
    // folder the user picked a moment ago through a panel that had just enumerated it, and
    // a save that gave up early would drop the key for a folder that is perfectly good.
    guard let resolution = Self.resolve(data) else {
      defaults.removeObject(forKey: key)
      throw Failure.notBookmarkable(url)
    }

    adopt(resolution)
  }

  /// How long a launch will wait for a bookmark to resolve before carrying on without it.
  /// A local folder resolves in well under a millisecond, so this is only ever spent on a
  /// volume that is in trouble — long enough to ride out a slow mount, short enough that
  /// nobody reads it as a hang. A test passes its own, because waiting is what it asserts on.
  public static let resolutionDeadline = Duration.milliseconds(750)

  /**
   Open the remembered folder, if there is one, and hold its scope.

   Idempotent: a second call while a folder is already open is a no-op, so it can be called
   from launch and again from a window without opening the scope twice.

   **Resolving a bookmark can block, so this one is bounded.** It runs before
   `NSApplicationMain`, and `URL(resolvingBookmarkData:)` goes to the file system: a folder on
   a network volume that has gone away answers slowly, or not at all, and no folder should be
   able to hold the app at a blank screen. So the resolve happens off the main thread and this
   waits `deadline` for it.

   Past the deadline it returns nil and the app carries on with no folder — but the resolve is
   **not cancelled**, and whatever it eventually produces is adopted then. So a slow volume
   costs a sidebar that fills in late rather than a folder that is lost, and a dead one costs
   nothing at all. `.withoutUI` and `.withoutMounting` are already on the resolve, so this can
   never become a mount prompt either.
   */
  @discardableResult
  public func restore(waitingUpTo deadline: Duration = BookmarkStore.resolutionDeadline) -> URL? {
    guard url == nil, let data = defaults.data(forKey: key) else {
      return url
    }

    let handoff = Handoff()
    resolveOffMain(data, into: handoff)

    guard case .resolved(let resolution) = handoff.wait(deadline), let resolution else {
      return nil
    }

    adopt(resolution)
    return url
  }

  /// Open `url` for this launch without remembering it. The debug root override uses this.
  public func useWithoutSaving(_ url: URL) {
    adopt(url, isScoped: false)
  }

  /// Forget the folder and close it.
  public func clear() {
    defaults.removeObject(forKey: key)
    adopt(nil, isScoped: false)
  }

  /**
   Open `folder`, and remember it if the sandbox lets us.

   The fallback is not a detail: a folder that cannot be bookmarked — a symlink to one, at M5 —
   is still a folder somebody just chose, and opening it for this session is a better answer
   than behaving as though the gesture never happened. Every route to a new root goes through
   here: the footer's panel, a folder dropped on the sidebar, a folder dropped on the editor.
   */
  func open(_ folder: URL) {
    do {
      try save(folder)
    } catch {
      useWithoutSaving(folder)
    }
  }

  // MARK: - Private

  private enum Constants {
    /// Shaped like upstream's `general.granted-folder-bookmark`, in the fork's own namespace.
    static let defaultsKey = "workspace.root-bookmark"
  }

  private let defaults: UserDefaults
  private let key: String

  /// Whether the scope on `url` is one this store opened, and therefore one it has to close.
  /// Every folder that came from a bookmark has one; the debug override does not.
  private var isScoped = false

  /**
   Resolve `data`, and hold the security scope it opens.

   `nonisolated` because the point is that it runs anywhere *but* the main actor — every call
   it makes can block on a file system, including `startAccessingSecurityScopedResource` and
   the rewrite of stale data, so all three are on this side of the handoff. A scope is held by
   the process rather than by a thread, so opening it here and adopting it on the main actor
   is the same scope either way.

   Returning nil leaves the stored data alone. A folder on a volume that is not mounted yet
   resolves on a later launch, and discarding the bookmark here would lose it for good.
   */
  nonisolated private static func resolve(_ data: Data) -> ResolvedBookmark? {
    var isStale = false
    guard let folder = try? URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      return nil
    }

    let isScoped = folder.startAccessingSecurityScopedResource()

    // Stale means it resolved this time and might not next time. Rewriting it now, while the
    // scope is held, is what carries the folder through a rename or a move.
    let refreshed = isStale ? try? folder.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) : nil

    return ResolvedBookmark(url: folder, isScoped: isScoped, refreshed: refreshed)
  }

  /// Resolve away from the main thread, so that a folder in trouble cannot stall a launch.
  /// Whichever side ends up holding the result adopts it — the waiter while it is still
  /// waiting, this side once the deadline has passed.
  private func resolveOffMain(_ data: Data, into handoff: Handoff) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let resolution = Self.resolve(data)
      guard handoff.deliver(resolution) == .tooLate else {
        return
      }

      Task { @MainActor in
        guard let self else {
          resolution?.releaseScope()
          return
        }

        self.adoptLate(resolution)
      }
    }
  }

  /// The waiter gave up on this one, so adopting it falls to the resolver — unless a folder
  /// was chosen in the meantime, which wins, and leaves this scope to give back.
  private func adoptLate(_ resolution: ResolvedBookmark?) {
    guard let resolution else {
      return
    }

    guard url == nil else {
      return resolution.releaseScope()
    }

    adopt(resolution)
  }

  private func adopt(_ resolution: ResolvedBookmark) {
    adopt(resolution.url, isScoped: resolution.isScoped)

    if let refreshed = resolution.refreshed {
      defaults.set(refreshed, forKey: key)
    }
  }

  private func adopt(_ next: URL?, isScoped: Bool) {
    if self.isScoped, let url {
      url.stopAccessingSecurityScopedResource()
    }

    url = next
    self.isScoped = isScoped
  }
}

// MARK: - Resolving

/// A bookmark that resolved: the folder it named, whether its security scope is being held,
/// and fresher bookmark data when the stored copy had gone stale.
struct ResolvedBookmark: Sendable {
  let url: URL
  let isScoped: Bool
  let refreshed: Data?

  /// Give the scope back. For a resolution that arrived too late to be anyone's answer —
  /// holding a scope nobody reads through is a leak for the life of the process.
  func releaseScope() {
    if isScoped {
      url.stopAccessingSecurityScopedResource()
    }
  }
}

/**
 The one-shot handoff between a bookmark resolving off the main thread and a main-thread
 caller that will only wait so long for it.

 Its real job is the second one: saying *which side owns the result*. Without that, a
 resolution landing a moment after the deadline is either adopted twice or leaks the security
 scope it opened, and which of the two happens depends on timing — the shape of bug that shows
 up once a month on someone else's machine.
 */
private final class Handoff: @unchecked Sendable {
  enum Delivery {
    /// The waiter has it, and adopts it.
    case toWaiter
    /// The waiter has gone; the resolver adopts it, late.
    case tooLate
  }

  enum Outcome {
    case resolved(ResolvedBookmark?)
    /// The deadline passed, and doubles as "nothing has been delivered yet". Either way the
    /// result, if it ever arrives, belongs to the resolver.
    case tooSlow
  }

  func deliver(_ resolution: ResolvedBookmark?) -> Delivery {
    lock.lock()

    guard !hasGivenUp else {
      lock.unlock()
      return .tooLate
    }

    outcome = .resolved(resolution)
    lock.unlock()
    semaphore.signal()

    return .toWaiter
  }

  func wait(_ deadline: Duration) -> Outcome {
    let seconds = Double(deadline.components.seconds)
      + Double(deadline.components.attoseconds) / 1e18

    // Waited on before the lock is taken, never while holding it: `deliver` needs the same
    // lock to hand the result over, so waiting inside it would deadlock every launch.
    let signalled = semaphore.wait(timeout: .now() + seconds) == .success

    lock.lock()
    defer { lock.unlock() }

    if signalled {
      return outcome
    }

    // It can still have landed between the timeout firing and this lock being taken, and
    // taking it then would be dropping a folder that had actually resolved.
    guard case .tooSlow = outcome else {
      return outcome
    }

    hasGivenUp = true
    return .tooSlow
  }

  // MARK: - Private

  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)

  private var outcome = Outcome.tooSlow
  private var hasGivenUp = false
}
