//
//  SidebarFilter.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 What the sidebar lists, as three preferences of its own.

 **Why it exists at all.** The sidebar used to take its hidden-file rule from
 `AppPreferences.General.showHiddenFiles`, which is upstream's *save and open panel accessory*
 preference (`EditorSaveOptionsView.swift`). Ticking a checkbox in a save panel then silently
 re-filtered every file tree in the app, which is not a thing anyone asked for and is not
 discoverable from either end. The sidebar's filtering is the sidebar's business, so it owns
 its own switches and stops reading that one.

 **Where the defaults come from.** The old Writie app shipped two of these —
 `filterToMarkdownFiles` and `hideAssetsFolders`, both defaulting to on — and they are the
 user's own prior answers, so they are kept: a folder of notes lists as notes, and the folder
 attachments live in stays out of the way. `showsAllFiles` is that first one inverted, because
 a preference reads better as the thing it turns on than as the thing it stops doing.

 `showsHiddenFiles` is the fork's, and it is here rather than absent because the capability
 already existed — it was simply wired to the wrong switch. Hidden files are a separate axis
 from file *types*, as they are in Finder, which is why this is three toggles and not two.

 One store, app-wide, as `SidebarWidth` and `BookmarkStore` are: a filter is a statement about
 how you want to see your files, not about one window. Every open window follows a change,
 which is `WorkspaceModel.observeFilter()`'s job. Tests make their own against a scratch
 `UserDefaults`.
 */
@MainActor
@Observable
public final class SidebarFilter {
  /// The one the app uses.
  public static let shared = SidebarFilter(defaults: .standard, prefix: Constants.prefix)

  /// List every file, whatever its extension, rather than the types the app declares as its
  /// own. Off by default: a notes folder full of PDFs and images reads as a mess.
  public var showsAllFiles: Bool {
    didSet { write(showsAllFiles, oldValue, to: .showsAllFiles) }
  }

  /// List dotfiles. Off by default, as Finder has it.
  public var showsHiddenFiles: Bool {
    didSet { write(showsHiddenFiles, oldValue, to: .showsHiddenFiles) }
  }

  /// Leave out folders named `assets`. **On** by default, the way the old app had it: that
  /// folder is where attachments go, and a list of notes is easier to read without it.
  public var hidesAssetsFolders: Bool {
    didSet { write(hidesAssetsFolders, oldValue, to: .hidesAssetsFolders) }
  }

  public init(defaults: UserDefaults, prefix: String) {
    self.defaults = defaults
    self.prefix = prefix

    // `object(forKey:)` rather than `bool(forKey:)`, so that "never set" is distinguishable
    // from "set to false" — which is the whole difference for a preference defaulting to on
    self.showsAllFiles = defaults.object(forKey: "\(prefix).\(Key.showsAllFiles.rawValue)") as? Bool ?? false
    self.showsHiddenFiles = defaults.object(forKey: "\(prefix).\(Key.showsHiddenFiles.rawValue)") as? Bool ?? false
    self.hidesAssetsFolders = defaults.object(forKey: "\(prefix).\(Key.hidesAssetsFolders.rawValue)") as? Bool ?? true
  }

  /// The scan these preferences describe, for the file types the app declares as its own.
  /// Built fresh at every scan rather than stored, which is what lets a preference change
  /// reach a window that is already open.
  public func options(fileExtensions: Set<String>) -> FolderScanner.Options {
    FolderScanner.Options(
      fileExtensions: fileExtensions,
      showsAllFiles: showsAllFiles,
      showsHiddenFiles: showsHiddenFiles,
      hidesAssetsFolders: hidesAssetsFolders
    )
  }

  // MARK: - Private

  private enum Constants {
    static let prefix = "workspace.sidebar-filter"
  }

  private enum Key: String {
    case showsAllFiles = "shows-all-files"
    case showsHiddenFiles = "shows-hidden-files"
    case hidesAssetsFolders = "hides-assets-folders"
  }

  private let defaults: UserDefaults
  private let prefix: String

  private func write(_ value: Bool, _ oldValue: Bool, to key: Key) {
    guard value != oldValue else {
      return
    }

    defaults.set(value, forKey: "\(prefix).\(key.rawValue)")
  }
}
