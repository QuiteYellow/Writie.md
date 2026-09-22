# Writie.md

A fork of [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) with a folder sidebar.

MarkEdit is a small, fast, native Markdown editor for macOS. It is a single-file editor on purpose: it opens the file you hand it and leaves file management to Finder. This fork adds a panel listing the files beside the current document, so a folder of notes can be worked through without going back to Finder for each one. Clicking a file replaces the document in the window; right-click opens it in a new window.

## Status

Unfinished, and there are no releases. The sidebar lists a folder and opens files from it. Choosing that folder, keeping it across launches, and updating the list when files change on disk are not built yet. If you want a Markdown editor today, use MarkEdit.

## Why this is a fork

MarkEdit is the best open-source Markdown editor I've used, but I wish it had folder support. Workspace features are out of scope for it, as mentioned in ([#1389](https://github.com/MarkEdit-app/MarkEdit/issues/1389), [#1417](https://github.com/MarkEdit-app/MarkEdit/issues/1417), [#736](https://github.com/MarkEdit-app/MarkEdit/issues/736)). That is a reasonable line for a single-file editor to hold, and it is not disputed here. Nothing in this repository is destined for an upstream pull request.

The fork is unofficial and unaffiliated. Report anything broken here, not to MarkEdit. See [NOTICE](NOTICE) for the full statement.

## Building

Runs on macOS 15 and later.

The editor's web bundle is generated and is not in the repository. Xcode cannot build without it, and the error it gives when the bundle is missing says only that `index.html` couldn't be opened.

Upstream builds it with Node and yarn. Deno works too:

```
cd CoreEditor
deno install
deno run -A npm:vite build
```

Signing values stay out of the repository. Copy the template, fill it in, then generate the local config and build:

```
cp .env.example .env
./gen-signing.sh
xcodebuild -project MarkEdit.xcodeproj -scheme MarkEditMac -configuration Debug build
```

## Licence

MIT, unchanged from upstream. Copyright in the original work is MarkEdit.app's. See [LICENSE](LICENSE) for the terms and [NOTICE](NOTICE) for what this fork changes and what it does not claim.
