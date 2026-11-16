// Size timeline: storage used per month, with a draggable date-range selection.

import SwiftUI
import Charts
import SlimreelKit

struct SizeTimeline: View {
    let items: [VideoItem]          // already filtered by everything except date
    @Binding var from: Date?
    @Binding var to: Date?
    @State private var hover: Date?

    var buckets: [MonthBucket] {
        MonthBucket.make(items.lazy.map { (date: $0.sortDate, bytes: $0.bytes) })
    }

    func inRange(_ month: Date) -> Bool { DateRange.monthOverlaps(month, from: from, to: to) }

    var body: some View {
        let data = buckets
        let hovered = data.first { $0.month == hover }
        let first = data.first?.month ?? Date()
        let last = DateRange.monthEnd(data.last?.month ?? Date())
        let maxGB = data.map(\.gb).max() ?? 1
        let ticks = [0.0, 1, 5, 10, 20, 50, 100, 200, 500].filter { $0 <= maxGB * 1.1 }
        VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text("Storage by month").font(.caption).fontWeight(.medium)
            Spacer()
            Group {
                if let hovered {
                    Text("\(hovered.month.formatted(.dateTime.month(.wide).year())) · \(fmtBytes(hovered.bytes)) · \(hovered.count) video\(hovered.count == 1 ? "" : "s")")
                } else {
                    Text("Drag across the chart to choose a date range")
                }
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        Chart {
            // Shaded band behind the selected range, so it's visible even over tiny months.
            if from != nil || to != nil {
                RectangleMark(xStart: .value("From", max(from ?? first, first)),
                              xEnd: .value("To", min(to ?? last, last)))
                    .foregroundStyle(Brand.mintDeep.opacity(0.14))
            }
            ForEach(data) { b in
                BarMark(x: .value("Month", b.month, unit: .month),
                        y: .value("Size", b.gb))
                    .cornerRadius(2)
                    .foregroundStyle(barColor(b))
            }
        }
        // Square-root scale: one huge month doesn't flatten all the others.
        .chartYScale(type: .squareRoot)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let gb = v.as(Double.self) { Text(gb == gb.rounded() ? "\(Int(gb)) GB" : String(format: "%.1f GB", gb)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .year)) { _ in
                AxisTick().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.year(), centered: false)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let origin = proxy.plotFrame.map { geo[$0].origin } ?? .zero
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): hover = proxy.value(atX: p.x - origin.x, as: Date.self).map(DateRange.monthStart)
                        case .ended: hover = nil
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        guard let a = proxy.value(atX: g.startLocation.x - origin.x, as: Date.self),
                              let b = proxy.value(atX: g.location.x - origin.x, as: Date.self) else { return }
                        from = DateRange.monthStart(min(a, b))
                        to = DateRange.monthEnd(max(a, b))
                    })
            }
        }
        .accessibilityLabel("Storage used by videos per month")
        .frame(height: 96)
        }
    }

    func barColor(_ b: MonthBucket) -> Color {
        let selected = inRange(b.month)
        let isHover = b.month == hover
        if selected { return Brand.mintDeep.opacity(isHover ? 1 : 0.85) }
        return Color.secondary.opacity(isHover ? 0.55 : 0.3)
    }
}

/// Date-range controls for the filter row: presets, from/to pickers, clear.
struct DateRangeControls: View {
    @Binding var from: Date?
    @Binding var to: Date?
    let years: [Int]          // years present in the library, newest first
    let earliest: Date
    let latest: Date

    var label: String {
        switch (from, to) {
        case (nil, nil): return "All dates"
        case let (f?, nil): return "From \(f.formatted(date: .abbreviated, time: .omitted))"
        case let (nil, t?): return "Before \(t.formatted(date: .abbreviated, time: .omitted))"
        case (_?, _?): return "Custom range"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Button("All Dates") { from = nil; to = nil }
                Divider()
                Button("Last 30 Days") { from = DateRange.dayStart(DateRange.ago(.day, 30)); to = nil }
                Button("Last 12 Months") { from = DateRange.dayStart(DateRange.ago(.month, 12)); to = nil }
                Divider()
                Button("Older Than 1 Year") { from = nil; to = DateRange.dayEnd(DateRange.ago(.year, 1)) }
                Button("Older Than 3 Years") { from = nil; to = DateRange.dayEnd(DateRange.ago(.year, 3)) }
                Button("Older Than 5 Years") { from = nil; to = DateRange.dayEnd(DateRange.ago(.year, 5)) }
                Divider()
                Menu("Year") {
                    ForEach(years, id: \.self) { y in
                        Button(String(y)) { from = DateRange.yearStart(y); to = DateRange.yearEnd(y) }
                    }
                }
            } label: {
                Label(label, systemImage: "calendar")
            }
            .fixedSize()

            DatePicker("From", selection: Binding(
                get: { from ?? earliest }, set: { from = DateRange.dayStart($0) }),
                displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
            Text("–").foregroundStyle(.secondary)
            DatePicker("To", selection: Binding(
                get: { to ?? latest }, set: { to = DateRange.dayEnd($0) }),
                displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
            if from != nil || to != nil {
                Button { from = nil; to = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Show all dates")
            }
        }
    }
}

extension Library {
    /// Test hook: renders the timeline with real data to PNGs, then quits.
    func renderTimelineSnapshots(_ dir: URL) {
        let y = Calendar.current.component(.year, from: Date()) - 3
        let cases: [(String, Date?, Date?, ColorScheme)] = [
            ("all-light", nil, nil, .light), ("range-light", DateRange.yearStart(y), DateRange.yearEnd(y + 1), .light),
            ("range-dark", DateRange.yearStart(y), DateRange.yearEnd(y + 1), .dark),
        ]
        for (name, f, t, scheme) in cases {
            let view = SizeTimeline(items: items, from: .constant(f), to: .constant(t))
                .padding(12).frame(width: 1120)
                .background(scheme == .dark ? Color(white: 0.12) : Color.white)
                .environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: view); r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        exit(0)
    }
}
