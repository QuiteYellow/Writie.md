//
//  NSApplication+Extras.swift
//  MarkEditMac
//
//  Created by cyan on 12/13/22.
//

import AppKit
import MarkEditKit

extension NSApplication {
  var appDelegate: AppDelegate? {
    guard let delegate = delegate as? AppDelegate else {
      Logger.assert(delegate != nil, "Expected to get AppDelegate")
      return nil
    }

    return delegate
  }

  var currentEditor: EditorViewController? {
    keyWindow?.hostedEditor ?? mainWindow?.hostedEditor
  }

  func terminateSafely(_ sender: Any? = nil) {
    RunLoop.performOnMain {
      Terminator.shared.terminateApp(sender)
    }
  }

  func relaunchSafely(_ sender: Any? = nil, safeMode: Bool = false) {
    RunLoop.performOnMain {
      Terminator.shared.relaunchApp(sender, safeMode: safeMode)
    }
  }
}

// MARK: - Editor Lookup

/**
 Fork addition: windows wrap the editor in a container (an `NSSplitViewController`,
 once the sidebar lands), so a window's `contentViewController` is no longer the
 editor itself. Everything that used to cast reaches the editor through here instead.

 Kept in this file rather than a new one because new app-target files mean
 `project.pbxproj` edits, and that file is the worst merge surface in the repository.
 */
extension NSViewController {
  /// The editor hosted by this controller, whether it is the controller itself or a descendant.
  var hostedEditor: EditorViewController? {
    if let editor = self as? EditorViewController {
      return editor
    }

    for child in children {
      if let editor = child.hostedEditor {
        return editor
      }
    }

    return nil
  }
}

extension NSWindow {
  /// The editor hosted by this window, at any depth below its content view controller.
  var hostedEditor: EditorViewController? {
    contentViewController?.hostedEditor
  }
}

// MARK: - Terminator

@MainActor
private final class Terminator: NSObject {
  static let shared = Terminator()

  func terminateApp(_ sender: Any?) {
    if AppPreferences.General.quitAlwaysKeepsWindows, let unsavedDraft {
      return unsavedDraft.runModalSavePanel(
        for: .saveOperation,
        delegate: self,
        didSave: #selector(handleDraftSave(_:didSave:)),
        contextInfo: nil
      )
    }

    performTermination(sender)
  }

  func relaunchApp(_ sender: Any? = nil, safeMode: Bool = false) {
    AppRelauncher.request(safeMode: safeMode)
    terminateApp(sender)
  }

  // MARK: - Private

  override private init() {}

  private var unsavedDraft: NSDocument? {
    NSDocumentController.shared.editorDocuments.first {
      $0.fileURL == nil && ($0.isOutdated || $0.hasUnautosavedChanges)
    }
  }

  private func performTermination(_ sender: Any?) {
    NSDocumentController.shared.editorDocuments.forEach {
      $0.isTerminating = true
    }

    NSApp.terminate(sender)
  }

  @objc private func handleDraftSave(_ document: NSDocument, didSave: Bool) {
    guard didSave else {
      AppRelauncher.cancel()
      return
    }

    if AppRelauncher.isRequested {
      RunLoop.performOnMain { [weak self] in
        self?.terminateApp(nil)
      }
    } else if unsavedDraft == nil {
      performTermination(nil)
    } else {
      document.close()
    }
  }
}
