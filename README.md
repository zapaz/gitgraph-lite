# GitGraph Lite

A small native macOS Git history browser, inspired by the compact workflow of VS Code's Git Graph. This is an independent implementation, with no extension source code or assets reused.

## Run

Open the prebuilt **GitGraph Lite.app**, or build it from source with the commands below. Then choose **Open Repository…** (⌘O).

- Coloured commit graph with branch and tag labels.
- Commit message, author, date, and file changes.
- Select a file for a side-by-side diff with aligned lines, old/new line numbers, line backgrounds and highlighted changed text.
- Scroll each side horizontally; vertical scrolling stays synchronized. Use the arrow buttons to jump between changes, or switch to **Unified** to copy a patch.
- Unified view has fixed OLD/NEW line-number gutters and change markers, full-width addition/deletion backgrounds, word highlights, hunk separators and optional line wrapping. Next/previous change stays in the selected mode and shows a change counter. Text remains selectable; **Copy patch** copies Git's original patch, including its metadata and prefixes (disabled for truncated previews).
- ⌘-click exactly two commits to compare the older selected commit to the newer one in the displayed history.
- Branch filtering and search across loaded commit messages, authors, hashes and labels.
- Loads 500 commits initially; **Load more** adds another 500.
- Checks refs and HEAD every four seconds and refreshes after external commits, branch changes and tags.
- Remembers the last repository/worktree.
- ⌘R refreshes, ⌘F searches, ⇧⌘C copies selected commit hashes.
- Terminal: `open -a "/path/to/GitGraph Lite.app" --args --repo "/path/to/repository"`.

## Commit context menu (version 0.2)

Right-click any commit to:

- Copy its hash or full commit message.
- Compare with HEAD, select a comparison anchor, or compare two selected commits.
- Create a branch (optionally check it out), add a lightweight or annotated tag, or check out a detached commit.
- Cherry-pick, revert, merge, rebase the current branch, reset (soft/mixed/hard), or drop an ordinary commit from the current branch's history.
- Choose the mainline parent when cherry-picking or reverting a merge commit.
- Choose fast-forward, merge-commit or squash mode when merging. Squash stages changes without committing.
- Use submenus for local branches/tags on the commit: check out, rename or safely delete a branch; copy or delete a tag.
- Continue or abort a pending merge, rebase, cherry-pick or revert after resolving conflicts in your editor and staging the files.

Mutation dialogs describe the target and effect. Checkout, merge, cherry-pick, revert, rebase and drop require a clean working tree. Rebase, reset and drop create a local `gitgraph-backup/...` branch pointing to the previous HEAD. These backups preserve committed history, **not uncommitted changes**. Hard reset explicitly discards local changes after confirmation. Branch deletion uses Git's safe `-d` mode. The app rejects an action if refs, HEAD or the pending operation changed while its dialog was open.

## Worktrees (version 0.3)

- A worktree selector switches between folders without changing their checked-out branches or local changes.
- **Manage Worktrees…** lists every worktree's path, branch or detached HEAD, changed-file count, main/locked/missing/prunable state.
- Create a worktree on a new branch, an unused existing local branch, or a detached commit. Optionally open it immediately.
- **Create Worktree Here…** in a commit's context menu starts a new worktree from that commit.
- Move a clean linked worktree, lock/unlock it, or remove it while preserving its branch. Removing a detached worktree first saves its HEAD to a `gitgraph-backup/worktree-...` branch.
- Removal refuses main, active, locked, missing or dirty worktrees, pending operations, and any case rejected by Git. No force removal is offered.
- Branches checked out in another worktree cannot be checked out, renamed or deleted here; their branch submenu offers **Open Worktree**.
- The graph marks worktree HEADs with blue badges and includes commits reachable only from detached worktree HEADs when showing all branches.
- The main window refreshes worktree state automatically; the manager also has a Refresh button. Stale/missing registrations are shown, but pruning and repair remain CLI operations.

## Scope

Version 0.4 adds the enhanced unified viewer alongside local history operations and worktree management. Remote fetch/pull/push, stash management, staging/committing and a conflict editor remain outside this version; it does not reproduce every feature of the VS Code extension. Use Fork or your editor for those workflows. Worktree change counts are displayed, but uncommitted diffs are not. Merge diffs use the first parent. Renames appear as deletion/addition. Diff previews are capped at 2 MB. Search covers loaded commits; graph connections are hidden during search. Wide graphs may require widening the GRAPH column. Bare repositories are not supported as the active repository.

For repositories in macOS protected folders, use **Open Repository…** and grant access when macOS requests it.

Requires macOS 13+ and `/usr/bin/git` (Apple Command Line Tools). This build targets Apple Silicon. Locally ad-hoc signed; not notarized for public distribution.

## Build and test

Requires Swift 5.9+ and the macOS SDK. No external package dependencies.

```sh
zsh build-app.sh
zsh check.sh
open "dist/GitGraph Lite.app"
```

The build script writes `dist/GitGraph Lite.app`. Intermediate files and caches go in `.build-local/`; both folders are ignored by Git. To use another location, set `GITGRAPH_BUILD_ROOT` for intermediate files or `GITGRAPH_APP_PATH` for the app bundle.

## Verified on the development Mac

- Release build and local signature verification pass.
- Automated checks cover graph lane convergence, an empty repository, a root commit, merge diffs against the first parent, arbitrary commit comparison, branch filtering, detached HEAD, and filenames containing Unicode, brackets and a tab.
- New checks cover aligned replacements, unequal line counts, multiple hunks, Unicode highlight ranges, CRLF and binary-file detection.
- Unified-diff checks verify removal-before-addition ordering, line numbers, change-navigation anchors, blank context lines and newline notes. The unified layout, word highlights, wrap toggle and navigation remaining in Unified mode were checked in the running app.
- Local-action checks use disposable repositories and verify branch/tag operations, cherry-pick, merge/revert, rebase/drop, reset modes and backup refs, rejection of dirty/stale state, and conflict abort/continue.
- Worktree checks cover real linked worktrees with a `.git` file, new/existing branches, detached-only history, Unicode/newline paths, dirty/locked/main/active protections, move/remove, branch retention and branch-occupation guards. The worktree selector, graph badges and two-worktree manager with clean/dirty counts were checked in the running app.
- Live app checks confirm commit/file/diff display, two-commit comparison, search filtering, and automatic appearance of an externally created tag.
- The window layout was checked visually. Large-repository performance and public distribution have not been validated.
