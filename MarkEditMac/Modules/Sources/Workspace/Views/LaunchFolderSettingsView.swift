//
//  LaunchFolderSettingsView.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI
import SettingsUI

/**
 The Settings rows that choose which folder a launch opens with.

 It lives in the module rather than in `GeneralSettingsView` so that its strings live in the
 module's own catalog: `MarkEditMac/Resources/Localizable.xcstrings` takes 37 upstream commits
 a year and is the worst file in the fork's merge surface to put a line in. The app target
 places this and knows nothing else about it.

 `SettingsUI` is a dependency for `formMenuPicker()` and `formLabel()`, which are what make a
 fork row sit in the same two columns as every upstream one. Without them the picker is a
 different width and the row reads as bolted on, because it is.
 */
public struct LaunchFolderSettingsView: View {
  @Bindable private var folder: LaunchFolder

  public init(folder: LaunchFolder = .shared) {
    self.folder = folder
  }

  public var body: some View {
    Picker(selection: $folder.mode) {
      Text("Last Used", bundle: .module).tag(LaunchFolder.Mode.lastUsed)
      Text("Custom", bundle: .module).tag(LaunchFolder.Mode.custom)
    } label: {
      Text("Default Folder:", bundle: .module)
    }
    .formMenuPicker()
    .onChange(of: folder.mode) {
      // Choosing Custom with nothing pinned has no answer to give, so it asks for one rather
      // than leaving a row that says "No folder chosen" and waiting to be noticed.
      if folder.mode == .custom && !folder.hasPinnedFolder {
        folder.choosePinnedFolder()
      }
    }

    if folder.mode == .custom {
      pinnedRow
        .formLabel(Text(verbatim: ""))
        .formBreathingInset()
    }
  }
}

// MARK: - Private

private extension LaunchFolderSettingsView {
  var pinnedRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        name
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityIdentifier(Self.nameIdentifier)

        Spacer()

        Button {
          folder.choosePinnedFolder()
        } label: {
          Text("Choose Folder…", bundle: .module)
        }
        .accessibilityIdentifier(Self.chooseIdentifier)

        if folder.hasPinnedFolder {
          Button {
            folder.clearPinnedFolder()
          } label: {
            Text("Remove", bundle: .module)
          }
        }
      }

      // Only ever set by a folder the sandbox refused to bookmark, which is rare enough that
      // the alternative was to say nothing and leave the pin silently unchanged.
      if let failure = folder.failure {
        Text(verbatim: failure).formDescription()
      }
    }
  }

  /// The pinned folder's name, and whether it can be opened right now. A pin on a volume that
  /// is not mounted keeps its name — "Archive (unavailable)" is an answer, a blank row is not.
  @ViewBuilder var name: some View {
    if let name = folder.pinnedFolderName {
      Label {
        if folder.pinnedFolder == nil {
          Text("\(name) (unavailable)", bundle: .module)
        } else {
          Text(verbatim: name)
        }
      } icon: {
        Image(systemName: "folder")
      }
    } else {
      Text("No folder chosen", bundle: .module)
        .foregroundStyle(.secondary)
    }
  }
}

public extension LaunchFolderSettingsView {
  /// The control naming the pinned folder, and the button that changes it. A UI test reads the
  /// first and clicks the second; the panel it opens is the half no test here can drive.
  static let nameIdentifier = "workspace.settings.pinned-folder"
  static let chooseIdentifier = "workspace.settings.choose-pinned-folder"
}
