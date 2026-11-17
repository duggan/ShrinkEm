// The background queue: Move to Folder and Shrink jobs run one after another while
// the window stays usable. Each job deletes its verified originals when it finishes,
// so Photos still asks before anything is removed.
//
// This is its own ObservableObject so that progress ticks only redraw the activity
// bar, not the whole window (the table can hold thousands of rows).

import SwiftUI
import Photos
import ShrinkEmKit

struct Job: Identifiable {
    enum Kind {
        case move(folder: URL)
        case shrink(ShrinkSettings)
    }
    enum State: Equatable { case waiting, running, deleting, finished, cancelled }

    let id = UUID()
    let kind: Kind
    let items: [VideoItem]
    var state = State.waiting
    /// Test hook only: do all the work but never import into or delete from Photos.
    var dryRun = false

    var index = 0                    // 1-based, the video being worked on
    var name = ""
    var doneBytes: Int64 = 0
    var currentBytes: Int64 = 0
    var fileProgress = 0.0
    var done = 0                     // videos saved (move) or replaced (shrink)
    var doneOriginalBytes: Int64 = 0
    var newBytes: Int64 = 0          // shrink: size of the replacement copies
    var deleted = false
    var stopRequested = false        // finish the current video, then stop
    var cancelRequested = false      // stop now; the current video is left untouched
    var failures: [String] = []

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var isActive: Bool { state == .waiting || state == .running || state == .deleting }
    var overall: Double {
        let total = totalBytes
        return total > 0 ? min(1, (Double(doneBytes) + fileProgress * Double(currentBytes)) / Double(total)) : 0
    }
    var isShrink: Bool { if case .shrink = kind { return true } else { return false } }
    var folder: URL? {
        switch kind {
        case .move(let f): return f
        case .shrink(let s): return s.archiveFolder
        }
    }
    var title: String {
        let n = "\(items.count) video\(items.count == 1 ? "" : "s")"
        switch kind {
        case .move(let f): return "Move \(n) to \(f.lastPathComponent)"
        case .shrink(let s):
            return "Shrink \(n) to \(s.maxHeight)p \(s.maxFPS) fps" + (s.archiveFolder.map { ", originals to \($0.lastPathComponent)" } ?? "")
        }
    }
}

@MainActor
final class WorkQueue: ObservableObject {
    @Published private(set) var jobs: [Job] = []
    private unowned let library: Library
    private var runner: Task<Void, Never>?
    private var tokens: [UUID: CancelToken] = [:]

    init(library: Library) { self.library = library }

    var isWorking: Bool { jobs.contains { $0.isActive } }
    var current: Job? { jobs.first { $0.state == .running || $0.state == .deleting } }
    var waitingCount: Int { jobs.filter { $0.state == .waiting }.count }
    var remainingVideos: Int {
        jobs.reduce(0) { n, j in
            switch j.state {
            case .waiting: return n + j.items.count
            case .running, .deleting: return n + max(0, j.items.count - j.index + 1)
            default: return n
            }
        }
    }

    // MARK: Adding and cancelling

    /// Queues `ids` (minus any already in a job). Returns how many were queued.
    @discardableResult
    func enqueue(_ kind: Job.Kind, ids: Set<String>, dryRun: Bool = false) -> Int {
        let busy = library.busyIDs
        // Biggest first, matching the list's default order.
        let items = library.items.filter { ids.contains($0.id) && !busy.contains($0.id) }
            .sorted { $0.bytes > $1.bytes }
        guard !items.isEmpty else { return 0 }
        var job = Job(kind: kind, items: items)
        job.dryRun = dryRun
        jobs.append(job)
        refreshBusy()
        startRunner()
        return items.count
    }

    /// A waiting job is dropped. A running one stops now: the video in progress is left
    /// as it was (partial files removed), and the videos it already finished are
    /// completed, so Photos asks before deleting their originals. (Abandoning finished
    /// shrinks would leave both versions in Photos.)
    func cancel(_ id: UUID) {
        mutate(id) { job in
            switch job.state {
            case .waiting: job.state = .cancelled
            case .running: job.cancelRequested = true
            default: break
            }
        }
        tokens[id]?.cancel()
        refreshBusy()
    }

    /// Lets the video in progress finish, then stops the job.
    func stopAfterCurrent(_ id: UUID) {
        mutate(id) { if $0.state == .running { $0.stopRequested = true } }
    }

    func clearFinished() {
        jobs.removeAll { !$0.isActive }
    }

    // MARK: Running

    private func startRunner() {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            await self?.runAll()
            self?.runner = nil
        }
    }

    private func runAll() async {
        // Keep long jobs at full speed when the window is in the background, and
        // stop the Mac idling to sleep mid-job.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Moving or shrinking videos")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        while let next = jobs.first(where: { $0.state == .waiting }) {
            mutate(next.id) { $0.state = .running }
            let token = CancelToken()
            tokens[next.id] = token
            switch next.kind {
            case .move(let folder): await runMove(next.id, folder: folder, cancel: token)
            case .shrink(let settings): await runShrink(next.id, settings: settings, cancel: token)
            }
            tokens[next.id] = nil
            mutate(next.id) { $0.state = $0.cancelRequested && $0.done == 0 ? .cancelled : .finished }
            refreshBusy()
            updateDockBadge()
        }
        updateDockBadge()
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    /// The asset as Photos has it now, or nil if it was deleted meanwhile.
    private func liveAsset(_ item: VideoItem) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject
    }

    private func begin(_ id: UUID, _ i: Int, _ item: VideoItem) {
        mutate(id) {
            $0.index = i + 1
            $0.name = item.filename
            $0.currentBytes = item.bytes
            $0.fileProgress = 0
        }
        updateDockBadge()
    }

    private func finishItem(_ id: UUID, _ item: VideoItem) {
        mutate(id) {
            $0.doneBytes += item.bytes
            $0.fileProgress = 0
        }
    }

    /// Progress callbacks arrive from PhotoKit's threads, often many times a second.
    /// Hop to the main actor and skip changes too small to see.
    private nonisolated func reporter(_ id: UUID, scale: Double = 1, offset: Double = 0) -> @Sendable (Double) -> Void {
        { [weak self] p in
            Task { @MainActor in
                guard let self, let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
                let value = offset + scale * p
                if abs(self.jobs[i].fileProgress - value) >= 0.005 || value >= 1 { self.jobs[i].fileProgress = value }
            }
        }
    }

    private func shouldStop(_ id: UUID) -> Bool {
        guard let job = jobs.first(where: { $0.id == id }) else { return true }
        return job.stopRequested || job.cancelRequested
    }

    private func isCancellation(_ error: Error, _ token: CancelToken) -> Bool {
        token.isCancelled || error is CancellationError
    }

    private func runMove(_ id: UUID, folder: URL, cancel: CancelToken) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        var exported = Set<String>()
        for (i, item) in job.items.enumerated() {
            if shouldStop(id) { break }
            begin(id, i, item)
            do {
                guard let asset = liveAsset(item) else { throw Library.ExportError("No longer in Photos") }
                try await Library.export(asset, to: folder, cancel: cancel, progress: reporter(id))
                exported.insert(item.id)
                mutate(id) { $0.done += 1; $0.doneOriginalBytes += item.bytes }
            } catch where isCancellation(error, cancel) {
                break   // export already removed this video's partial files
            } catch {
                mutate(id) { $0.failures.append("\(item.filename): \(error.localizedDescription)") }
            }
            finishItem(id, item)
        }
        // Only videos whose files were written and verified get deleted.
        if !exported.isEmpty && !job.dryRun {
            mutate(id) { $0.state = .deleting }
            let ok = await library.delete(exported)
            mutate(id) { $0.deleted = ok }
            if ok { library.selectionInvalidated.formUnion(exported) }
        }
    }

    private func runShrink(_ id: UUID, settings: ShrinkSettings, cancel: CancelToken) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let tmp = Library.shrinkTempDir()
        let encodeShare = settings.archiveFolder == nil ? 1.0 : 0.5
        var replaced: [String: String] = [:]   // original ID → new ID

        for (i, item) in job.items.enumerated() {
            if shouldStop(id) { break }
            begin(id, i, item)
            let url = tmp.appendingPathComponent(UUID().uuidString + ".mov")
            do {
                guard let asset = liveAsset(item) else { throw Library.ShrinkError("No longer in Photos") }
                _ = try await Library.reencode(asset, settings: settings, to: url, cancel: cancel,
                                               progress: reporter(id, scale: encodeShare))
                let newSize = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                if !ShrinkSettings.worthReplacing(original: item.bytes, copy: newSize) {
                    throw Library.ShrinkError("Only \(fmtBytes(item.bytes)) → \(fmtBytes(newSize)) — not worth replacing")
                }
                // Archive the full-quality original (and any edited version) before
                // touching Photos. If that fails, the video is left exactly as it was.
                if let folder = settings.archiveFolder {
                    try await Library.export(asset, to: folder, cancel: cancel,
                                             progress: reporter(id, scale: 0.5, offset: 0.5))
                }
                // Last chance to cancel: from here the copy goes into Photos.
                try cancel.check()
                if !job.dryRun {
                    let base = (item.filename as NSString).deletingPathExtension
                    let newID = try await Library.importReplacement(for: asset, fileURL: url,
                                                                    filename: (base.isEmpty ? "Video" : base) + ".mov")
                    replaced[item.id] = newID
                    library.addItems(ids: [newID])   // show the new copy straight away
                }
                mutate(id) { $0.done += 1; $0.doneOriginalBytes += item.bytes; $0.newBytes += newSize }
            } catch where isCancellation(error, cancel) {
                try? FileManager.default.removeItem(at: url)
                break
            } catch {
                mutate(id) { $0.failures.append("\(item.filename): \(error.localizedDescription)") }
            }
            try? FileManager.default.removeItem(at: url)   // gone already if Photos moved it in
            finishItem(id, item)
        }

        if !replaced.isEmpty {
            mutate(id) { $0.state = .deleting }
            let ok = await library.delete(Set(replaced.keys))
            mutate(id) { $0.deleted = ok }
            if ok {
                library.selectionInvalidated.formUnion(replaced.keys)
                // Carry "kept" marks over to the replacements.
                for (old, new) in replaced where library.kept.contains(old) {
                    library.kept.remove(old)
                    library.kept.insert(new)
                }
                UserDefaults.standard.set(Array(library.kept), forKey: "kept")
            }
        }
    }

    /// Test hook only: show these jobs as-is (for offscreen renders of the queue UI).
    func previewJobs(_ sample: [Job]) { jobs = sample }

    // MARK: Helpers

    private func mutate(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }

    /// Recomputes the busy set on the library (which the table reads) only when it changes.
    private func refreshBusy() {
        // A running job's finished videos stay busy too, until it deletes them.
        let busy = Set(jobs.filter(\.isActive).flatMap { $0.items.map(\.id) })
        if busy != library.busyIDs { library.busyIDs = busy }
    }

    private func updateDockBadge() {
        let n = remainingVideos
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
    }
}

// MARK: - Test hook

extension Library {
    /// `SHRINKEM_QUEUETEST_DIR=<dir>`: queues dry-run jobs on real videos (files are
    /// written to `<dir>`, nothing is imported into or deleted from Photos), checks the
    /// queue's rules, measures the longest main-thread stall, logs, and quits.
    func queueSelfTest(_ dir: URL) async {
        var log = ""
        try? await Task.sleep(nanoseconds: 2_000_000_000)   // let the window's first render settle
        func note(_ s: String) { log += "\(String(format: "%7.2f", Date().timeIntervalSince(t0)))s  \(s)\n" }
        let t0 = Date()

        // Main-thread responsiveness: a 20 ms timer; any gap well over that is a stall.
        var last = Date(), worst = 0.0, stalls: [String] = []
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let now = Date(), gap = now.timeIntervalSince(last)
            worst = max(worst, gap); last = now
            if gap > 0.06 { stalls.append(String(format: "%.0fms at %.2fs", gap * 1000, now.timeIntervalSince(t0))) }
        }

        let small = items.filter { $0.duration > 3 && $0.bytes > 0 }.sorted { $0.bytes < $1.bytes }
        let fourK = items.filter { min($0.width, $0.height) >= 2160 && $0.duration > 3 && !Library.isSlowMo($0.asset) }
            .sorted { $0.bytes < $1.bytes }
        let wantBig = ProcessInfo.processInfo.environment["SHRINKEM_QUEUETEST_BIG"] != nil
        guard small.count >= 4, let big = wantBig ? fourK.first(where: { $0.bytes > 80_000_000 }) : fourK.first
        else { note("not enough videos"); return }
        let moveIDs: Set<String> = [small[0].id, small[1].id]

        let q = queue
        let folder = dir.appendingPathComponent("moved")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        note("queued move: \(q.enqueue(.move(folder: folder), ids: moveIDs, dryRun: true))")
        note("queued shrink: \(q.enqueue(.shrink(ShrinkSettings(maxHeight: 1080, maxFPS: 60)), ids: [big.id], dryRun: true))")
        note("re-queue same videos (expect 0): \(q.enqueue(.move(folder: folder), ids: moveIDs, dryRun: true))")
        note("queued third: \(q.enqueue(.move(folder: folder), ids: [small[2].id], dryRun: true))")
        note("busy before run: \(busyIDs.count) (expect 4)")
        if let third = q.jobs.last { q.cancel(third.id) }
        note("after cancelling third: busy \(busyIDs.count) (expect 3), states \(q.jobs.map { "\($0.state)" })")

        var seen = ""
        while q.isWorking {
            let states = q.jobs.map { "\($0.state)" }.joined(separator: ",")
            if states != seen { note("states: \(states)"); seen = states }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        note("states: \(q.jobs.map { "\($0.state)" }.joined(separator: ","))")

        // Cancelling running jobs: how fast they stop, and what they leave behind.
        func files(_ dir: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() }
        func waitUntil(_ limit: Double, _ cond: () -> Bool) async {
            let start = Date()
            while !cond() && Date().timeIntervalSince(start) < limit { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        func cancelTest(_ label: String, _ kind: Job.Kind, _ ids: Set<String>, folder: URL?,
                        when: @escaping (Job) -> Bool) async {
            let tmpBefore = files(Library.shrinkTempDir())
            q.enqueue(kind, ids: ids, dryRun: true)
            guard let id = q.jobs.last?.id else { return }
            await waitUntil(60) { q.jobs.first { $0.id == id }.map(when) ?? true }
            let at = q.jobs.first { $0.id == id }!
            note("\(label): cancelling at video \(at.index), \(Int(at.fileProgress * 100))% of it")
            let t = Date()
            q.cancel(id)
            await waitUntil(30) { !(q.jobs.first { $0.id == id }?.isActive ?? false) }
            let job = q.jobs.first { $0.id == id }!
            note(String(format: "\(label): stopped in %.2fs, state \(job.state), done \(job.done), failures \(job.failures.count)", Date().timeIntervalSince(t)))
            if let folder { note("\(label): folder now \(files(folder))") }
            note("\(label): temp files left \(Set(files(Library.shrinkTempDir())).subtracting(tmpBefore).count)")
        }
        let large = items.filter { $0.bytes > 150_000_000 && $0.bytes < 700_000_000 && $0.duration > 3 }.min { $0.bytes < $1.bytes }
        if let large {
            let f1 = dir.appendingPathComponent("cancel-move")
            try? FileManager.default.createDirectory(at: f1, withIntermediateDirectories: true)
            await cancelTest("move \(fmtBytes(large.bytes))", .move(folder: f1), [large.id], folder: f1) { $0.state == .running && $0.fileProgress > 0.05 }
            let f3 = dir.appendingPathComponent("cancel-second")
            try? FileManager.default.createDirectory(at: f3, withIntermediateDirectories: true)
            // Biggest first, so the large video goes first; cancel during the small one.
            let tiny = small[3]
            await cancelTest("move two, cancel on second", .move(folder: f3), [large.id, tiny.id], folder: f3) { $0.index == 2 && $0.state == .running }
        } else { note("no 150–700 MB video for the move cancel test") }
        await cancelTest("shrink \(fmtBytes(big.bytes))", .shrink(ShrinkSettings(maxHeight: 1080, maxFPS: 60)), [big.id], folder: nil) { $0.state == .running && $0.fileProgress > 0.3 }
        note("busy at end: \(busyIDs.count) (expect 0)")
        timer.invalidate()
        for job in q.jobs {
            note("\(job.title): done \(job.done)/\(job.items.count), failures \(job.failures), headline: \(JobRow.headline(job))")
        }
        note("busy after run: \(busyIDs.count) (expect 0)")
        note("files written: \((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])")
        note(String(format: "longest main-thread gap: %.0f ms", worst * 1000))
        note("gaps over 60 ms: \(stalls)")
        try? log.write(to: dir.appendingPathComponent("queuetest.log"), atomically: true, encoding: .utf8)
        exit(0)
    }
}

// MARK: - Stall test hook

extension Library {
    static let testSelect = Notification.Name("ShrinkEmTestSelect")

    /// `SHRINKEM_STALLTEST_DIR=<dir>` (optionally `SHRINKEM_STALLTEST_TARGET=<folder>`, e.g.
    /// a network share): times the main-thread work behind queueing many videos, idle
    /// and while a dry-run move streams a large video to the target. Logs and quits.
    func stallSelfTest(_ dir: URL) async {
        var log = ""
        let t0 = Date()
        func note(_ s: String) { log += String(format: "%7.2fs  ", Date().timeIntervalSince(t0)) + s + "\n" }
        func time(_ label: String, _ body: () -> Void) {
            let t = Date(); body(); note(String(format: "%-34@ %7.1f ms", label as NSString, Date().timeIntervalSince(t) * 1000))
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        var last = Date(), stalls: [String] = []
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let now = Date(), gap = now.timeIntervalSince(last); last = now
            if gap > 0.1 { stalls.append(String(format: "%.0fms at %.2fs", gap * 1000, now.timeIntervalSince(t0))) }
        }
        let target = ProcessInfo.processInfo.environment["SHRINKEM_STALLTEST_TARGET"].map { URL(fileURLWithPath: $0) }
            ?? dir.appendingPathComponent("target")
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let selection = Set(items.sorted { $0.bytes > $1.bytes }.dropFirst(5).prefix(300).map(\.id))
        let sortOrder = [KeyPathComparator(\VideoItem.bytes, order: .reverse)]

        func probes(_ phase: String) async {
            note("-- \(phase)")
            // The share is checked off the main thread now; time it, and watch the main
            // thread stay free while it runs.
            last = Date(); stalls.removeAll()
            let t = Date()
            let st = await Library.folderStatus(target)
            note(String(format: "folderStatus(target) off-main     %7.1f ms (reachable \(st.reachable)); main stalls meanwhile: \(stalls)", Date().timeIntervalSince(t) * 1000))
            time("bytes(300 selected) x3") { for _ in 0..<3 { _ = bytes(selection) } }
            time("rows: filter + sort") { _ = items.filter { !kept.contains($0.id) }.sorted(using: sortOrder) }
            time("timeline: MonthBucket.make") { _ = MonthBucket.make(items.lazy.map { (date: $0.sortDate, bytes: $0.bytes) }) }
            time("date controls: years, min, max") {
                let d = items.map(\.sortDate).filter { $0 != .distantPast }
                _ = Set(d.map { Calendar.current.component(.year, from: $0) }); _ = d.min(); _ = d.max()
            }
            time("PHAsset.fetch 1 by id") { _ = PHAsset.fetchAssets(withLocalIdentifiers: [items[0].id], options: nil).firstObject }
        }

        // The table's fast sort must order by the same key as the generic comparator.
        let columns: [(String, KeyPathComparator<VideoItem>, (VideoItem) -> String)] = [
            ("bytes", KeyPathComparator(\VideoItem.bytes), { "\($0.bytes)" }),
            ("duration", KeyPathComparator(\VideoItem.duration), { "\($0.duration)" }),
            ("mbPerMin", KeyPathComparator(\VideoItem.mbPerMin), { "\($0.mbPerMin)" }),
            ("sortDate", KeyPathComparator(\VideoItem.sortDate), { "\($0.sortDate)" }),
            ("pixels", KeyPathComparator(\VideoItem.pixels), { "\($0.pixels)" }),
            ("filename", KeyPathComparator(\VideoItem.filename), { $0.filename.lowercased() }),
        ]
        for (name, base, key) in columns {
            for order in [SortOrder.forward, .reverse] {
                var c = base; c.order = order
                let fast = ContentView.sorted(items, by: [c]).map(key)
                // Filenames deliberately sort as Finder does, not by raw String order.
                let slow = name == "filename"
                    ? items.sorted { let r = $0.filename.localizedStandardCompare($1.filename)
                                     return order == .forward ? r == .orderedAscending : r == .orderedDescending }.map(key)
                    : items.sorted(using: [c]).map(key)
                note("sort \(name) \(order == .forward ? "asc" : "desc"): \(fast == slow ? "same order" : "DIFFERENT")")
            }
        }
        await probes("idle")
        guard let large = items.filter({ $0.bytes > 150_000_000 && $0.bytes < 700_000_000 }).min(by: { $0.bytes < $1.bytes }) else {
            note("no large video"); return
        }
        let q = queue
        q.enqueue(.move(folder: target), ids: [large.id], dryRun: true)
        let start = Date()
        while (q.current?.fileProgress ?? 0) < 0.2 && Date().timeIntervalSince(start) < 60 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await probes("while moving \(fmtBytes(large.bytes)) to \(target.lastPathComponent)")
        note("-- selecting 300 rows in the list")
        last = Date(); stalls.removeAll()
        NotificationCenter.default.post(name: Library.testSelect, object: selection)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        note("stalls >100 ms in the 3 s after selecting: \(stalls)")
        note("-- queueing those 300 while the move runs")
        last = Date(); stalls.removeAll()
        time("enqueue(300)") { q.enqueue(.shrink(ShrinkSettings(maxHeight: 1080, maxFPS: 60)), ids: selection, dryRun: true) }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        note("stalls >100 ms in the 4 s after queueing: \(stalls)")
        for job in q.jobs where job.isActive { q.cancel(job.id) }
        while q.isWorking { try? await Task.sleep(nanoseconds: 100_000_000) }
        timer.invalidate()
        if ProcessInfo.processInfo.environment["SHRINKEM_STALLTEST_TARGET"] != nil { try? FileManager.default.removeItem(at: target) }
        try? log.write(to: dir.appendingPathComponent("stalltest.log"), atomically: true, encoding: .utf8)
        exit(0)
    }
}
