import SwiftUI

private let dayStartMin = 0
private let dayEndMin = 24 * 60
private let pxPerMin: CGFloat = 1.5

struct TimelineSection: View {
    @EnvironmentObject var store: PlannerStore
    let onTapEvent: (PlannerEvent) -> Void
    let onTapTask: (PlannerTask) -> Void

    private let viewStartMin = 8 * 60
    private let viewHours = 12

    // Opens on 08:00, unless something is scheduled earlier — then show it.
    private var anchorMin: Int {
        let starts = store.data.events.map(\.startMin)
            + store.data.tasks.compactMap(\.scheduledStart)
        guard let first = starts.min() else { return viewStartMin }
        return min(first, viewStartMin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline").font(.serif(20, .semibold)).foregroundStyle(Theme.ink)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        HourGrid()
                        Color.clear.frame(width: 1, height: 1)
                            .offset(y: CGFloat(anchorMin) * pxPerMin)
                            .id("morningAnchor")
                        slotBlocks
                    }
                    .frame(height: CGFloat(dayEndMin - dayStartMin) * pxPerMin)
                }
                .frame(height: CGFloat(viewHours * 60) * pxPerMin)
                .onAppear { proxy.scrollTo("morningAnchor", anchor: .top) }
                .onChange(of: store.day) {
                    proxy.scrollTo("morningAnchor", anchor: .top)
                }
                .onChange(of: store.dayLoadStamp) {
                    proxy.scrollTo("morningAnchor", anchor: .top)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline")
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        .shadow(color: Theme.ink.opacity(0.05), radius: 12, y: 4)
    }

    @ViewBuilder private var slotBlocks: some View {
        ForEach(store.data.events) { event in
            SlotBlock(
                title: event.title, bucket: event.bucket,
                start: event.startMin, minutes: event.durationMin,
                isTask: false, done: false,
                onTap: { onTapEvent(event) },
                onMove: { store.move(event, toStart: $0) }
            )
        }
        ForEach(store.data.tasks.filter { $0.scheduledStart != nil }) { task in
            SlotBlock(
                title: task.title, bucket: task.bucket,
                start: task.scheduledStart ?? 0,
                minutes: task.scheduledMinutes ?? 60,
                isTask: true, done: task.done,
                onTap: { onTapTask(task) },
                onMove: { store.moveScheduled(task, toStart: $0) }
            )
        }
    }
}

private struct HourGrid: View {
    var body: some View {
        ForEach(Array(stride(from: dayStartMin, through: dayEndMin, by: 60)), id: \.self) {
            min in
            VStack(spacing: 0) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Text(Day.time(min)).font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .offset(y: CGFloat(min - dayStartMin) * pxPerMin)
        }
    }
}

struct SlotBlock: View {
    let title: String
    let bucket: Bucket
    let start: Int
    let minutes: Int
    let isTask: Bool
    let done: Bool
    let onTap: () -> Void
    let onMove: (Int) -> Void

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    private var accent: Color { Theme.accent(bucket) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isTask {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text("\(Day.time(start)) · \(minutes)m")
                    .font(.caption2.monospacedDigit()).opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(26, CGFloat(minutes) * pxPerMin - 2), alignment: .top)
        .foregroundStyle(Theme.slotInk(bucket))
        .background(alignment: .leading) {
            HStack(spacing: 0) {
                Rectangle().fill(accent).frame(width: isTask ? 4 : 3)
                Theme.slotFill(bucket).opacity(isDragging ? 0.6 : 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 44)
        .offset(y: CGFloat(start - dayStartMin) * pxPerMin + dragOffset)
        .shadow(color: isDragging ? Theme.ink.opacity(0.22) : .clear, radius: 8)
        .onTapGesture(perform: onTap)
        .gesture(moveGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("slot-\(title)")
    }

    // Long-press then vertical drag; snaps to 15 minutes on release.
    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture())
            .updating($isDragging) { value, state, _ in
                if case .second = value { state = true }
            }
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    dragOffset = drag.translation.height
                }
            }
            .onEnded { value in
                defer { dragOffset = 0 }
                guard case .second(true, let drag?) = value else { return }
                let rawStart = CGFloat(start) + drag.translation.height / pxPerMin
                let snapped = Int((rawStart / 15).rounded()) * 15
                let clamped = min(max(snapped, dayStartMin), dayEndMin - minutes)
                if clamped != start { onMove(clamped) }
            }
    }
}
