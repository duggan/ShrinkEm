// The model: the Photos library's videos, sizes, and the move-to-folder workflow.

import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers
import SlimreelKit

// MARK: - Model

struct VideoItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let bytes: Int64          // all resources (original + edits + paired files)
    let originalBytes: Int64  // the original video resource
    let duration: Double
    let sortDate: Date
    let width: Int
    let height: Int
    let filename: String
    let isFavorite: Bool
    let isEdited: Bool        // Photos holds edits (rendered or not)

    var pixels: Int { width * height }
    var mbPerMin: Double { duration > 0 ? Double(bytes) / 1_000_000 / (duration / 60) : 0 }
}

@MainActor
final class Library: ObservableObject {
    @Published var items: [VideoItem] = []
    @Published var loading = false
    @Published var progress = 0.0
    @Published var message: String?
    @Published var kept: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "kept") ?? [])

    func start() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            message = "Slimreel needs access to your Photos library. Enable it in System Settings → Privacy & Security → Photos, then relaunch."
            return
        }
        await reload()
        if let dir = ProcessInfo.processInfo.environment["SLIMREEL_SELFTEST_DIR"] { await selfTest(URL(fileURLWithPath: dir)) }
        if let dir = ProcessInfo.processInfo.environment["SLIMREEL_SHRINKTEST_DIR"] { await shrinkSelfTest(URL(fileURLWithPath: dir)) }
        if let dir = ProcessInfo.processInfo.environment["SLIMREEL_QUEUETEST_DIR"] { await queueSelfTest(URL(fileURLWithPath: dir)) }
        if let dir = ProcessInfo.processInfo.environment["SLIMREEL_RENDER_DIR"] { renderTimelineSnapshots(URL(fileURLWithPath: dir)) }
    }

    /// Read-only self-test: exports the smallest video (twice, to check name
    /// de-duplication) and verifies it. Never deletes anything. Quits when done.
    private func selfTest(_ dir: URL) async {
        var log = "videos=\(items.count) totalBytes=\(items.reduce(0) { $0 + $1.bytes })\n"
        let smallest = items.filter { $0.bytes > 0 && $0.duration > 3 }.min { $0.bytes < $1.bytes }
        let smallestEdited = items.filter { $0.isEdited && $0.duration > 3 }.min { $0.bytes < $1.bytes }
        for item in [smallest, smallestEdited].compactMap({ $0 }) {
            log += "testing \(item.filename) bytes=\(item.bytes) edited=\(item.isEdited)\n"
            for r in PHAssetResource.assetResources(for: item.asset) {
                log += "  resource type=\(r.type.rawValue) \(r.originalFilename) \((r.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? -1)\n"
            }
            for run in 1...2 {
                do {
                    try await Library.export(item.asset, to: dir) { _ in }
                    log += "run\(run): OK\n"
                } catch { log += "run\(run): FAIL \(error.localizedDescription)\n" }
            }
        }
        try? log.write(to: dir.appendingPathComponent("selftest.log"), atomically: true, encoding: .utf8)
        exit(0)
    }

    func reload() async {
        guard !loading else { return }
        loading = true
        progress = 0
        let result = await Task.detached(priority: .userInitiated) { [weak self] in
            Library.scan { p in Task { @MainActor in self?.progress = p } }
        }.value
        items = result
        loading = false
    }

    nonisolated static func scan(progress: @escaping @Sendable (Double) -> Void) -> [VideoItem] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: .video, options: opts)
        let n = max(fetch.count, 1)
        var out: [VideoItem] = []
        out.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, i, _ in
            out.append(makeItem(asset))
            if i % 50 == 0 { progress(Double(i) / Double(n)) }
        }
        progress(1)
        return out
    }

    nonisolated static func makeItem(_ asset: PHAsset) -> VideoItem {
        var total: Int64 = 0
        var original: Int64 = 0
        var name = ""
        var edited = false
        for r in PHAssetResource.assetResources(for: asset) {
            // `fileSize` isn't public API but is the standard way to read it via KVC.
            let size = (r.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
            total += size
            if r.type == .video {
                original = size
                name = r.originalFilename
            }
            if name.isEmpty { name = r.originalFilename }
            if r.type == .adjustmentData || r.type == .fullSizeVideo { edited = true }
        }
        return VideoItem(
            id: asset.localIdentifier, asset: asset,
            bytes: total, originalBytes: original,
            duration: asset.duration,
            sortDate: asset.creationDate ?? .distantPast,
            width: asset.pixelWidth, height: asset.pixelHeight,
            filename: name, isFavorite: asset.isFavorite, isEdited: edited)
    }

    /// Adds newly created videos (e.g. shrunk copies) without rescanning the library.
    func addItems(ids: [String]) {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var added: [VideoItem] = []
        fetch.enumerateObjects { asset, _, _ in added.append(Library.makeItem(asset)) }
        let known = Set(items.map(\.id))
        items.append(contentsOf: added.filter { !known.contains($0.id) })
    }

    func assets(_ ids: Set<String>) -> [PHAsset] {
        items.filter { ids.contains($0.id) }.map(\.asset)
    }

    func bytes(_ ids: Set<String>) -> Int64 {
        items.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    /// Returns true if the assets were deleted (false if cancelled or failed).
    @discardableResult
    func delete(_ ids: Set<String>) async -> Bool {
        let targets = assets(ids)
        guard !targets.isEmpty else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(targets as NSArray)
            }
            items.removeAll { ids.contains($0.id) }
            return true
        } catch {
            let ns = error as NSError
            if ns.code != NSUserCancelledError && ns.code != PHPhotosError.userCancelled.rawValue {
                message = "Delete failed: \(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: Background work

    /// Move and Shrink jobs, run one after another (see WorkQueue.swift).
    lazy var queue = WorkQueue(library: self)

    /// Videos in a waiting or running job. They can't be queued again or deleted
    /// until their job finishes. Changes only when jobs start or finish.
    @Published var busyIDs = Set<String>()

    static func freeSpace(at url: URL) -> Int64? {
        // "Important usage" capacity reports 0 on network volumes (SMB/AFP/NFS),
        // so fall back to the plain free-space figure when it's missing or zero.
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = v?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        if let plain = v?.volumeAvailableCapacity, plain > 0 { return Int64(plain) }
        return nil
    }

    /// IDs removed by a job, so the view can drop them from its selection.
    @Published var selectionInvalidated = Set<String>()

    struct ExportError: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    /// Writes the original video (and the edited version, if any) into `folder`.
    /// Throws unless every file is written and its size matches what Photos reports.
    nonisolated static func export(_ asset: PHAsset, to folder: URL,
                                   progress: @escaping @Sendable (Double) -> Void) async throws {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let original = resources.first(where: { $0.type == .video })
                ?? resources.first(where: { $0.type == .fullSizeVideo }) else {
            throw ExportError("No video file found in Photos")
        }
        let originalName = fileName(for: original)
        let base = (originalName as NSString).deletingPathExtension
        var jobs: [(PHAssetResource, URL)] = [(original, uniqueURL(in: folder, name: originalName))]
        if let edit = resources.first(where: { $0.type == .fullSizeVideo }), edit !== original {
            let ext = (fileName(for: edit) as NSString).pathExtension
            jobs.append((edit, uniqueURL(in: folder, name: "\(base) (edited).\(ext)")))
        }

        // Edits Photos hasn't rendered to a file exist only as Adjustments.plist,
        // so we render the edited version ourselves to keep it.
        let needsRender = !resources.contains { $0.type == .fullSizeVideo }
            && resources.contains { $0.type == .adjustmentData }
        let writeShare = needsRender ? 0.5 : 1.0

        let sizes = jobs.map { ($0.0.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0 }
        let total = max(sizes.reduce(0, +), 1)
        var before: Int64 = 0
        var written: [URL] = []
        do {
            for ((resource, url), size) in zip(jobs, sizes) {
                let opts = PHAssetResourceRequestOptions()
                opts.isNetworkAccessAllowed = true
                let base = before
                opts.progressHandler = { p in progress(writeShare * (Double(base) + p * Double(size)) / Double(total)) }
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: opts)
                written.append(url)

                let onDisk = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                if onDisk == 0 || (size > 0 && onDisk != size) {
                    throw ExportError("Saved file size (\(onDisk) bytes) doesn't match Photos (\(size) bytes)")
                }
                if let date = asset.creationDate {
                    try? FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
                }
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
                before += size
            }
            if needsRender {
                let url = uniqueURL(in: folder, name: "\(base) (edited).mov")
                written.append(url)
                try await renderEdited(asset, to: url) { p in progress(0.5 + 0.5 * p) }
                if let date = asset.creationDate {
                    try? FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
                }
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            }
        } catch {
            for url in written { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        progress(1)
    }

    /// Renders the current (edited) version of a video with Photos' edits applied.
    nonisolated static func renderEdited(_ asset: PHAsset, to url: URL,
                                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let opts = PHVideoRequestOptions()
        opts.version = .current
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        // HEVC keeps the rendered copy close to the original's size; H.264 is the fallback.
        var session: AVAssetExportSession?
        for preset in [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality] where session == nil {
            session = await withCheckedContinuation { cont in
                PHImageManager.default().requestExportSession(forVideo: asset, options: opts,
                                                              exportPreset: preset) { s, _ in
                    cont.resume(returning: s)
                }
            }
        }
        guard let session else { throw ExportError("Photos couldn't prepare the edited version") }
        session.outputURL = url
        session.outputFileType = .mov
        let ticker = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        await session.export()
        ticker.cancel()
        guard session.status == .completed else {
            throw ExportError("Rendering the edited version failed: \(session.error?.localizedDescription ?? "unknown error")")
        }
        let onDisk = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let tracks = (try? await AVURLAsset(url: url).loadTracks(withMediaType: .video)) ?? []
        if onDisk == 0 || tracks.isEmpty { throw ExportError("The edited version came out empty") }
    }

    /// The resource's original filename, made safe, with an extension added if it has none.
    nonisolated static func fileName(for r: PHAssetResource) -> String {
        FileNaming.safeName(original: r.originalFilename, typeIdentifier: r.uniformTypeIdentifier)
    }

    nonisolated static func uniqueURL(in folder: URL, name: String) -> URL {
        FileNaming.uniqueURL(in: folder, name: name)
    }

    static let reviewAlbum = "Slimreel – Review"

    func addToReviewAlbum(_ ids: Set<String>) async {
        let targets = assets(ids)
        guard !targets.isEmpty else { return }
        let fo = PHFetchOptions()
        fo.predicate = NSPredicate(format: "title == %@", Library.reviewAlbum)
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: fo).firstObject
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = existing.flatMap { PHAssetCollectionChangeRequest(for: $0) }
                    ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: Library.reviewAlbum)
                req.addAssets(targets as NSArray)
            }
            message = "Added \(targets.count) video\(targets.count == 1 ? "" : "s") to the “\(Library.reviewAlbum)” album."
        } catch {
            message = "Couldn't add to album: \(error.localizedDescription)"
        }
    }

    func toggleKeep(_ ids: Set<String>) {
        if ids.isSubset(of: kept) { kept.subtract(ids) } else { kept.formUnion(ids) }
        UserDefaults.standard.set(Array(kept), forKey: "kept")
    }
}
