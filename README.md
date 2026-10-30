<div align="center">
  <img src="Assets/AppIcon.png" width="80" alt="GitGraph Lite icon">
  <h1>GitGraph Lite</h1>
  <p><strong>Parallel AI coding. Separate worktrees. One clear graph.</strong></p>
  <p>A lightweight, native macOS Git browser with worktrees at its core.<br>Give each AI task its own branch and working folder. Review them all in one graph.</p>
  <p>
    <a href="https://github.com/zapaz/gitgraph-lite/releases/latest"><strong>Download for macOS</strong></a>
    &nbsp;·&nbsp; <a href="docs/guide.md">User guide</a>
    &nbsp;·&nbsp; <a href="HISTORY.md">Release history</a>
  </p>
  <p><sub>macOS 13+ · Apple Silicon · Native AppKit · MIT licensed</sub></p>
</div>

<a href="docs/screenshots/branch-actions.png"><img src="docs/screenshots/branch-actions.png" width="1440" alt="GitGraph Lite showing a complex five-branch history with merges, tags, worktrees, a visual diff and the action menu for feature/search"></a>

<p align="center"><sub>A real app capture with the fictional Atlas sample repository. Click any image to view it full size.</sub></p>

## Worktrees: the foundation of parallel AI coding

One AI agent builds a feature. Another fixes a bug. You review a third task. When they share a working folder, they also share its checked-out branch and local edits. **Git worktrees give each task a separate working folder and branch within the same repository**—an essential foundation for working on several branches with AI in parallel.

GitGraph Lite puts worktree management at the centre of that workflow:

- **One task, one branch, one workspace.** Open a branch to create its worktree automatically, or reuse its existing folder. Branches can wait without a folder until you need them.
- **Keep parallel work in place.** Point each AI agent or editor session at its task's worktree. The app never switches an existing worktree to another branch; opening another task leaves your current files and local changes in place.
- **Review everything together.** See branches, worktrees and merges in one graph. Inspect diffs, compare commits and bring finished work into the branch you choose.

GitGraph Lite manages the Git side of the workflow alongside your AI tools; you run the agents in their respective folders.

## Your history, without the clutter

- **Follow every branch.** Trace merges across a coloured graph. See local branches, origin refs, tags and worktrees in context.
- **Understand the change.** Inspect side-by-side or unified diffs with line numbers and word highlights. Browse changed files as a folder tree, or compare two commits with ⌘-click.
- **Act on exactly what you click.** Short menus for commits, branches, tags and worktrees. Push one branch, publish one tag, or pull into the selected branch's workspace with fast-forward protection.
- **Make room for what matters.** Filter several branches, pin the important ones and fold long commit chains. The graph refreshes after changes made in your other Git tools.

## Take a closer look

<p align="center">
  <a href="docs/screenshots/diff-side-by-side.png" title="Side-by-side diffs"><img src="docs/screenshots/diff-side-by-side.png" width="190" alt="Side-by-side diff with word highlights and a changed-file tree"></a>
  <a href="docs/screenshots/diff-unified.png" title="Unified diff · dark mode"><img src="docs/screenshots/diff-unified.png" width="190" alt="Unified diff in dark mode with old and new line numbers"></a>
  <a href="docs/screenshots/branch-picker.png" title="Branches and pins"><img src="docs/screenshots/branch-picker.png" width="190" alt="Multi-branch picker with local and origin refs, branch pins and workspace state"></a>
  <a href="docs/screenshots/worktrees.png" title="Worktrees for parallel AI tasks"><img src="docs/screenshots/worktrees.png" width="190" alt="Worktree manager with three dedicated workspaces, their branches, paths and clean or modified state"></a>
</p>

<p align="center"><sub>Side-by-side diffs · Unified in dark mode · Branches &amp; pins · Parallel worktrees</sub></p>

## Get started

1. **[Download the latest release](https://github.com/zapaz/gitgraph-lite/releases/latest)** for Apple Silicon.
2. Unzip it and drag **GitGraph Lite.app** into **Applications**.
3. Open a local repository with **⌘O**, then **Open** a branch from the branch browser to create or reuse its worktree.
4. Open that folder in your editor or AI tool. Repeat for another task to work in parallel, and use the graph and diffs to review the results.

**⌘F** searches loaded commits · **⌘R** refreshes · **⌘-click two commits** compares them.

The app uses your installed `/usr/bin/git` and existing Git/SSH credentials. Preferences and action rankings stay on your Mac. No account is required; there is no cloud sync or telemetry. The downloadable app is locally signed and is not notarized by Apple.

## Small app. Real Git.

Inspired by the compact workflow of VS Code's Git Graph, built independently with Swift and AppKit. No extension code or assets are reused. GitGraph Lite brings worktree management, history and visual diffs together for parallel development with AI, alongside your editor and other Git tools.

[User & developer guide](docs/guide.md) · [Performance measurements](docs/performance-0.10.7.md) · [All versions & downloads](HISTORY.md) · [Build from source](docs/guide.md#build-and-test) · [MIT License](LICENSE)
