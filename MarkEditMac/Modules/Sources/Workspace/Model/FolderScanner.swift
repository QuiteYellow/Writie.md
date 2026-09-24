//
//  FolderScanner.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 Lists one directory.

 `contents(of:options:)` is `nonisolated` and `async`, so enumerating a folder never runs on
 the main actor. It reads a single directory and does not descend: the sidebar asks for a
 directory when its row is expanded, which is also the unit `DirectoryObserver` watches, so
 the two line up exactly — one `open`, one listing, one observer, torn down together when the
 row collapses.

 M4's eager whole-tree walk needed a 4000-node stop to keep someone who pointed the sidebar at
 their home directory from waiting on a full-disk walk, and a tree that hit it was silently
 truncated. Reading one directory at a time removes the need for the limit rather than raising
 it, so that truncation is gone.
 */
public enum FolderScanner {
  public enum Failure: Error, Equatable {
    case unreadable(URL)
  }

  public struct Options: Sendable {
    /// Extensions a file must have to be listed, when `showsAllFiles` is off. Files with no
    /// extension are always listed.
    let fileExtensions: Set<String>

    /// List every file, whatever its extension. `fileExtensions` is then unused.
    let showsAllFiles: Bool
    let showsHiddenFiles: Bool

    /// Leave out directories named `assets`, whatever their case — the convention this app
    /// drops attachments into, which is clutter in a list of notes.
    let hidesAssetsFolders: Bool

    public init(
      fileExtensions: Set<String>,
      showsAllFiles: Bool,
      showsHiddenFiles: Bool,
      hidesAssetsFolders: Bool
    ) {
      self.fileExtensions = fileExtensions
      self.showsAllFiles = showsAllFiles
      self.showsHiddenFiles = showsHiddenFiles
      self.hidesAssetsFolders = hidesAssetsFolders
    }
  }

  /// The one name the assets convention is spelled with, compared lowercased. Kept here so
  /// that hiding such a folder and (group D) creating one cannot drift apart.
  public static let assetsFolderName = "assets"

  public static func contents(of directory: URL, options: Options) async throws(Failure) -> [FileNode] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
    let mask: FileManager.DirectoryEnumerationOptions = options.showsHiddenFiles ? [] : [.skipsHiddenFiles]

    let urls: [URL]
    do {
      urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: keys,
        options: mask
      )
    } catch {
      throw Failure.unreadable(directory)
    }

    var nodes = [FileNode]()
    for url in urls {
      let values = try? url.resourceValues(forKeys: Set(keys))

      // A package (.textbundle, .app) is a directory the user means as one thing
      let isDirectory = values?.isDirectory == true && values?.isPackage != true
      let listed = isDirectory ? isListed(directory: url, options: options) : isListed(url, options: options)
      guard listed else {
        continue
      }

      nodes.append(FileNode(url: url, isDirectory: isDirectory))
    }

    return sorted(nodes)
  }
}

// MARK: - Private

private extension FolderScanner {
  static func isListed(_ url: URL, options: Options) -> Bool {
    guard !options.showsAllFiles else {
      return true
    }

    let ext = url.pathExtension
    // Notes folders are full of extension-less files, and the app opens them as plain text
    return ext.isEmpty || options.fileExtensions.contains(ext.lowercased())
  }

  /// A directory is listed whatever it holds — the tree is how you find a file, not a filter
  /// on one — with the single exception the assets convention earns.
  static func isListed(directory url: URL, options: Options) -> Bool {
    guard options.hidesAssetsFolders else {
      return true
    }

    return url.lastPathComponent.lowercased() != Self.assetsFolderName
  }

  /// Folders first, then by name the way Finder orders it — "10" after "9", not before it.
  static func sorted(_ nodes: [FileNode]) -> [FileNode] {
    nodes.sorted {
      if $0.isDirectory != $1.isDirectory {
        return $0.isDirectory
      }

      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}
