// The main window: filters, timeline, table, detail pane, toolbar.

import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers
import SlimreelKit

struct ContentView: View {
    @EnvironmentObject var lib: Library
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\VideoItem.bytes, order: .reverse)]
    @State private var pendingDelete: Set<String>?
    @State private var pendingMove: (ids: Set<String>, folder: URL)?
    @AppStorage("moveFolder") private var moveFolderPath = ""
    @State private var pendingShrink: Set<String>?
    @AppStorage("minMB") private var minMB = 0
    @AppStorage("hideKept") private var hideKept = true
    @State private var dateFrom: Date?
    @State private var dateTo: Date?

    /// Items passing every filter except the date range (feeds the timeline).
    var undated: [VideoItem] {
        let min = Int64(minMB) * 1_000_000
        return lib.items.filter { $0.bytes >= min && !(hideKept && lib.kept.contains($0.id)) }
    }

    func inDateRange(_ item: VideoItem) -> Bool {
        DateRange.contains(item.sortDate, from: dateFrom, to: dateTo)
    }

    var dated: [Date] { lib.items.map(\.sortDate).filter { $0 != .distantPast } }

    var selectedItem: VideoItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return lib.items.first { $0.id == id }
    }

    var body: some View {
        let base = undated
        let rows = base.filter(inDateRange).sorted(using: sortOrder)
        VStack(spacing: 0) {
            header(rows)
            if !base.isEmpty {
                SizeTimeline(items: base, from: $dateFrom, to: $dateTo)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            HSplitView {
                table(rows).frame(minWidth: 640)
                DetailView(item: selectedItem, selectedCount: selection.count,
                           selectedBytes: lib.bytes(selection))
                    .frame(minWidth: 320, idealWidth: 400)
            }
            .confirmationDialog(moveTitle, isPresented: Binding(
                get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })
            ) {
                Button("Save to Folder, Then Delete from Photos", role: .destructive) {
                    if let m = pendingMove { Task { await lib.moveToFolder(m.ids, folder: m.folder) } }
                    pendingMove = nil
                }
            } message: {
                Text(moveMessage)
            }
            .sheet(isPresented: Binding(get: { lib.move != nil }, set: { if !$0 { lib.move = nil } })) {
                MoveSheet().environmentObject(lib)
            }
            .onChange(of: lib.selectionInvalidated) { _, ids in selection.subtract(ids) }
        }
        .sheet(isPresented: Binding(get: { pendingShrink != nil }, set: { if !$0 { pendingShrink = nil } })) {
            ShrinkOptionsSheet(ids: pendingShrink ?? []) { settings in
                if let ids = pendingShrink { Task { await lib.shrink(ids, settings: settings) } }
                pendingShrink = nil
            } cancel: { pendingShrink = nil }
            .environmentObject(lib)
        }
        .task { await lib.start() }
        .toolbar { toolbar }
        .confirmationDialog(deleteTitle, isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Move to Recently Deleted", role: .destructive) {
                if let ids = pendingDelete {
                    selection.subtract(ids)
                    Task { await lib.delete(ids) }
                }
                pendingDelete = nil
            }
        } message: {
            Text("They'll stay in Photos → Recently Deleted for 30 days (and still use iCloud storage) until you empty it there.")
        }
        .alert(lib.message ?? "", isPresented: Binding(
            get: { lib.message != nil }, set: { if !$0 { lib.message = nil } })
        ) { Button("OK") {} }
    }

    var deleteTitle: String {
        let ids = pendingDelete ?? []
        return "Delete \(ids.count) video\(ids.count == 1 ? "" : "s") (\(fmtBytes(lib.bytes(ids))))?"
    }

    var moveTitle: String {
        guard let m = pendingMove else { return "" }
        return "Move \(m.ids.count) video\(m.ids.count == 1 ? "" : "s") (\(fmtBytes(lib.bytes(m.ids)))) to “\(m.folder.lastPathComponent)”?"
    }

    var moveMessage: String {
        guard let m = pendingMove else { return "" }
        var s = "The original files (plus any edited versions) are saved to \(m.folder.path), downloading from iCloud if needed. Only videos that save and check out correctly are then moved to Photos → Recently Deleted."
        let needed = lib.bytes(m.ids)
        if let free = Library.freeSpace(at: m.folder), free < needed + 1_000_000_000 {
            s += "\n\n⚠️ That drive only has \(fmtBytes(free)) free, and these videos need \(fmtBytes(needed)). Some may fail to save (they won't be deleted)."
        }
        return s
    }

    func chooseFolder(for ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        panel.message = "Choose where to save \(ids.count) video\(ids.count == 1 ? "" : "s") (\(fmtBytes(lib.bytes(ids))))"
        if !moveFolderPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: moveFolderPath) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        moveFolderPath = url.path
        pendingMove = (ids, url)
    }

    func header(_ rows: [VideoItem]) -> some View {
        HStack(spacing: 16) {
            let dates = dated
            let years = Array(Set(dates.map { Calendar.current.component(.year, from: $0) })).sorted(by: >)
            DateRangeControls(from: $dateFrom, to: $dateTo, years: years,
                              earliest: dates.min() ?? Date(), latest: dates.max() ?? Date())
            Picker("Min size", selection: $minMB) {
                Text("All").tag(0)
                Text("≥ 50 MB").tag(50)
                Text("≥ 100 MB").tag(100)
                Text("≥ 250 MB").tag(250)
                Text("≥ 500 MB").tag(500)
                Text("≥ 1 GB").tag(1000)
            }
            .frame(width: 150)
            Toggle("Hide kept", isOn: $hideKept)
            Spacer()
            if lib.loading {
                ProgressView(value: lib.progress).frame(width: 100)
                Text("Sizing up your videos…").foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 1) {
                let total = rows.reduce(Int64(0)) { $0 + $1.bytes }
                Text("\(rows.count) videos · \(fmtBytes(total))").font(.headline).monospacedDigit()
                if !selection.isEmpty {
                    Text("\(selection.count) selected · \(fmtBytes(lib.bytes(selection)))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    func table(_ rows: [VideoItem]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { Thumb(asset: $0.asset) }.width(76)
            TableColumn("Size", value: \.bytes) { item in
                Text(fmtBytes(item.bytes)).monospacedDigit().fontWeight(.medium)
            }.width(min: 70, ideal: 85)
            TableColumn("Length", value: \.duration) { Text(fmtDur($0.duration)).monospacedDigit() }
                .width(min: 55, ideal: 65)
            TableColumn("MB/min", value: \.mbPerMin) { Text(String(format: "%.0f", $0.mbPerMin)).monospacedDigit() }
                .width(min: 50, ideal: 60)
            TableColumn("Date", value: \.sortDate) { Text($0.sortDate, format: .dateTime.year().month(.abbreviated).day()) }
                .width(min: 80, ideal: 100)
            TableColumn("Resolution", value: \.pixels) { Text("\($0.width)×\($0.height)").monospacedDigit() }
                .width(min: 80, ideal: 90)
            TableColumn("Name", value: \.filename) { Text($0.filename).lineLimit(1).truncationMode(.middle) }
            TableColumn("") { item in
                HStack(spacing: 4) {
                    if lib.kept.contains(item.id) { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).help("Kept") }
                    if item.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.pink).help("Favorite") }
                    if item.isEdited { Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary).help("Edited — moving saves the original and the edited version") }
                }
            }.width(56)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button(ids.isSubset(of: lib.kept) ? "Unmark Kept" : "Mark as Kept") { lib.toggleKeep(ids) }
            Button("Add to “\(Library.reviewAlbum)” Album") { Task { await lib.addToReviewAlbum(ids) } }
            Divider()
            Button("Shrink…") { pendingShrink = ids }
            Button("Move to Folder…") { chooseFolder(for: ids) }
            Button("Delete…", role: .destructive) { pendingDelete = ids }
        }
        .onDeleteCommand { if !selection.isEmpty { pendingDelete = selection } }
        .overlay { if rows.isEmpty && !lib.loading { emptyState } }
    }

    @ViewBuilder var emptyState: some View {
        if lib.items.isEmpty {
            ContentUnavailableView("No videos here", systemImage: "film",
                description: Text("This Photos library doesn't have any videos in it."))
        } else if hideKept && lib.items.allSatisfy({ lib.kept.contains($0.id) }) {
            ContentUnavailableView {
                Label("That's the lot", systemImage: "checkmark.seal")
            } description: {
                Text("You've been through every video. Turn off Hide Kept to see them again.")
            }
        } else if minMB > 0 && dateFrom == nil && dateTo == nil {
            ContentUnavailableView("Nothing over \(fmtBytes(Int64(minMB) * 1_000_000))", systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Lower the minimum size to see more."))
        } else {
            ContentUnavailableView("Nothing matches", systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No videos fit these filters. Lower the minimum size or widen the dates."))
        }
    }

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { Task { await lib.reload() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .disabled(lib.loading)
            Button { lib.toggleKeep(selection) } label: { Label("Keep", systemImage: "checkmark.seal") }
                .help("Mark selected as kept (hidden when “Hide kept” is on)")
                .keyboardShortcut("k", modifiers: [])
                .disabled(selection.isEmpty)
            Button { Task { await lib.addToReviewAlbum(selection) } } label: { Label("Add to Album", systemImage: "rectangle.stack.badge.plus") }
                .help("Add selected to the “\(Library.reviewAlbum)” album in Photos")
                .disabled(selection.isEmpty)
            Button { pendingShrink = selection } label: { Label("Shrink", systemImage: "arrow.down.right.and.arrow.up.left") }
                .help("Re-encode at a lower resolution / frame rate and replace the original in Photos")
                .disabled(selection.isEmpty || lib.move != nil)
            Button { chooseFolder(for: selection) } label: { Label("Move to Folder", systemImage: "folder.badge.plus") }
                .help("Save the original files to a folder, then delete them from Photos/iCloud")
                .disabled(selection.isEmpty || lib.move != nil)
            Button(role: .destructive) { pendingDelete = selection } label: { Label("Delete", systemImage: "trash") }
                .help("Move selected to Recently Deleted (⌫)")
                .disabled(selection.isEmpty)
        }
    }
}
