<div align="center">
  <img src="Assets/AppIcon.png" width="80" alt="GitGraph Lite icon">
  <h1>GitGraph Lite</h1>
  <p><strong>See the whole history. Stay on the right branch.</strong></p>
  <p>A focused, native macOS Git browser with a colourful graph, visual diffs<br>and a dedicated workspace for every branch you open.</p>
  <p>
    <a href="https://github.com/zapaz/gitgraph-lite/releases/latest"><strong>Download for macOS</strong></a>
    &nbsp;·&nbsp; <a href="docs/guide.md">User guide</a>
    &nbsp;·&nbsp; <a href="HISTORY.md">Release history</a>
  </p>
  <p><sub>macOS 13+ · Apple Silicon · Native AppKit · MIT licensed</sub></p>
</div>

<a href="docs/screenshots/branch-actions.png"><img src="docs/screenshots/branch-actions.png" width="1440" alt="GitGraph Lite showing a complex five-branch history with merges, tags, worktrees, a visual diff and the action menu for feature/search"></a>

<p align="center"><sub>A real app capture with the fictional Atlas sample repository. Click any image to view it full size.</sub></p>

## Your history, without the clutter

- **Follow every branch.** Trace merges across a coloured graph. See local branches, origin refs, tags and worktrees in context.
- **Keep each workspace on its branch.** Open a branch to reuse its dedicated worktree—or create one automatically. Your other workspace keeps its branch and local changes.
- **Understand the change.** Inspect side-by-side or unified diffs with line numbers and word highlights. Browse changed files as a folder tree, or compare two commits with ⌘-click.
- **Act on exactly what you click.** Short menus for commits, branches, tags and worktrees. Push one branch, publish one tag, or pull into the selected branch's workspace with fast-forward protection.
- **Make room for what matters.** Filter several branches, pin the important ones and fold long commit chains. The graph refreshes after changes made in your other Git tools.

## Take a closer look

<p align="center">
  <a href="docs/screenshots/diff-side-by-side.png" title="Side-by-side diffs"><img src="docs/screenshots/diff-side-by-side.png" width="190" alt="Side-by-side diff with word highlights and a changed-file tree"></a>
  <a href="docs/screenshots/diff-unified.png" title="Unified diff · dark mode"><img src="docs/screenshots/diff-unified.png" width="190" alt="Unified diff in dark mode with old and new line numbers"></a>
  <a href="docs/screenshots/branch-picker.png" title="Branches and pins"><img src="docs/screenshots/branch-picker.png" width="190" alt="Multi-branch picker with local and origin refs, branch pins and workspace state"></a>
  <a href="docs/screenshots/worktrees.png" title="Dedicated workspaces"><img src="docs/screenshots/worktrees.png" width="190" alt="Worktree manager with three dedicated workspaces, their branches, paths and clean or modified state"></a>
</p>

<p align="center"><sub>Side-by-side diffs · Unified in dark mode · Branches &amp; pins · Dedicated workspaces</sub></p>

## Get started

1. **[Download the latest release](https://github.com/zapaz/gitgraph-lite/releases/latest)** for Apple Silicon.
2. Unzip it and drag **GitGraph Lite.app** into **Applications**.
3. Open a local repository with **⌘O**. Follow its history, inspect a change or open a branch's workspace.

**⌘F** searches loaded commits · **⌘R** refreshes · **⌘-click two commits** compares them.

The app uses your installed `/usr/bin/git` and existing Git/SSH credentials. Preferences and action rankings stay on your Mac. No account is required; there is no cloud sync or telemetry. The downloadable app is locally signed and is not notarized by Apple.

## Small app. Real Git.

Inspired by the compact workflow of VS Code's Git Graph, built independently with Swift and AppKit. No extension code or assets are reused. GitGraph Lite focuses on history, diffs and branch/worktree navigation, alongside your editor and other Git tools.

[User & developer guide](docs/guide.md) · [Performance measurements](docs/performance-0.10.7.md) · [All versions & downloads](HISTORY.md) · [Build from source](docs/guide.md#build-and-test) · [MIT License](LICENSE)
