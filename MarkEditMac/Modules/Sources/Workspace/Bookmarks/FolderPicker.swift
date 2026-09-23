//
//  FolderPicker.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/**
 The open panel that chooses the sidebar's folder.

 It is the panel, and nothing else: picking a folder needs nothing the app knows, and keeping
 it here is what lets `WorkspaceModel` stay Foundation-only.

 A free-floating panel rather than a sheet on the window the click came from, because the
 folder it chooses belongs to the app rather than to that window — every open sidebar follows
 it. This is also the shape upstream's Grant Folder Access panel takes.
 */
@MainActor
enum FolderPicker {
  /// Run the panel. Returns the chosen folder, or nil if the user cancelled.
  static func chooseFolder(startingAt current: URL?) async -> URL? {
    let panel = NSOpenPanel()
    panel.prompt = String(
      localized: "Choose",
      bundle: .module,
      comment: "Confirmation button of the panel that picks the sidebar's folder"
    )

    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = current

    guard await panel.begin() == .OK else {
      return nil
    }

    return panel.url
  }
}
