//
//  SidebarDrop.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/**
 What a *file* dropped on the sidebar does: which folder it lands in, and whether that is a
 copy or a move.

 Kept apart from the view, like `FolderDrop`'s pasteboard half, because a drag cannot be
 synthesized on this machine — so every rule here is reachable as a function, and the view is
 left with nothing but geometry and AppKit callbacks.

 **A folder dropped on the sidebar still re-roots, even when it lands on a row.** `drops.md`
 §3.0 says "a folder dropped anywhere on the sidebar — the tree, or the placeholder — becomes
 the root", and that shipped before per-row targeting existed. Read literally it still holds,
 so it is what this implements. It is worth a second look rather than a settled decision:
 Finder would copy the folder into the row it landed on, and the spec's sentence was written
 when there was no row to land on. Recorded as an open question in `TRACKER.md` ▸ *Backlog* ▸ D
 rather than decided here, because quietly changing a gesture the user asked for two hours
 earlier is the worse of the two mistakes.
 */
enum SidebarDrop {
  /**
   Where a drag came from, which is the whole of what decides the default.

   `.sidebar` is **not reachable from the view today** — originating a drag out of a row is
   D11b and nothing does it yet — and it is a parameter rather than a hard-coded `.outside`
   precisely so that §3.2's rule is written down and tested now, while the reasoning behind it
   is fresh, instead of being re-derived when D11b arrives.
   */
  enum Source {
    case outside
    case sidebar
  }

  /**
   Copy or move, per `drops.md` §3.1 and §3.2.

   | Gesture | Default | Modifier |
   |---|---|---|
   | From outside the app into a folder | copy | ⌘ moves |
   | From one sidebar folder to another | move | ⌥ copies |

   The asymmetry is deliberate and is not an inconsistency: a drop from outside is an *import*,
   where copying leaves the original where it was, and a drag within the tree is a
   *reorganise*, where copying would leave a duplicate every time someone tidied. Each default
   is the non-destructive reading of **that** gesture.

   **The modifier for a move is ⌘, not ⌥.** Finder's set is ⌘ force move, ⌥ force copy — so the
   key that is easy to misremember as "the modify key" is the exact opposite of what is wanted,
   and picking it would silently duplicate a file every time someone meant to move one.

   **The badge is AppKit's, not ours.** It draws the green plus for `.copy` and nothing for
   `.move`, which is the Finder vocabulary a user already reads as "this will move".

   **Intersected with what the source allows.** `draggingSourceOperationMask` is the source's
   permission, and returning an operation outside it refuses the drop with no explanation. When
   what is wanted is not on offer the fallback is `.copy` and **never** `.move`: a source that
   will not copy is not a reason to delete someone's file, so the drag is refused instead.
   */
  static func operation(
    from source: Source,
    modifiers: NSEvent.ModifierFlags,
    allowedBy mask: NSDragOperation
  ) -> NSDragOperation {
    let wanted: NSDragOperation = switch source {
    case .outside:
      modifiers.contains(.command) ? .move : .copy
    case .sidebar:
      modifiers.contains(.option) ? .copy : .move
    }

    if mask.contains(wanted) {
      return wanted
    }

    return mask.contains(.copy) ? .copy : []
  }

  /**
   Which folder receives a drop that landed on `node`: the folder itself, or the folder the
   file sits in. Nothing under the pointer means the root, which is what a drop on empty space
   below the last row means.

   The same rule New File and New Folder use, because "where does a new thing go" and "where
   does a dropped thing go" are one question — two answers would be a bug on the day somebody
   noticed them disagreeing.
   */
  static func destination(landingOn node: FileNode?, root: URL?) -> URL? {
    guard let node else {
      return root
    }

    return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
  }

  /**
   Every file in the drag, in pasteboard order.

   Unlike `FolderDrop.folder(in:)`, which picks one, an import takes the lot — and unlike
   `EditorDrops.droppedFiles(on:)` it does not filter out a promise's placeholder, because the
   caller checks for promises first and never gets here with one.
   */
  static func files(in pasteboard: NSPasteboard) -> [URL] {
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL]

    return (urls ?? []).filter { !$0.lastPathComponent.isEmpty && $0.lastPathComponent != "/" }
  }

  /// The promises in the drag — a screenshot, a Mail attachment, an SFTP file — which have no
  /// file behind them yet. Read before `files`, because their placeholder URLs are useless.
  static func promises(in pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
    (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? []
  }
}
