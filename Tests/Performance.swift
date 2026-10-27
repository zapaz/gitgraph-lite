// This file is appended to the real Controller sources by the benchmark script.
let perfArgs = CommandLine.arguments
func perfOption(_ name: String, _ fallback: String) -> String {
    guard let i = perfArgs.firstIndex(of: name), perfArgs.indices.contains(i+1) else { return fallback }
    return perfArgs[i+1]
}
let perfPath = perfOption("--repo", "")
let perfOutput = perfOption("--output", "performance.json")
guard !perfPath.isEmpty, let perfCount = Int(perfOption("--iterations", "5")), perfCount > 0 else {
    fputs("Usage: benchmark-performance.sh REPOSITORY [OUTPUT_JSON] [ITERATIONS]\n", stderr); exit(2)
}
func perfTime(_ work: () throws -> Void) rethrows -> Double {
    let start = ProcessInfo.processInfo.systemUptime
    try work(); return (ProcessInfo.processInfo.systemUptime-start)*1000
}
func perfMedian(_ values: [Double]) -> Double { values.sorted()[values.count/2] }
_ = NSApplication.shared
let perfController = Controller(); perfController.timer?.invalidate()
var perfSamples: [String:[Double]] = [:]
var perfRepo: Repository!
for _ in 0..<perfCount {
    perfSamples["load_500_ms", default: []].append(try perfTime { perfRepo = try Git.load(at: perfPath, branchNames: nil, pins: [], limit: 500) })
}
perfController.repository = perfRepo; perfController.commits = perfRepo.commits
perfController.graph = GraphLayout.make(perfRepo.commits)
perfController.applySearch(selected: [])
for selection in [Set(["main"]), Set(["prod"]), Set(["main","prod"]), Set(["main"]), Set(["prod"])] {
    perfController.branchSelection = selection
    let duration = perfTime {
        perfController.branchSelectionChanged()
        let deadline = Date().addingTimeInterval(60)
        while perfController.loading && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
        precondition(!perfController.loading && perfController.repository != nil)
        perfController.table.layoutSubtreeIfNeeded()
    }
    perfSamples["branch_filter_ms", default: []].append(duration)
}
// Fixed real input, independent of the branch filter result or the default fold preference.
let perfData = try Git.run(["log", "--all", "--date-order", "-z", "--format=%H%x00%P%x00%an%x00%ct%x00%D%x00%s", "--max-count=10000", "--"], at: perfPath)
let perfCommits = Git.parseLog(perfData)
for size in Set([min(500, perfCommits.count), min(10000, perfCommits.count)]).sorted() {
    perfController.commits = Array(perfCommits.prefix(size)); perfController.graph = GraphLayout.make(perfController.commits)
    perfController.groupsFolded = true; perfController.search.stringValue = ""; perfController.applySearch(selected: [])
    for _ in 0..<10 {
        let duration = perfTime {
            for query in ["f", "fi", "fix", "fix:", "docs", "zapaz", "market", "not-present-9281", ""] {
                perfController.search.stringValue = query; perfController.applySearch(selected: []); perfController.table.layoutSubtreeIfNeeded()
            }
        }
        perfSamples["search_\(size)_sequence_ms", default: []].append(duration)
    }
}
let result: [String:Any] = ["repository":perfPath,"commitInputCount":perfCommits.count,"worktreeCount":perfRepo.worktrees.count,"samples":perfSamples,"median_ms":perfSamples.mapValues(perfMedian)]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
try data.write(to: URL(fileURLWithPath: perfOutput))
print(String(decoding: data, as: UTF8.self)); perfController.window?.close()
