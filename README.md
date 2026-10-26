# GitGraph Lite

A small native macOS Git history browser, inspired by the compact workflow of VS Code's Git Graph. This is an independent implementation, with no extension source code or assets reused.

## Run

Open **GitGraph Lite.app** in the parent folder, then choose **Open Repository…** (⌘O).

- Coloured commit graph with branch and tag labels.
- Commit message, author, date, and file changes.
- Select a file for a coloured unified diff.
- ⌘-click exactly two commits to compare the older selected commit to the newer one in the displayed history.
- Branch filtering and search across loaded commit messages, authors, hashes and labels.
- Loads 500 commits initially; **Load more** adds another 500.
- Checks refs and HEAD every four seconds and refreshes after external commits, branch changes and tags.
- Remembers the last repository. Supports linked worktrees.
- ⌘R refreshes, ⌘F searches, ⇧⌘C copies selected commit hashes.
- Terminal: `open -a "/path/to/GitGraph Lite.app" --args --repo "/path/to/repository"`.

## Scope of version 0.1

Read-only history browser. Use Fork for staging, committing, remote operations, and history editing. Uncommitted changes are not displayed. Merge commits show changes against the first parent. Renames appear as deletion/addition. Diff previews are capped at 2 MB. Search covers loaded commits; connections are hidden during search to avoid suggesting incorrect graph continuity. Wide graphs may require widening the GRAPH column. Bare repositories are not supported in this version.

Requires macOS 13+ and `/usr/bin/git` (Apple Command Line Tools). This build targets Apple Silicon. Locally ad-hoc signed; not notarized for public distribution.

## Build and test

Requires Swift 5.9+ and the macOS SDK. No external package dependencies.

```sh
zsh build-app.sh
zsh check.sh
```

The build script writes the app beside this source folder. Intermediate build files go in the workspace's `work/build` folder.

## Verified on the development Mac

- Release build and local signature verification pass.
- Automated checks cover graph lane convergence, an empty repository, a root commit, merge diffs against the first parent, arbitrary commit comparison, branch filtering, detached HEAD, and filenames containing Unicode, brackets and a tab.
- Live app checks confirm commit/file/diff display, two-commit comparison, search filtering, and automatic appearance of an externally created tag.
- The window layout was checked visually. Large-repository performance and public distribution have not been validated.
