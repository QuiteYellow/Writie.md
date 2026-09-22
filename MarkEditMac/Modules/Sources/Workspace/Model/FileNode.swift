//
//  FileNode.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 One entry in the sidebar's tree.

 A value type keyed by its `URL`, so a scan performed off the main actor crosses back to the
 model without ceremony — in Swift 6 language mode the compiler checks that, rather than
 leaving it to review.
 */
public struct FileNode: Identifiable, Hashable, Sendable {
  /// Nil for files. A directory always has an array, empty if it holds nothing we show.
  public let children: [Self]?
  public let url: URL

  public var id: URL { url }
  public var name: String { url.lastPathComponent }
  public var isDirectory: Bool { children != nil }

  public init(url: URL, children: [Self]?) {
    self.url = url
    self.children = children
  }
}
