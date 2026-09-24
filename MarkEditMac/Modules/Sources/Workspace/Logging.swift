//
//  Logging.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import OSLog

/**
 The fork's own log, for the failures it deliberately recovers from.

 Upstream has `Logger` in `MarkEditKit`, which this module cannot see — and the module should
 not gain a dependency on the app's frameworks for the sake of one line. `OSLog` is the system's
 own, costs nothing, and is readable after the fact with:

 ```
 log show --last 10m --predicate 'subsystem == "com.quiteyellow.writie-md"' --info
 ```

 It exists because of a bug that had no other way of being diagnosed: a file received from a
 promise drag failed to copy into `assets/` and fell back to a link, and the fallback is
 *supposed* to be silent — so the one thing worth knowing, what the file system actually said,
 was the one thing nobody could see.
 */
enum WorkspaceLog {
  static let drops = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.quiteyellow.writie-md",
    category: "drops"
  )
}
