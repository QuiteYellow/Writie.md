//
//  SidebarSettingsView.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI
import SettingsUI

/**
 The Settings rows that decide what the sidebar lists.

 In the module rather than in `GeneralSettingsView` for the reason `LaunchFolderSettingsView`
 is: its strings then live in the module's own catalog, and `MarkEditMac/Resources/
 Localizable.xcstrings` takes 37 upstream commits a year. The app target places this and knows
 nothing else about it.

 A `VStack` of toggles under one label is upstream's own shape for a group of switches
 (`EditorSettingsView`'s Display Options), so these sit in the same two columns as every row
 around them.

 Nothing here tells a window to refresh: `SidebarFilter` is `@Observable`, and every open
 window's `WorkspaceModel` is watching it. The old app posted a `.sidebarSettingsChanged`
 notification to do the same job.
 */
public struct SidebarSettingsView: View {
  @Bindable private var filter: SidebarFilter

  public init(filter: SidebarFilter = .shared) {
    self.filter = filter
  }

  public var body: some View {
    VStack(alignment: .leading) {
      Toggle(isOn: $filter.showsAllFiles) {
        Text("Show all file types", bundle: .module)
      }
      .accessibilityIdentifier(Self.allFilesIdentifier)

      Toggle(isOn: $filter.showsHiddenFiles) {
        Text("Show hidden files", bundle: .module)
      }
      .accessibilityIdentifier(Self.hiddenFilesIdentifier)

      Toggle(isOn: $filter.hidesAssetsFolders) {
        Text("Hide Assets folders", bundle: .module)
      }
      .accessibilityIdentifier(Self.assetsFoldersIdentifier)
    }
    .formLabel(alignment: .top, Text("Sidebar:", bundle: .module))
    .formBreathingInset()
  }
}

public extension SidebarSettingsView {
  /// The three switches, so a UI test can work them without matching on a localised title.
  static let allFilesIdentifier = "workspace.settings.shows-all-files"
  static let hiddenFilesIdentifier = "workspace.settings.shows-hidden-files"
  static let assetsFoldersIdentifier = "workspace.settings.hides-assets-folders"
}
