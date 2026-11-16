// Progress and summary sheet shared by Move to Folder and Shrink.

import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers
import SlimreelKit

struct MoveSheet: View {
    @EnvironmentObject var lib: Library

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let m = lib.move {
                switch m.phase {
                case .exporting:
                    Text("\(m.kind == .shrink ? "Shrinking" : "Saving") \(m.index) of \(m.total)…").font(.headline)
                    Text(m.name).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    ProgressView(value: m.fileProgress) { Text("This file").font(.caption) }
                    ProgressView(value: m.overall) {
                        Text("Overall · \(fmtBytes(m.doneBytes)) of \(fmtBytes(m.totalBytes))").font(.caption)
                    }
                    HStack {
                        Spacer()
                        Button(m.stopRequested ? "Stopping after this file…" : "Stop After This File") {
                            lib.move?.stopRequested = true
                        }
                        .disabled(m.stopRequested)
                    }
                case .deleting:
                    Text(m.kind == .shrink
                         ? "Added \(m.exported) smaller cop\(m.exported == 1 ? "y" : "ies"). Deleting the originals…"
                         : "Saved \(m.exported) video\(m.exported == 1 ? "" : "s"). Deleting from Photos…").font(.headline)
                    ProgressView().controlSize(.small)
                    Text("Confirm the deletion in the Photos dialog.").foregroundStyle(.secondary)
                case .finished:
                    summary(m)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .interactiveDismissDisabled(lib.move?.phase != .finished)
    }

    @ViewBuilder func summary(_ m: Library.MoveProgress) -> some View {
        if m.kind == .shrink { shrinkSummary(m) } else { moveSummary(m) }
        if !m.failures.isEmpty {
            Text(m.kind == .shrink ? "\(m.failures.count) skipped or failed (originals untouched):"
                                   : "\(m.failures.count) couldn't be saved and were left in Photos:").font(.subheadline)
            ScrollView {
                Text(m.failures.joined(separator: "\n")).font(.caption).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        HStack {
            if m.kind == .move || m.archiveFolder != nil {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([m.folder]) }
                    .disabled(m.exported == 0)
            }
            Spacer()
            Button("Done") { lib.move = nil }.keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder func shrinkSummary(_ m: Library.MoveProgress) -> some View {
        let saved = m.exportedBytes - m.newBytes
        if m.exported > 0 && m.deleted {
            Label("Freed \(fmtBytes(saved)).", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
            Text("\(m.exported) video\(m.exported == 1 ? "" : "s") shrunk, \(fmtBytes(m.exportedBytes)) → \(fmtBytes(m.newBytes)). Date, location and albums stay. The originals are in Recently Deleted for 30 days; the space comes back when Photos empties it, or when you do.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let folder = m.archiveFolder {
                Label("The full-quality originals are in \(folder.lastPathComponent), each checked against Photos.", systemImage: "externaldrive.fill")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        } else if m.exported > 0 {
            Label("Added \(m.exported) smaller cop\(m.exported == 1 ? "y" : "ies"), but the originals weren't deleted", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text("The deletion was cancelled or failed, so Photos now has both versions. Delete the originals yourself to save \(fmtBytes(saved)).")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Nothing was shrunk", systemImage: "xmark.circle.fill").font(.headline).foregroundStyle(.red)
        }
    }

    @ViewBuilder func moveSummary(_ m: Library.MoveProgress) -> some View {
        if m.exported > 0 && m.deleted {
            Label("Moved \(m.exported) video\(m.exported == 1 ? "" : "s") (\(fmtBytes(m.exportedBytes))) to \(m.folder.lastPathComponent).", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
            Text("Each copy was checked against the original. The videos are in Recently Deleted for 30 days; the space comes back when Photos empties it, or when you do.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if m.exported > 0 {
            Label("Saved \(m.exported) video\(m.exported == 1 ? "" : "s"), but they were not deleted from Photos", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text("The deletion was cancelled or failed, so the copies are in the folder and the originals are still in Photos.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Nothing was moved", systemImage: "xmark.circle.fill").font(.headline).foregroundStyle(.red)
        }
    }
}
