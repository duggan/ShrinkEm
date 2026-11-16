import Foundation
import UniformTypeIdentifiers

public enum FileNaming {
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "3gp", "mkv", "webm", "mts", "m2ts", "hevc"]

    /// A safe file name for a Photos resource: no path separators or colons, and
    /// an extension (from its type identifier) if it has no video extension.
    public static func safeName(original: String, typeIdentifier: String) -> String {
        var name = original.isEmpty ? "Video" : original
        name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if !videoExtensions.contains((name as NSString).pathExtension.lowercased()) {
            name += "." + (UTType(typeIdentifier)?.preferredFilenameExtension ?? "mov")
        }
        return name
    }

    /// `folder/name`, or "name 2", "name 3"… if taken. Never overwrites.
    public static func uniqueURL(in folder: URL, name: String,
                                 exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        let safe = name.isEmpty ? "Video.mov" : name.replacingOccurrences(of: "/", with: "-")
        var url = folder.appendingPathComponent(safe)
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        var n = 2
        while exists(url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}
