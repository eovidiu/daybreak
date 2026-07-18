import WidgetKit
import SwiftUI

struct CaptureEntry: TimelineEntry {
    let date: Date
}

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry { CaptureEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: .now)], policy: .never))
    }
}

struct DaybreakWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sparkles").font(.title3)
            Spacer()
            Text("Capture").font(.headline)
            Text("Jot it. I’ll sort it.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "daybreak://capture"))
    }
}

struct DaybreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaybreakCapture", provider: CaptureProvider()) { _ in
            DaybreakWidgetView().containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick Capture")
        .description("Opens Daybreak straight to the capture field.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct DaybreakWidgetBundle: WidgetBundle {
    var body: some Widget { DaybreakWidget() }
}
