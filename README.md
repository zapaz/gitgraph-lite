# GitGraph Lite

<img src="Assets/AppIcon.png" width="96" alt="GitGraph Lite icon">

A small native macOS Git history browser, inspired by the compact workflow of VS Code's Git Graph. This is an independent implementation, with no extension source code or assets reused.

## Run

Open the prebuilt **GitGraph Lite.app**, or build it from source with the commands below. Then choose **Open Repository…** (⌘O).

- Coloured commit graph with branch and tag labels.
- Compact 24px history rows with a stronger blue/magenta/green/orange graph palette. Branch badges use the matching lane colour, a coloured icon and an individually outlined label; matching local/remote refs share a badge. Tags appear separately at the right of the description. Full ref names and worktree paths remain available in the row tooltip.
- Current worktree HEAD has a ring in the graph and a stronger description/branch label. Worktree occupancy is shown with a small stack marker rather than several long name badges.
- History uses Git's date order so recent commits on parallel branches stay near each other while children remain above their parents. Dates show the committer timestamp in local time, including hours/minutes.
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

## Branch browser and compact history (version 0.8)

- The HISTORY picker supports multiple branches. A branch name includes its local and origin references, even when their tips diverge. Filtering never checks out a branch.
- `main` and `master`, when present, are always pinned and included in filtered history. Star other branches to keep them visible too. Pins persist per repository and are shared between its worktrees. Pinning controls history visibility, not Git write permissions.
- Each branch shows its local/remote versions and associated worktree, with **Open worktree** or one-click **Create worktree**. Remote-only origin branches create a same-named tracking local branch in a new worktree; the active folder is preserved.
- Linear history is grouped into blocks of 5–20 commits by default. Group boundaries stay stable when selecting commits, and hidden selections are cleared when collapsing. The Groups menu reports Collapsed/Expanded/Mixed/Off and its commands can be repeated. Expand/collapse individual groups or use the top-level grouping menu. Branch/tag tips, worktree HEADs, merge commits, junctions and lane transitions remain visible. Searching temporarily shows individual commits.
- The context menu shows pinned actions first and puts all other actions under **Plus…**. Use **Plus… → Pin Actions…** to choose visible actions. Preferences persist across launches. Continue/Abort remain directly available during conflict recovery.
- Changed files default to a collapsible **Tree** view; **Paths** restores the full-path list. File mode persists across launches.
- Commit hashes use ten characters and stronger monospace text; date and author use smaller secondary text.

## Branch navigation (version 0.7)

Worktree creation is automatic. **Create Branch...**, **Create Worktree Here** and the manager's **Create Worktree** button generate a branch name from the commit subject/hash, choose an available folder and open it without a form, location chooser or success dialog. Folders are placed beside the main checkout in `<repository>-worktrees/`; existing folders/branches are never overwritten.

**Checkout... on a remote ref switches branches in the current worktree.** `origin/main` maps to local `main`; `origin/feature/ui` maps to local `feature/ui`. If the local branch is missing, it is created with upstream tracking. Existing local commits and existing upstream settings are preserved; an existing branch without an upstream is linked to the selected remote. Checkout refuses pending operations, dirty working trees when switching, and branches used in another worktree. It never uses force, reset or automatic stash.

- If a branch already belongs to a worktree, **Open Worktree** opens that folder.
- Otherwise, **Create Worktree on This Branch…** automatically creates and opens a worktree with that existing local branch.
- Local-branch checkout opens or creates its worktree automatically. Remote checkout uses the current folder as described above.
- Right-click an individual branch badge to target that ref; in a combined local/remote badge, the remote-name suffix targets the remote. A generic row checkout prefers `origin`, then a stable lexical ordering, with no chooser.
- The **HISTORY** branch menu is a read-only graph filter. It does not change HEAD, files or the checked-out branch.
- Branches currently used by any worktree cannot be renamed or deleted through the app, including the active branch.

## Commit context menu

Actions retain the legacy Git Graph names. Pinned actions appear directly; the rest are under **Plus…**. The available actions include:

```text
Add Tag...
Create Branch...
────────────────────────────────────────────
Checkout...
Cherry Pick...
Revert...
────────────────────────────────────────────
Merge into current branch...
Rebase current branch on this Commit...
Reset current branch to this Commit...
────────────────────────────────────────────
Copy Commit Hash to Clipboard
Copy Commit Subject to Clipboard
```

Reset opens a dialog offering soft/mixed/hard modes. Remote checkout uses the current folder and the same local branch name, without the remote prefix. Local checkout opens or automatically creates a worktree. A commit with no branch gets a new automatically named branch/worktree.

All actions, including comparison, full-message copy, drop and branch/tag management, are available under **Plus…** unless pinned. Use **Plus… → Pin Actions…** to customize the visible menu. Pending operations always expose Continue/Abort directly for conflict recovery.

The menus support:

- Copy its hash or full commit message.
- Compare with HEAD, select a comparison anchor, or compare two selected commits.
- Create a worktree from the commit, or add a lightweight or annotated tag.
- Cherry-pick, revert, merge, rebase the current branch, reset (soft/mixed/hard), or drop an ordinary commit from the current branch's history.
- Choose the mainline parent when cherry-picking or reverting a merge commit.
- Choose fast-forward, merge-commit or squash mode when merging. Squash stages changes without committing.
- Use branch submenus to open/create a worktree, copy the branch name, or rename/safely delete an unused branch; tag submenus can copy/delete a tag.
- Continue or abort a pending merge, rebase, cherry-pick or revert after resolving conflicts in your editor and staging the files.

Mutation dialogs describe the target and effect. Merge, cherry-pick, revert, rebase and drop require a clean working tree. Rebase, reset and drop create a local `gitgraph-backup/...` branch pointing to the previous HEAD. These backups preserve committed history, **not uncommitted changes**. Hard reset explicitly discards local changes after confirmation. Branch deletion uses Git's safe `-d` mode. The app rejects an action if refs, HEAD or the pending operation changed while its dialog was open.

## Worktrees (version 0.3)

- A worktree selector switches between folders without changing their checked-out branches or local changes.
- **Manage Worktrees…** lists every worktree's path, branch or detached HEAD, changed-file count, main/locked/missing/prunable state.
- Create and open a worktree on an automatically named new branch, or reuse an existing local branch, without supplying a name or location. Existing detached worktrees remain supported for browsing and management.
- **Create Worktree Here…** in a commit's context menu starts a new worktree from that commit.
- Move a clean linked worktree, lock/unlock it, or remove it while preserving its branch. Removing a detached worktree first saves its HEAD to a `gitgraph-backup/worktree-...` branch.
- Removal refuses main, active, locked, missing or dirty worktrees, pending operations, and any case rejected by Git. No force removal is offered.
- Branches used in a worktree cannot be renamed/deleted here or checked out simultaneously elsewhere. A remote checkout can switch the current worktree to an available local branch.
- The graph marks worktree HEADs with blue badges and includes commits reachable only from detached worktree HEADs when showing all branches.
- The main window refreshes worktree state automatically; the manager also has a Refresh button. Stale/missing registrations are shown, but pruning and repair remain CLI operations.

## Scope

Version 0.8 adds a multi-branch browser, persistent pins, collapsible history, customizable action menus and a changed-file tree, alongside automatic worktree creation and same-folder remote checkout to the compact history view, enhanced unified viewer and local history operations. Remote fetch/pull/push, stash management, staging/committing and a conflict editor remain outside this version; it does not reproduce every feature of the VS Code extension. Use Fork or your editor for those workflows. Worktree change counts are displayed, but uncommitted diffs are not. Merge diffs use the first parent. Renames appear as deletion/addition. Diff previews are capped at 2 MB. Search covers loaded commits; graph connections are hidden during search. Wide graphs may require widening the GRAPH column. Bare repositories are not supported as the active repository.

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

The application icon is in `Assets/` and is bundled for Finder and the Dock. Its generation prompt is recorded in `Assets/icon-prompt.md`; regenerate its macOS sizes with `zsh make-icon.sh`.

## Verified on the development Mac

- Release build and local signature verification pass.
- Automated checks cover graph lane convergence, an empty repository, a root commit, merge diffs against the first parent, arbitrary commit comparison, branch filtering, detached HEAD, and filenames containing Unicode, brackets and a tab.
- New checks cover aligned replacements, unequal line counts, multiple hunks, Unicode highlight ranges, CRLF and binary-file detection.
- Unified-diff checks verify removal-before-addition ordering, line numbers, change-navigation anchors, blank context lines and newline notes. The unified layout, word highlights, wrap toggle and navigation remaining in Unified mode were checked in the running app.
- Local-action checks use disposable repositories and verify branch/tag operations, cherry-pick, merge/revert, rebase/drop, reset modes and backup refs, rejection of dirty/stale state, and conflict abort/continue.
- Worktree checks cover real linked worktrees with a `.git` file, new/existing branches, detached-only history, Unicode/newline paths, dirty/locked/main/active protections, move/remove, branch retention and branch-occupation guards. The worktree selector, graph badges and two-worktree manager with clean/dirty counts were checked in the running app.
- Regression checks verify that creating worktrees on new/existing branches preserves the active worktree's branch, HEAD, tracked edits and untracked files; history filtering also leaves the active branch unchanged.
- History checks verify local/remote label grouping, diverged refs, symbolic-ref filtering, comma-containing tag names, chronological interleaving across branches and child-before-parent ordering.
- Navigation checks use local disposable remotes to verify `origin/main` → local `main` in the same folder, tracking, preservation of existing local commits, nested branch/remote names, dirty/occupied/stale guards, automatic worktree names/paths and collision handling, reuse, and checkout into an unborn local branch.
- Live app checks confirm commit/file/diff display, two-commit comparison, search filtering, and automatic appearance of an externally created tag.
- The window layout was checked visually. Large-repository performance and public distribution have not been validated.

AppKit grouping regression checks (after building, with a macOS desktop session): `zsh Tests/check-grouping-ui.sh`. These exercise global and per-group collapse after selecting interior commits, repeated commands, hidden selections and search restoration.
