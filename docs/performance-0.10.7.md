# Loading and filtering performance — 0.10.7

Measured on an Apple M1 Mac running macOS 27.2 on 27 October 2026 against the unchanged 0.10.6 executable. Both versions used the same isolated snapshot of runbot, commit `28095f629db2af339b757cf406e50a97baea7a2f`, with 2,529 reachable commits and six fixed worktrees. This avoids changes from other Git tools during the comparison.

| Measured operation | 0.10.6 | 0.10.7 | Speedup |
| --- | ---: | ---: | ---: |
| Full repository load, 500 commits | 4627.4 ms | 1227.6 ms | 3.77× |
| Branch filter, including AppKit update/layout | 3067.2 ms | 143.8 ms | 21.33× |
| Search sequence, 500 commits | 101.4 ms | 46.5 ms | 2.18× |
| Search sequence, 2,529 commits | 177.9 ms | 57.5 ms | 3.09× |

## Method and limits

The table reports median wall-clock time: five complete repository loads, five branch-filter changes, and ten nine-query search sequences. Queries were `f`, `fi`, `fix`, `fix:`, `docs`, `zapaz`, `market`, `not-present-9281`, then empty. Searches include applying results to the real AppKit table and completing layout. Branch-filter measurements include Git loading, preparation, and AppKit layout; full repository loading measures `Git.load`, rather than process launch or display-server paint time.

Both executables use an optimized core and `-O` compilation of the real app/controller sources. The first executable is frozen from 0.10.6. No filesystem caches were evicted. Repeated search sequences exercise the bounded recent-query cache as well as the search index and retained table rows. These results exceed the 2× target on these measured median workloads; they are not a guarantee for every repository or a cold start.

The first search sequences, before warming the recent-query cache, were 102.6 → 58.4 ms for 500 commits and 173.2 → 95.8 ms for 2,529 commits. Raw samples and the comparison metadata are in [performance-0.10.7.json](performance-0.10.7.json).

## Changes

- Wake directly when Git exits instead of polling its process run loop.
- Resolve the worktree Git directory once when checking pending operations.
- Read independent worktree statuses concurrently, with at most four scans. If another tool removes a worktree mid-scan and registration changes, retry once.
- Reuse repository metadata for branch filtering and Load more after validating the refs/HEAD/operation signature and current worktree registration. External reference or worktree changes trigger a full reload. Statuses continue refreshing through the normal polling/manual refresh path; write operations still perform fresh validation.
- Prepare graph, groups, labels and normalized search text off the main thread.
- Cache history groups, one folded projection, and up to 16 recent search results. Replacing history invalidates these caches.
- Apply search row insertions/removals without reconstructing views for surviving commits.
- Keep loaded/in-flight immutable commit details while their selection stays the same, and avoid resetting empty file/diff panels on every keystroke.

## Reproduce

Build the release app, then run:

```sh
GITGRAPH_BUILD_ROOT=/path/to/build zsh build-app.sh
GITGRAPH_BUILD_ROOT=/path/to/build zsh Tests/benchmark-performance.sh /path/to/repository /path/to/results.json 5
```

Use a disposable, stable copy when other tools are modifying the repository. The script requires a macOS desktop session and writes the raw timing samples as JSON. It does not create commits or switch branches in the measured repository; normal repository loading may update GitGraph Lite's private workspace-association metadata.
