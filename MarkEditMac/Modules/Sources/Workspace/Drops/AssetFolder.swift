//
//  AssetFolder.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 Where a dropped file lands: `assets/`, beside the document it was dropped into.

 **The convention, and why it is spelled `assets`.** Upstream already copies a file dropped on
 a `.textbundle` into that bundle's `assets/` folder, but that is textbundle *spec* compliance
 inside a container the app made, so it is weaker precedent than it looks. What settles it is
 the old Writie app: it hid folders named `assets` in plain user folders and never created
 one, which means it assumed the notes already had them — as Obsidian, Bear and Typora vaults
 do. `_assets` would have been invisible to that convention and to the sidebar's own hide rule
 for the sake of one narrow collision (a folder where `assets/` means build output), which is
 untidy rather than harmful. Full reasoning in `drops.md` §1.

 **Beside the document, not at the workspace root.** The requirement is that *a note and its
 `assets/` folder travel together*: move the subtree a note lives in and its links still
 resolve. A root-level assets folder would make every note depend on the whole vault.

 **Copy, never move, and never overwrite.** A drop must never be the reason a file leaves
 someone's Desktop, and an existing `photo.png` is never replaced — the second copy is
 `photo-1.png`, which is upstream's `TextBundleAssets` convention, deliberately duplicated here
 rather than made public there (~15 lines against an edit to an upstream file, and the fork's
 budget prefers the duplication). The two are the same convention and must stay that way.

 **One case the spec did not name, decided here: a file that is already inside the document's
 own folder is linked where it lies.** Copying it would leave two of it in a folder the user
 curates, and it is already as portable as the copy would be — it travels with the same
 subtree. So `staged` returns it unchanged, and `FileDropHandler` writes the relative link it
 would have written before any of this existed.
 */
public enum AssetFolder {
  /// The folder's name, in one place. The sidebar's "Hide Assets folders" preference compares
  /// against this, so hiding the folder and creating it cannot drift apart.
  public static let name = "assets"

  /**
   The file to link, given the file that was dropped.

   Returns `source` unchanged — which is the behaviour that existed before group D — whenever
   copying is not the right answer or is not possible:

   - **No document URL.** An untitled document has nothing for a relative link to be relative
     to; `EditorDrops` saves it before the drop is delivered, so by here this means there is
     nothing to be done.
   - **The document is itself a folder**, which is what a `.textbundle` is. Upstream's own
     path copies into the bundle's `assets/`, and it should keep doing that. Asked of the file
     system rather than of the document's type name, because the question is exactly "is there
     a folder to put this beside".
   - **The source is already inside the document's folder.** See the type's note above.
   - **The copy failed.** The likeliest cause is the sandbox: opening a document grants access
     to that file, not to the directory it sits in, so a document opened from outside the
     workspace root may have nowhere to write. A relative link to the file where it lies is a
     worse answer than the copy and a much better one than inserting nothing.
   */
  public static func staged(_ source: URL, besideDocumentAt documentURL: URL?) -> URL {
    guard let documentURL, !isDirectory(documentURL) else {
      return source
    }

    let directory = documentURL.deletingLastPathComponent()
    guard !isInside(source, directory) else {
      return source
    }

    do {
      return try stage(source, in: directory)
    } catch {
      // Recovered from deliberately — a link to the file where it lies still works — but the
      // recovery is silent, so the reason has to go somewhere. It went nowhere until a real
      // drag failed this way and there was nothing to read. See `WorkspaceLog`.
      WorkspaceLog.drops.error("Could not stage \(source.path(percentEncoded: false), privacy: .public) into \(directory.path(percentEncoded: false), privacy: .public): \(error.localizedDescription, privacy: .public)")

      return source
    }
  }

  /// Copy `source` into `directory`'s `assets/` folder under a name that is not taken, and
  /// hand back where it landed. Throws whatever the file system said, which is what the
  /// caller turns into "link it where it lies".
  public static func stage(_ source: URL, in directory: URL) throws -> URL {
    let assets = directory.appending(path: name, directoryHint: .isDirectory)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)

    let existing = (try? fileManager.contentsOfDirectory(atPath: assets.path(percentEncoded: false))) ?? []
    let destination = assets.appending(path: uniqueName(for: source, existing: Set(existing)))

    try fileManager.copyItem(at: source, to: destination)
    return destination
  }
}

// MARK: - Private

private extension AssetFolder {
  /// `photo.png`, or `photo-1.png`, `photo-2.png`, … when that name is taken. The same rule as
  /// `TextBundleAssets.uniqueFileName`, which is `private` to that module — and deliberately
  /// **not** the `" copy"` suffix `FileActions.duplicate` uses: one is importing a file, the
  /// other is duplicating one in place, and unifying them would make both read wrong.
  static func uniqueName(for source: URL, existing: Set<String>) -> String {
    let preferred = source.lastPathComponent
    guard existing.contains(preferred) else {
      return preferred
    }

    let pathExtension = source.pathExtension
    let baseName = source.deletingPathExtension().lastPathComponent
    let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"

    var index = 1
    while true {
      let candidate = "\(baseName)-\(index)\(suffix)"
      if !existing.contains(candidate) {
        return candidate
      }

      index += 1
    }
  }

  /// Whether `url` sits anywhere under `directory`.
  ///
  /// Both sides go through the same canonicalisation — the one `URL.relativePath(from:)` uses
  /// to build the link this answer decides — so the `/var` against `/private/var` disagreement
  /// that has bitten this fork twice cannot appear between them. Canonicalising *one* side is
  /// what causes it; canonicalising both is what the link itself does.
  static func isInside(_ url: URL, _ directory: URL) -> Bool {
    let base = canonicalPath(directory)
    let target = canonicalPath(url)
    return target.hasPrefix(base.hasSuffix("/") ? base : "\(base)/")
  }

  static func canonicalPath(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
  }

  static func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
  }
}
