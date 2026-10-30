# Screenshot gallery

These are real captures of GitGraph Lite 0.11.0 running a fictional **Atlas** repository. The sample history contains five branches, multiple merges, a divergent origin ref, an unmerged experiment, two tags and three dedicated worktrees. Names, authors and code are demonstration data. No user repository content is shown.

- [Complex graph with branch actions](branch-actions.png)
- [Side-by-side diff](diff-side-by-side.png)
- [Unified diff, dark appearance](diff-unified.png)
- [Branch picker and pins](branch-picker.png)
- [Worktree manager](worktrees.png)

Captures use the production AppKit views and menus; the demonstration harness only supplies sample data and arranges the window, selection and appearance. See the [product page](../../README.md).

## Presentation artwork

The [product page](../../README.md) frames these captures with a shared navy, turquoise and violet design. The four preview cards use the same size and proportions so they form two columns on wider screens and stack on mobile. Diff cards show an enlarged crop; every image links to its complete original capture. The app interface and sample data have not been retouched.

The framed images live in [presentation/](presentation/). To regenerate them with Playwright and its Chromium browser available:

```sh
node docs/screenshots/presentation/render.cjs
```

For a Playwright installation outside the normal Node module search path, set `PLAYWRIGHT_MODULE` to that module's absolute path. The renderer only adds HTML/CSS framing around the existing captures; it adds no dependencies to the macOS app.
