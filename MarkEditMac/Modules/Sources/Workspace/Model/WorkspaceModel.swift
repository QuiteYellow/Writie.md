//
//  WorkspaceModel.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 What the sidebar is showing, and what happens when a row is clicked.

 `@Observable` rather than `ObservableObject`: the SwiftUI view reads the properties it uses
 and re-renders on those, with no `@Published` and no Combine.
 */
@MainActor
@Observable
public final class WorkspaceModel {
  public enum State {
    case noRoot
    case loading
    case loaded([FileNode])
    case unreadable(URL)
  }

  public private(set) var root: URL?
  public private(set) var state: State = .noRoot

  /// The row drawn as selected. Setting it is what opens a file.
  public var selection: URL? {
    didSet {
      guard let selection, selection != oldValue else {
        return
      }

      open(selection)
    }
  }

  public init(host: WorkspaceHost?, options: FolderScanner.Options) {
    self.host = host
    self.options = options
  }

  public func setRoot(_ url: URL?) {
    guard url != root else {
      return
    }

    root = url
    selection = host?.currentFileURL
    reload()
  }

  public func reload() {
    scanTask?.cancel()

    guard let root else {
      return state = .noRoot
    }

    state = .loading
    let options = options

    scanTask = Task { [weak self] in
      let result = try? await FolderScanner.scan(root: root, options: options)
      guard !Task.isCancelled, let self else {
        return
      }

      state = result.map { State.loaded($0) } ?? .unreadable(root)
    }
  }

  // MARK: - Private

  private weak var host: WorkspaceHost?
  private let options: FolderScanner.Options
  private var scanTask: Task<Void, Never>?

  private func open(_ url: URL) {
    // Directories expand and collapse, they don't replace the document. The view doesn't tag
    // them as selectable either; this is the half that doesn't depend on the view getting it
    // right, and it also covers a selection restored before the scan finished.
    guard case .loaded(let nodes) = state, Self.node(for: url, in: nodes)?.isDirectory == false else {
      return
    }

    host?.openInPlace(url)
  }

  private static func node(for url: URL, in nodes: [FileNode]) -> FileNode? {
    for candidate in nodes {
      if candidate.url == url {
        return candidate
      }

      if let children = candidate.children, let match = node(for: url, in: children) {
        return match
      }
    }

    return nil
  }
}
