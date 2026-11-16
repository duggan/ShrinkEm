// Cancelling a running job. Each long PhotoKit or AVFoundation step registers how to
// stop itself with the job's token; cancelling the token stops whatever is in flight.

import Foundation
import Photos
import CryptoKit

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [UUID: () -> Void] = [:]

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Runs `handler` when the token is cancelled (straight away if it already is).
    @discardableResult
    func onCancel(_ handler: @escaping () -> Void) -> UUID {
        let key = UUID()
        lock.lock()
        let already = cancelled
        if !already { handlers[key] = handler }
        lock.unlock()
        if already { handler() }
        return key
    }

    func remove(_ key: UUID) {
        lock.lock(); handlers[key] = nil; lock.unlock()
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let pending = Array(handlers.values)
        handlers = [:]
        lock.unlock()
        pending.forEach { $0() }
    }

    func check() throws { if isCancelled { throw CancellationError() } }
}

extension Library {
    /// Streams a Photos resource to `url` (downloading from iCloud if needed), then reads
    /// the file back and checks it matches what Photos sent, byte for byte (SHA-256 of
    /// the stream against SHA-256 of the file). Unlike `writeData`, it can be stopped
    /// part-way through. The caller removes `url` on failure; it's created before the
    /// first byte arrives. Progress: 0–0.9 receiving, 0.9–1 reading back.
    nonisolated static func write(_ resource: PHAssetResource, to url: URL, cancel: CancelToken?,
                                  progress: @escaping @Sendable (Double) -> Void) async throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ExportError("Couldn't create \(url.lastPathComponent) in \(url.deletingLastPathComponent().lastPathComponent)")
        }
        let sink = try Sink(FileHandle(forWritingTo: url))
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.progressHandler = { progress(0.9 * $0) }
        let manager = PHAssetResourceManager.default()
        var key: UUID?
        defer { if let key { cancel?.remove(key) } }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let id = manager.requestData(for: resource, options: opts, dataReceivedHandler: { data in
                if !sink.write(data) { manager.cancelDataRequest(sink.requestID) }   // disk full, drive gone…
            }, completionHandler: { error in
                if let failure = sink.error ?? error { cont.resume(throwing: failure) } else { cont.resume() }
            })
            sink.requestID = id
            key = cancel?.onCancel { manager.cancelDataRequest(id) }
        }
        let sent = try sink.close()
        try cancel?.check()
        // Test hook only: damage the copy so the read-back check has something to catch.
        if ProcessInfo.processInfo.environment["SLIMREEL_CORRUPT_COPIES"] != nil,
           let h = try? FileHandle(forUpdating: url) {
            try? h.seek(toOffset: 1000); try? h.write(contentsOf: Data([0xFF, 0x00])); try? h.close()
        }
        let onDisk = try readBack(url, cancel: cancel) { progress(0.9 + 0.1 * $0) }
        guard onDisk == sent else {
            throw ExportError("The copy in \(url.deletingLastPathComponent().lastPathComponent) didn't match what Photos sent")
        }
    }

    /// SHA-256 of a file, read in 8 MB chunks.
    private nonisolated static func readBack(_ url: URL, cancel: CancelToken?,
                                             progress: (Double) -> Void) throws -> SHA256Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let total = max(Double((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 1), 1)
        var hasher = SHA256(), read = 0.0
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            try cancel?.check()
            hasher.update(data: chunk)
            read += Double(chunk.count)
            progress(read / total)
        }
        return hasher.finalize()
    }

    /// Writes the streamed chunks and hashes them; remembers the first write error.
    /// PhotoKit delivers chunks one at a time, in order, on its own queue.
    private final class Sink: @unchecked Sendable {
        let handle: FileHandle
        var requestID: PHAssetResourceDataRequestID = 0
        private var hasher = SHA256()
        private(set) var error: Error?
        init(_ handle: FileHandle) { self.handle = handle }
        func write(_ data: Data) -> Bool {
            guard error == nil else { return false }
            do {
                try handle.write(contentsOf: data)
                hasher.update(data: data)
                return true
            } catch { self.error = error; return false }
        }
        func close() throws -> SHA256Digest {
            try handle.synchronize()   // on disk (or the server) before it's read back
            try handle.close()
            if let error { throw error }
            return hasher.finalize()
        }
    }
}
