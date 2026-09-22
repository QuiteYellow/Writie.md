//
//  FolderScanner.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 Turns a folder on disk into a tree of `FileNode`.

 `scan` is `nonisolated` and `async`, so enumerating a folder never runs on the main actor.
 It walks the whole tree in one pass, which is what "static tree" buys: no expansion
 bookkeeping, and the answer is a value the model can swap in wholesale. M6 makes it lazy,
 one directory per expanded node, because that is also the unit `DispatchSource` watches.

 Until then `Constants.nodeLimit` is the stop that keeps someone who points the sidebar at
 their home directory from waiting on a full-disk walk. It is a safety limit, not a design:
 a tree that hits it is silently truncated, which is acceptable only because the root is
 hardcoded at this milestone.
 */
public enum FolderScanner {
  public enum Failure: Error {
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

  public static func scan(root: URL, options: Options) async throws(Failure) -> [FileNode] {
    var budget = Constants.nodeLimit
    return try contents(of: root, options: options, budget: &budget)
  }
}

// MARK: - Private

private extension FolderScanner {
  enum Constants {
    static let nodeLimit = 4000
  }

  static func contents(of directory: URL, options: Options, budget: inout Int) throws(Failure) -> [FileNode] {
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
    for url in urls where budget > 0 {
      let values = try? url.resourceValues(forKeys: Set(keys))

      // A package (.textbundle, .app) is a directory the user means as one thing
      let isDirectory = values?.isDirectory == true && values?.isPackage != true
      guard isDirectory || isListed(url, options: options) else {
        continue
      }

      budget -= 1

      // A subfolder we can't read lists as empty rather than failing the whole scan; only
      // the root being unreadable is worth telling the user about
      let children = isDirectory ? ((try? contents(of: url, options: options, budget: &budget)) ?? []) : nil
      nodes.append(FileNode(url: url, children: children))
    }

    return sorted(nodes)
  }

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
