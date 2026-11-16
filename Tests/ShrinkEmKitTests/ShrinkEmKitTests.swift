import XCTest
@testable import ShrinkEmKit

final class FileNamingTests: XCTestCase {
    func testKeepsVideoExtension() {
        XCTAssertEqual(FileNaming.safeName(original: "IMG_0001.MOV", typeIdentifier: "com.apple.quicktime-movie"), "IMG_0001.MOV")
    }
    func testAddsExtensionWhenMissing() {
        XCTAssertEqual(FileNaming.safeName(original: "PETKIT Video2026-06-07 21:46:23", typeIdentifier: "public.mpeg-4"),
                       "PETKIT Video2026-06-07 21-46-23.mp4")
    }
    func testAddsExtensionForNonVideoSuffix() {
        // "clip.final" isn't a video extension, so one is appended.
        XCTAssertEqual(FileNaming.safeName(original: "clip.final", typeIdentifier: "com.apple.quicktime-movie"), "clip.final.mov")
    }
    func testEmptyNameAndSlashes() {
        XCTAssertEqual(FileNaming.safeName(original: "", typeIdentifier: "com.apple.quicktime-movie"), "Video.mov")
        XCTAssertEqual(FileNaming.safeName(original: "a/b.mov", typeIdentifier: ""), "a-b.mov")
    }
    func testUniqueURLNumbersDuplicates() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["/tmp/x/IMG.MOV", "/tmp/x/IMG 2.MOV"]
        XCTAssertEqual(FileNaming.uniqueURL(in: folder, name: "IMG.MOV", exists: taken.contains).lastPathComponent, "IMG 3.MOV")
        XCTAssertEqual(FileNaming.uniqueURL(in: folder, name: "new.mov", exists: taken.contains).lastPathComponent, "new.mov")
        XCTAssertEqual(FileNaming.uniqueURL(in: folder, name: "noext", exists: { $0 == "/tmp/x/noext" }).lastPathComponent, "noext 2")
    }
}

final class ShrinkRulesTests: XCTestCase {
    let hd60 = ShrinkSettings(maxHeight: 1080, maxFPS: 60)

    func testFourK120NeedsBoth() {
        XCTAssertEqual(hd60.plan(width: 2160, height: 3840, fps: 119.95), .shrink(scale: true, frameRate: true))
    }
    func testFourK60OnlyScales() {
        // iPhone "60fps" is often 60.13: not a frame-rate change.
        XCTAssertEqual(hd60.plan(width: 3840, height: 2160, fps: 60.13), .shrink(scale: true, frameRate: false))
    }
    func testHD120OnlyFrameRate() {
        XCTAssertEqual(hd60.plan(width: 1920, height: 1080, fps: 120), .shrink(scale: false, frameRate: true))
    }
    func testAlreadySmall() {
        XCTAssertEqual(hd60.plan(width: 1080, height: 1920, fps: 30), .alreadySmall(shortSide: 1080, fps: 30))
    }
    func testWorthReplacing() {
        XCTAssertTrue(ShrinkSettings.worthReplacing(original: 100, copy: 89))
        XCTAssertFalse(ShrinkSettings.worthReplacing(original: 100, copy: 90))
        XCTAssertFalse(ShrinkSettings.worthReplacing(original: 100, copy: 0))
    }
    func testPresets() {
        XCTAssertEqual(hd60.preset, "AVAssetExportPresetHEVC1920x1080")
        XCTAssertEqual(ShrinkSettings(maxHeight: 720, maxFPS: 30).preset, "AVAssetExportPreset1280x720")
    }
}

final class DateRangeTests: XCTestCase {
    func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }
    func testContains() {
        XCTAssertTrue(DateRange.contains(d(2024, 5, 1), from: nil, to: nil))
        XCTAssertTrue(DateRange.contains(d(2024, 5, 1), from: d(2024, 1, 1), to: nil))
        XCTAssertFalse(DateRange.contains(d(2023, 5, 1), from: d(2024, 1, 1), to: nil))
        XCTAssertTrue(DateRange.contains(d(2024, 12, 31, 23), from: nil, to: DateRange.yearEnd(2024)))
        XCTAssertFalse(DateRange.contains(d(2025, 1, 1, 0), from: nil, to: DateRange.yearEnd(2024)))
    }
    func testMonthOverlap() {
        let may = DateRange.monthStart(d(2024, 5, 15))
        XCTAssertTrue(DateRange.monthOverlaps(may, from: d(2024, 5, 20), to: nil))   // partly
        XCTAssertFalse(DateRange.monthOverlaps(may, from: d(2024, 6, 1), to: nil))
        XCTAssertTrue(DateRange.monthOverlaps(may, from: nil, to: d(2024, 5, 2)))
        XCTAssertFalse(DateRange.monthOverlaps(may, from: nil, to: d(2024, 4, 30)))
    }
    func testDayAndMonthEdges() {
        XCTAssertEqual(DateRange.dayEnd(d(2024, 2, 28)), Calendar.current.date(from: DateComponents(year: 2024, month: 2, day: 28, hour: 23, minute: 59, second: 59)))
        XCTAssertEqual(Calendar.current.component(.day, from: DateRange.monthEnd(d(2024, 2, 10))), 29)  // leap year
    }
    func testBuckets() {
        let entries: [(date: Date, bytes: Int64)] = [(d(2024, 5, 1), 10), (d(2024, 5, 30), 5),
                                                     (d(2023, 1, 2), 7), (.distantPast, 99)]
        let b: [MonthBucket] = MonthBucket.make(entries)
        XCTAssertEqual(b.map(\.bytes), [7, 15])
        XCTAssertEqual(b.map(\.count), [1, 2])
        XCTAssertEqual(b.first?.month, DateRange.monthStart(d(2023, 1, 2)))
    }
}

final class FormattingTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(fmtDur(0), "0:00")
        XCTAssertEqual(fmtDur(65.4), "1:05")
        XCTAssertEqual(fmtDur(3725), "1:02:05")
    }
}
