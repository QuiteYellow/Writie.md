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
    /// Extensions a file must have to be listed. Files with no extension are always listed.
    let fileExtensions: Set<String>
    let showsHiddenFiles: Bool

    public init(fileExtensions: Set<String>, showsHiddenFiles: Bool) {
      self.fileExtensions = fileExtensions
      self.showsHiddenFiles = showsHiddenFiles
    }
  }

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
      guard isDirectory || isListed(url, options: options) else {
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
    let ext = url.pathExtension
    // Notes folders are full of extension-less files, and the app opens them as plain text
    return ext.isEmpty || options.fileExtensions.contains(ext.lowercased())
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
