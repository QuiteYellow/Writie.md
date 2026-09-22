//
//  FolderScannerTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import XCTest
@testable import Workspace

final class FolderScannerTests: XCTestCase {
  func testOrdersFoldersFirstThenNaturally() async throws {
    let root = try makeTree([
      "9.md",
      "10.md",
      "Notes/inner.md",
      "archive/old.md",
    ])

    let nodes = try await FolderScanner.scan(root: root, options: .markdown)
    // Case-insensitive like Finder, so "archive" sorts before "Notes", and 9 before 10
    XCTAssertEqual(nodes.map(\.name), ["archive", "Notes", "9.md", "10.md"])
    XCTAssertEqual(nodes.map(\.isDirectory), [true, true, false, false])
  }

  func testKeepsKnownExtensionsAndExtensionLessFiles() async throws {
    let root = try makeTree([
      "keep.md",
      "keep.markdown",
      "keep.txt",
      "Upper.MD",
      "README",
      "drop.png",
      "drop.pdf",
    ])

    let nodes = try await FolderScanner.scan(root: root, options: .markdown)
    XCTAssertEqual(Set(nodes.map(\.name)), ["keep.md", "keep.markdown", "keep.txt", "Upper.MD", "README"])
  }

  func testDescendsIntoSubfolders() async throws {
    let root = try makeTree(["top/middle/bottom.md"])
    let nodes = try await FolderScanner.scan(root: root, options: .markdown)

    let middle = try XCTUnwrap(nodes.first?.children?.first)
    XCTAssertEqual(middle.name, "middle")
    XCTAssertEqual(middle.children?.map(\.name), ["bottom.md"])
  }

  func testHidesDotFilesUnlessAsked() async throws {
    let root = try makeTree([".hidden.md", "shown.md"])

    let hiding = try await FolderScanner.scan(root: root, options: .markdown)
    XCTAssertEqual(hiding.map(\.name), ["shown.md"])

    let showing = try await FolderScanner.scan(root: root, options: .markdownShowingHidden)
    XCTAssertEqual(showing.map(\.name), [".hidden.md", "shown.md"])
  }

  func testTreatsAPackageAsAFileAndDoesNotDescend() async throws {
    let root = try makeTree(["bundle.textbundle/text.md"])
    let nodes = try await FolderScanner.scan(root: root, options: .textBundle)

    XCTAssertEqual(nodes.map(\.name), ["bundle.textbundle"])
    XCTAssertFalse(try XCTUnwrap(nodes.first).isDirectory)
  }

  func testUnreadableRootThrows() async {
    let missing = URL(filePath: NSTemporaryDirectory()).appending(path: "does-not-exist-\(UUID().uuidString)")

    do {
      _ = try await FolderScanner.scan(root: missing, options: .markdown)
      XCTFail("Expected scanning a missing folder to throw")
    } catch {
      XCTAssertEqual(error, .unreadable(missing))
    }
  }
}

// MARK: - Private

private extension FolderScanner.Options {
  static let markdown = Self(fileExtensions: ["md", "markdown", "txt"], showsHiddenFiles: false)
  static let markdownShowingHidden = Self(fileExtensions: ["md", "markdown", "txt"], showsHiddenFiles: true)
  static let textBundle = Self(fileExtensions: ["textbundle"], showsHiddenFiles: false)
}

private extension FolderScannerTests {
  /// Builds a throwaway tree from a list of relative paths; a path with a slash makes folders.
  func makeTree(_ paths: [String]) throws -> URL {
    let root = URL(filePath: NSTemporaryDirectory())
      .appending(path: "FolderScannerTests-\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }

    for path in paths {
      let url = root.appending(path: path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: url)
    }

    return root
  }
}

extension FolderScanner.Failure: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case let (.unreadable(lhs), .unreadable(rhs)):
      return lhs == rhs
    }
  }
}
