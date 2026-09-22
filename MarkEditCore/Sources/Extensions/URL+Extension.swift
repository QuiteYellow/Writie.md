//
//  URL+Extension.swift
//
//  Created by cyan on 12/23/25.
//

import Foundation

public extension URL {
  static var standardDirectories: [String: String] {
    [
      "home": Self.homeDirectory,
      "documents": Self.documentsDirectory,
      "library": Self.libraryDirectory,
      "caches": Self.cachesDirectory,
      "temporary": Self.temporaryDirectory,
      "sharedContainer": Self.sharedContainerURL,
    ].compactMapValues {
      $0?.path(percentEncoded: false)
    }
  }

  static var sharedContainerURL: URL? {
    // The app group needs development signing, which ad-hoc local builds don't have,
    // and containerURL(forSecurityApplicationGroupIdentifier:) hands back a path either
    // way. Report nil unless the container really exists: every caller already degrades
    // gracefully, whereas EditorIndexHtml.copyToSharedContainer otherwise trips its
    // assertion on each Debug launch trying to create a directory only the OS may create.
    guard let url = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.quiteyellow.writie-md"
    ) else {
      return nil
    }

    // Existence is not enough. Once containermanagerd has created the container, it stays
    // created and cannot be removed — so a half-configured group (App ID registered, App
    // Group not yet enabled on it) leaves a directory the sandbox still refuses to write.
    let path = url.path(percentEncoded: false)
    guard FileManager.default.fileExists(atPath: path),
          FileManager.default.isWritableFile(atPath: path) else {
      return nil
    }

    return url
  }

  /// Files in this directory whose extension is in `types`, sorted by localized filename order.
  func sortedFiles(types: Set<String>) -> [URL] {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: self,
      includingPropertiesForKeys: nil
    )) ?? []

    return files
      .filter { types.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }
}
