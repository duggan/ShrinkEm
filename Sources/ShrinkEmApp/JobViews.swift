// The queue's toolbar button and the popover it opens.
// Both observe WorkQueue directly, so progress ticks redraw only these views.

import SwiftUI
import ShrinkEmKit

/// The queue's toolbar button: a tray icon with a progress ring while a job runs (a
/// spinner while Photos waits for a delete confirmation). The Dock badge and the
/// tooltip carry the count of videos left.
struct QueueToolbarButton: View {
    @ObservedObject var queue: WorkQueue
    @State private var showQueue = false

    var body: some View {
        Button {
            showQueue.toggle()
        } label: {
            QueueIcon(queue: queue)
        }
        .help(QueueIcon.status(queue))
        .accessibilityLabel("Queue")
        .accessibilityValue(QueueIcon.status(queue))
        .popover(isPresented: $showQueue, arrowEdge: .bottom) {
            QueuePopover(queue: queue)
        }
    }
}

struct QueueIcon: View {
    @ObservedObject var queue: WorkQueue

    var body: some View {
        let job = queue.current
        ZStack {
            if let job {
                Circle().stroke(.secondary.opacity(0.25), lineWidth: 2.5)
                if job.state == .deleting {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().trim(from: 0, to: max(0.03, job.overall))
                        .stroke(Brand.mintDeep, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: job.overall)
                    Image(systemName: job.isShrink ? "arrow.down.right.and.arrow.up.left" : "folder")
                        .font(.system(size: 8, weight: .bold))
                }
            } else {
                Image(systemName: queue.jobs.isEmpty ? "tray" : "tray.full")
                    .font(.system(size: 14))
                if let last = queue.jobs.last(where: { $0.state == .finished }), !last.failures.isEmpty {
                    Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 8, y: -7)
                }
            }
        }
        .frame(width: 20, height: 20)
    }

    /// The tooltip and accessibility value: what the queue is doing.
    static func status(_ queue: WorkQueue) -> String {
        if let job = queue.current {
            if job.state == .deleting { return "Waiting for you to confirm the deletion in Photos" }
            var s = "\(job.isShrink ? "Shrinking" : "Moving") \(job.index) of \(job.items.count): \(job.name) · \(Int(job.overall * 100))%"
            if queue.waitingCount > 0 { s += " · \(queue.waitingCount) more job\(queue.waitingCount == 1 ? "" : "s") waiting" }
            return s
        }
        if let last = queue.jobs.last(where: { $0.state == .finished }) { return JobRow.headline(last) }
        return "Queue: nothing waiting"
    }
}

struct QueuePopover: View {
    @ObservedObject var queue: WorkQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue").font(.headline)
                Spacer()
                Button("Clear Finished") { queue.clearFinished() }
                    .disabled(!queue.jobs.contains { !$0.isActive })
            }
            .padding(12)
            Divider()
            if queue.jobs.isEmpty {
                Text("Nothing in the queue. Move to Folder and Shrink jobs wait here while you keep reviewing.")
                    .foregroundStyle(.secondary).padding(16)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(queue.jobs) { job in
                            JobRow(job: job, queue: queue).padding(12)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 460)
            }
        }
        .frame(width: 440)
    }
}

struct JobRow: View {
    let job: Job
    let queue: WorkQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.title).fontWeight(.medium).lineLimit(2)
                Spacer()
                if job.dryRun { Text("Test run").font(.caption).foregroundStyle(.secondary) }
            }
            switch job.state {
            case .waiting:
                HStack {
                    Text("Waiting · \(fmtBytes(job.totalBytes))").foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { queue.cancel(job.id) }
                }
            case .running:
                Text("\(job.isShrink ? "Shrinking" : "Saving") \(job.index) of \(job.items.count): \(job.name)")
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                ProgressView(value: job.fileProgress) { Text("This video").font(.caption) }
                ProgressView(value: job.overall) {
                    Text("Overall · \(fmtBytes(job.doneBytes)) of \(fmtBytes(job.totalBytes))").font(.caption)
                }
                HStack {
                    Spacer()
                    if job.cancelRequested {
                        Text("Cancelling…").foregroundStyle(.secondary)
                    } else {
                        Button(job.stopRequested ? "Stopping after this video…" : "Stop After This Video") {
                            queue.stopAfterCurrent(job.id)
                        }
                        .disabled(job.stopRequested)
                        .help("Finish the video in progress, then stop.")
                        Button("Cancel") { queue.cancel(job.id) }
                            .help(job.done > 0
                                  ? "Stop now. The \(job.done) video\(job.done == 1 ? "" : "s") already done will still be finished, and Photos asks before deleting \(job.done == 1 ? "its original" : "their originals")."
                                  : "Stop now. Nothing has been changed in Photos yet.")
                    }
                }
            case .deleting:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Confirm the deletion in the Photos dialog.").foregroundStyle(.secondary)
                }
            case .finished:
                summary
            case .cancelled:
                Text("Cancelled. Nothing was changed.").foregroundStyle(.secondary)
            }
        }
    }

    /// One line for the tooltip and summaries.
    static func headline(_ job: Job) -> String {
        let saved = job.doneOriginalBytes - job.newBytes
        if job.state == .cancelled { return "Cancelled. Nothing was changed." }
        if job.dryRun { return "Test run finished: \(job.done) of \(job.items.count) done." }
        if job.done > 0 && job.deleted {
            return job.isShrink ? "Freed \(fmtBytes(saved))."
                : "Moved \(job.done) video\(job.done == 1 ? "" : "s") (\(fmtBytes(job.doneOriginalBytes))) to \(job.folder?.lastPathComponent ?? "the folder")."
        }
        if job.done > 0 { return job.isShrink ? "Added smaller copies; originals not deleted." : "Saved copies; originals not deleted." }
        return job.isShrink ? "Nothing was shrunk." : "Nothing was moved."
    }

    @ViewBuilder var summary: some View {
        let saved = job.doneOriginalBytes - job.newBytes
        let n = job.done
        if job.dryRun {
            Label("Test run: \(n) of \(job.items.count) done. Nothing changed in Photos.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else if n > 0 && job.deleted {
            Label(Self.headline(job), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text(job.isShrink
                 ? "\(n) video\(n == 1 ? "" : "s") shrunk, \(fmtBytes(job.doneOriginalBytes)) → \(fmtBytes(job.newBytes)). Date, location and albums stay. The originals are in Recently Deleted for 30 days; the space comes back when Photos empties it, or when you do."
                 : "Each copy was checked against the original. The videos are in Recently Deleted for 30 days; the space comes back when Photos empties it, or when you do.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if job.isShrink, let folder = job.folder {
                Label("The full-quality originals are in \(folder.lastPathComponent), each checked against Photos.", systemImage: "externaldrive.fill")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        } else if n > 0 {
            Label(job.isShrink ? "Added \(n) smaller cop\(n == 1 ? "y" : "ies"), but the originals weren't deleted"
                               : "Saved \(n) video\(n == 1 ? "" : "s"), but they were not deleted from Photos",
                  systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(job.isShrink
                 ? "The deletion was cancelled or failed, so Photos now has both versions. Delete the originals yourself to save \(fmtBytes(saved))."
                 : "The deletion was cancelled or failed, so the copies are in the folder and the originals are still in Photos.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Label(Self.headline(job), systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
        if job.cancelRequested {
            Text("Cancelled during \(job.name), which was left as it was\(job.index < job.items.count ? ", along with the videos after it" : "").")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if job.stopRequested && job.index < job.items.count {
            Text("Stopped early. The videos after \(job.name) weren't touched.").font(.callout).foregroundStyle(.secondary)
        }
        if !job.failures.isEmpty {
            Text(job.isShrink ? "\(job.failures.count) skipped or failed (originals untouched):"
                              : "\(job.failures.count) couldn't be saved and \(job.failures.count == 1 ? "was" : "were") left in Photos:").font(.subheadline)
            ScrollView {
                Text(job.failures.joined(separator: "\n")).font(.caption).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 100)
        }
        if let folder = job.folder, n > 0 {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        }
    }
}
