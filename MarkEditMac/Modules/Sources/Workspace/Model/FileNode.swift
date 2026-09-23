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

 A node no longer carries its children. The tree is read one directory at a time, as rows are
 expanded, and `WorkspaceModel` holds the listings; a node only has to say whether it is a
 directory, which is what decides whether it gets a disclosure triangle or a selection tag.
 */
public struct FileNode: Identifiable, Hashable, Sendable {
  public let url: URL
  public let isDirectory: Bool

  public var id: URL { url }
  public var name: String { url.lastPathComponent }

  public init(url: URL, isDirectory: Bool) {
    self.url = url
    self.isDirectory = isDirectory
  }
}
