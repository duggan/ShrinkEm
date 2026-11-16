// Shrink: re-encode videos to a smaller resolution / frame rate, add the smaller
// copy to Photos with the same date, location, favorite and albums, then delete
// the original. Photos can't replace a video's file in place (an "edit" keeps
// the original too, which would use *more* space), so this is how space is freed.

import Foundation
import SwiftUI
import Photos
import AVFoundation
import SlimreelKit

struct SourceInfo {
    let width: Int, height: Int   // oriented
    let fps: Float
    let duration: Double
}

extension Library {
    struct ShrinkError: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    /// Slow-motion videos rely on their high frame rate, so they're never shrunk.
    nonisolated static func isSlowMo(_ asset: PHAsset) -> Bool {
        asset.mediaSubtypes.contains(.videoHighFrameRate)
    }

    /// Re-encodes the current (edited, if edited) version of `asset` into `url`.
    /// Returns the source's properties so the caller can report what changed.
    /// Throws `ShrinkError` if the video is already within `settings`.
    nonisolated static func reencode(_ asset: PHAsset, settings: ShrinkSettings, to url: URL,
                                     progress: @escaping @Sendable (Double) -> Void) async throws -> SourceInfo {
        if isSlowMo(asset) { throw ShrinkError("Slow-motion video — skipped so the slow motion isn't lost") }

        let opts = PHVideoRequestOptions()
        opts.version = .current
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.progressHandler = { p, _, _, _ in progress(0.25 * p) }   // iCloud download
        // Photos' own export sessions ignore a custom frame rate, so fetch the
        // (edited, if edited) video and run our own export session on it.
        let fetched: (AVAsset, AVAudioMix?)? = await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { av, mix, _ in
                cont.resume(returning: av.map { ($0, mix) })
            }
        }
        guard let (source, audioMix) = fetched,
              let session = AVAssetExportSession(asset: source, presetName: settings.preset) else {
            throw ShrinkError("Photos couldn't prepare this video for re-encoding")
        }
        session.audioMix = audioMix

        guard let track = try await source.loadTracks(withMediaType: .video).first else {
            throw ShrinkError("No video track")
        }
        let (natural, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let oriented = natural.applying(transform)
        let info = SourceInfo(width: Int(abs(oriented.width)), height: Int(abs(oriented.height)),
                              fps: fps, duration: try await source.load(.duration).seconds)

        let needsFPS: Bool
        switch settings.plan(width: info.width, height: info.height, fps: fps) {
        case .alreadySmall(let side, let rate):
            throw ShrinkError("Already \(side)p \(rate)fps — nothing to shrink")
        case .shrink(_, let frameRate):
            needsFPS = frameRate
        }

        if needsFPS {
            let comp = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: source)
            comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.maxFPS))
            // Otherwise the source track's own (120fps) timing wins over frameDuration.
            comp.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
            session.videoComposition = comp
        }

        session.outputURL = url
        session.outputFileType = .mov
        session.metadata = (try? await source.load(.metadata)) ?? []

        let ticker = Task {
            while !Task.isCancelled {
                progress(0.25 + 0.75 * Double(session.progress))
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        await session.export()
        ticker.cancel()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw ShrinkError("Re-encoding failed: \(session.error?.localizedDescription ?? "unknown error")")
        }

        // Verify the output before anyone deletes anything.
        let out = AVURLAsset(url: url)
        let outDuration = try await out.load(.duration).seconds
        let outVideo = try await out.loadTracks(withMediaType: .video)
        if outVideo.isEmpty || abs(outDuration - info.duration) > max(1, info.duration * 0.02) {
            try? FileManager.default.removeItem(at: url)
            throw ShrinkError("Re-encoded copy didn't check out (length \(String(format: "%.1f", outDuration))s vs \(String(format: "%.1f", info.duration))s)")
        }
        progress(1)
        return info
    }

    /// Adds `fileURL` to Photos as a new video carrying over `original`'s date,
    /// location, favorite/hidden state and album membership. Returns the new ID.
    nonisolated static func importReplacement(for original: PHAsset, fileURL: URL, filename: String) async throws -> String {
        let albums = PHAssetCollection.fetchAssetCollectionsContaining(original, with: .album, options: nil)
        var editable: [PHAssetCollection] = []
        albums.enumerateObjects { c, _, _ in if c.canPerform(.addContent) { editable.append(c) } }

        var newID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            let o = PHAssetResourceCreationOptions()
            o.originalFilename = filename
            o.shouldMoveFile = true
            req.addResource(with: .video, fileURL: fileURL, options: o)
            req.creationDate = original.creationDate
            req.location = original.location
            req.isFavorite = original.isFavorite
            req.isHidden = original.isHidden
            if let ph = req.placeholderForCreatedAsset {
                newID = ph.localIdentifier
                for album in editable {
                    PHAssetCollectionChangeRequest(for: album)?.addAssets([ph] as NSArray)
                }
            }
        }
        guard let newID else { throw ShrinkError("Photos didn't create the new video") }
        return newID
    }

    nonisolated static func shrinkTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Slimreel-shrink", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Read-only test: re-encodes a few 4K videos into `dir` without touching the library.
    func shrinkSelfTest(_ dir: URL) async {
        var log = ""
        let fourK = items.filter { min($0.width, $0.height) >= 2160 && $0.duration > 3 && !Library.isSlowMo($0.asset) }
        let picks = [
            fourK.filter { $0.width > $0.height }.min { $0.bytes < $1.bytes },
            fourK.filter { $0.height > $0.width }.min { $0.bytes < $1.bytes },
            fourK.filter { $0.isEdited }.min { $0.bytes < $1.bytes },
            fourK.filter { $0.mbPerMin > 1000 }.min { $0.bytes < $1.bytes },   // likely 4K120
        ].compactMap { $0 }
        log += "4K videos: \(fourK.count)\n"
        for (i, item) in picks.enumerated() {
            let url = dir.appendingPathComponent("test\(i)-\((item.filename as NSString).deletingPathExtension).mov")
            let t0 = Date()
            do {
                let low = ProcessInfo.processInfo.environment["SLIMREEL_SHRINKTEST_LOW"] != nil
                let info = try await Library.reencode(item.asset, settings: ShrinkSettings(maxHeight: low ? 720 : 1080, maxFPS: low ? 30 : 60), to: url) { _ in }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                if ProcessInfo.processInfo.environment["SLIMREEL_SHRINKTEST_ARCHIVE"] != nil {
                    let arch = dir.appendingPathComponent("archive"); try? FileManager.default.createDirectory(at: arch, withIntermediateDirectories: true)
                    try await Library.export(item.asset, to: arch) { _ in }
                    log += "  archived original OK\n"
                }
                log += "\(item.filename): src \(info.width)x\(info.height)@\(info.fps) \(item.bytes) bytes edited=\(item.isEdited) -> \(size) bytes in \(Int(Date().timeIntervalSince(t0)))s\n"
            } catch { log += "\(item.filename): FAIL \(error.localizedDescription)\n" }
        }
        try? log.write(to: dir.appendingPathComponent("shrinktest.log"), atomically: true, encoding: .utf8)
        exit(0)
    }
}

struct ShrinkOptionsSheet: View {
    @EnvironmentObject var lib: Library
    let ids: Set<String>
    let start: (ShrinkSettings) -> Void
    let cancel: () -> Void
    @AppStorage("shrinkHeight") private var maxHeight = 1080
    @AppStorage("shrinkFPS") private var maxFPS = 60
    @AppStorage("shrinkArchive") private var archive = false
    @AppStorage("moveFolder") private var folderPath = ""   // shared with Move to Folder

    var folder: URL? { folderPath.isEmpty ? nil : URL(fileURLWithPath: folderPath) }
    var folderReachable: Bool {
        var isDir: ObjCBool = false
        return !folderPath.isEmpty && FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir) && isDir.boolValue
    }
    var canStart: Bool { !archive || folderReachable }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shrink \(ids.count) video\(ids.count == 1 ? "" : "s") (\(fmtBytes(lib.bytes(ids))))")
                .font(.headline)
            Form {
                Picker("Resolution", selection: $maxHeight) {
                    Text("1080p (HEVC)").tag(1080)
                    Text("720p (H.264, no HDR)").tag(720)
                }
                Picker("Frame rate", selection: $maxFPS) {
                    Text("60 fps").tag(60)
                    Text("30 fps").tag(30)
                }
            }
            .formStyle(.columns)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Save the full-quality originals to a folder first", isOn: $archive)
                    if archive {
                        HStack {
                            Image(systemName: "folder")
                            Text(folderPath.isEmpty ? "No folder chosen" : folderPath)
                                .lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(folderReachable ? .primary : .secondary)
                            Spacer()
                            Button("Choose…", action: chooseFolder)
                        }
                        if !folderPath.isEmpty && !folderReachable {
                            Label("That folder isn't available — is the drive connected?", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).font(.callout)
                        } else if folderReachable, let folder, let free = Library.freeSpace(at: folder),
                                  free < lib.bytes(ids) + 1_000_000_000 {
                            Label("Only \(fmtBytes(free)) free there; originals that don't fit won't be shrunk.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).font(.callout)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            VStack(alignment: .leading, spacing: 6) {
                bullet("Each video is re-encoded to at most \(maxHeight)p and \(maxFPS) fps, keeping \(maxHeight >= 1080 ? "HDR, " : "")audio, date, location, favorite and albums.")
                if archive {
                    bullet("The original (plus any edited version) is saved to the folder and checked. If that fails, the video is left untouched.")
                }
                bullet("The smaller copy is added to Photos, then the originals go to Recently Deleted (Photos asks you to confirm).")
                bullet("Edits are baked into the new copy\(archive ? " in Photos" : "") and can no longer be undone there.")
                bullet("Skipped: slow-motion videos, videos already within these limits, and any that wouldn't come out at least 10% smaller.")
            }
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(archive ? "Save Originals & Shrink" : "Shrink") {
                    start(ShrinkSettings(maxHeight: maxHeight, maxFPS: maxFPS, archiveFolder: archive ? folder : nil))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Where should the full-quality originals be saved?"
        if !folderPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: folderPath) }
        if panel.runModal() == .OK, let url = panel.url { folderPath = url.path }
    }

    func bullet(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); Text(s) }
    }
}
