import Foundation

/// File-style byte counts, e.g. "1.68 GB".
public func fmtBytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

/// "m:ss", or "h:mm:ss" from an hour.
public func fmtDur(_ s: Double) -> String {
    let t = Int(s.rounded())
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                     : String(format: "%d:%02d", t / 60, t % 60)
}
