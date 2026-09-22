# Use of AI in this project

This project uses an AI assistant for parts of its research, code and writing. It is also a fork of someone else's actively developed app, holding a feature that app's maintainer has declined twice, and it edits the user's own files on disk. Process has grown up around both of those. This page describes it, so a reader can weigh a given claim and a contributor knows what is expected.

## Where it helps

- Reading the upstream tree and citing it — `NSDocument` lifecycle, the CodeMirror bridge, the AppKit seams a sidebar has to cut through.
- Writing Swift and TypeScript, tests, and documentation.
- Drafting issue replies, pull-request descriptions and release notes.
- Keeping the fork diff small enough that an upstream sync stays cheap.

## Every public-facing word is read and edited by a human

Issue comments, pull-request descriptions, commit messages, release notes and these docs are reviewed and edited before they go out. It is the rule that matters most, because the failure mode of assistant prose is confident, fluent text that reads exactly like a finding.

Two habits carry it.

**Run an AI-writing pass first.** Vocabulary tells, em-dash habits, hedging, and the sentence shapes that circle a contrast without landing a point. Two reasons this is worth the time. A hedge is usually a symptom: the sentence went vague because the claim under it was never checked against the tree, so the pass catches soft findings as well as soft prose. And a reader weighs a technical claim partly by the writing around it, so text that reads as unedited output spends credibility the argument needs.

**Then cut.** First drafts run long. A section that says the same thing twice, a sentence restating its own heading, a clause carrying emphasis where it should carry information: all of it goes. Duplication also drifts — every restatement is a second place to update, and the copy that falls behind is the one someone reads.

## What always needs a human

**Anything that can lose a user's text.** This is an editor. Document teardown, save and autosave ordering, the `canClose` path, encoding and line-ending handling, and the CodeMirror-to-Swift text flush are the places where a plausible-looking change silently destroys work. Changes there get read line by line and tried against a real build with a real dirty file, including the cancel branch.

**Sandbox, entitlements and security-scoped bookmarks.** Widening an entitlement to make something work is a change to what the app is allowed to reach on the user's disk. It is a decision, not an implementation detail, and it is never made to unblock a build.

**Signing and distribution.** Identities stay in `Local.xcconfig`, which is gitignored. Nothing signed or notarised happens on an assistant's initiative.

**Anything published under the MarkEdit name.** See the upstream rules below.

## Do

- **Cite the file and line, at a revision.** `EditorDocument.swift:244 at 72472b17` beats "MarkEdit's `canClose` does". Upstream ships often — 1.35.0 landed the same month this fork was cut — so a bare line number is a claim about a file that has already moved. A citation without a revision reads exactly like evidence and has a short half-life.
- **Read the tree before describing upstream behaviour.** Assistant recall about a specific third-party app's internals has been wrong often enough not to lean on. The checkout is right there.
- **Establish why something is the way it is before changing it.** `git log`, `git blame`, the commit that introduced the line. A reason that exists and holds gets respected; a reason that exists and is wrong gets quoted and then refuted; no stated reason at all is the strongest licence to change something, and it is only available to someone who actually looked.
- **Report negative results.** "Tried moving the window controller before removing it, AppKit closed the document out from under the switch" is worth as much as the version that worked, and cheaper to write down than to rediscover.
- **Try it in a build.** A claim about what AppKit does when a window controller changes documents comes from running it, or it is labelled as untested. The plan in [`in-window-switching.md`](in-window-switching.md) marks its own two unverified points for exactly this reason.
- **Keep the diff against upstream small and legible.** Every file touched is a merge conflict on the next sync. New code belongs in `MarkEditMac/Modules/Sources/Workspace/`, where SPM picks up files by path and `project.pbxproj` never has to change; an edit to an upstream app-target file needs a reason, and the reason is checked against that file's churn (`git log --since="12 months ago" --oneline -- <path>`) before it is made. The budget is in [`implementation-plan.md`](implementation-plan.md).
- **Measure before asserting an API exists.** The SDK is on disk. `grep` the headers in `$(xcrun --show-sdk-path)` and cite what you found, rather than recalling what a WWDC session said. This has already caught one confident invention: there is no `NSOutlineViewDiffableDataSource` in the macOS 27 SDK, and a design had been drafted around it.
- **Keep identifiers and paths out of tracked files.** Signing identities, team IDs, machine-specific paths and personal directory names stay in `Local.xcconfig` and `.env`.

## Don't

- **Don't state a mechanism the evidence cannot distinguish.** "The window went blank, which means the web view was deallocated" is one of several explanations a blank window is consistent with. Name the observation, then name what would separate the causes.
- **Don't take an upstream design decision as an invitation.** The folder sidebar was declined in [#1389](https://github.com/MarkEdit-app/MarkEdit/issues/1389) and again in [#1417](https://github.com/MarkEdit-app/MarkEdit/issues/1417), with reasons given. Nothing here is destined for a pull request, and no issue is opened upstream to relitigate it. Bug reports about genuine upstream bugs are welcome and separate.
- **Don't push to upstream, or to a contributor's branch.** Being able to is not permission; hand over the diff.
- **Don't ship anything calling itself MarkEdit.** The bundle identifier, app name and icon change before any build leaves this machine. See `NOTICE`.
- **Don't add "Generated by AI" footers.** Disclose authorship in the text where it matters, in plain words, once.
- **Don't write "we" as a solo maintainer.** It invents a team.

## Tips for an assistant working here

- The user scripts in `~/Developer/markedit-folder-sidebar` and `~/Developer/markedit-inline-tables` are the fallback if the fork stalls, and they run against stock MarkEdit. Don't break them to make the fork easier.
- `markedit-folder-sidebar/README.md` already documents the sidebar edge cases — natural sort, folders first, extension-less entries, untitled documents, access-denied state, the keyboard model. Read it before redesigning any of them.
- Reference code lives in `Writie.md.old` (`Utilities/BookmarkStore.swift` is the piece to lift) and `~/Developer/Quite-Listie`. The latter is multiplatform SwiftUI on `NavigationSplitView` — behaviour reference, not portable code for an AppKit split view.
- Any writing checker has false positives: a term of art that collides with a wordlist, or a quotation of the very thing being reported. Note the reason and leave the text as written.

## Contributions written with an assistant

Welcome, on the same terms this project holds itself to. Say so in the pull request, confirm a human has read and edited it, and be explicit about which behaviour you observed in a build you ran yourself.

Rejection follows from an unverified claim presented as a finding, whatever wrote it.
