import SwiftUI

struct PlannerView: View {
    @EnvironmentObject var store: PlannerStore
    @State private var editingTask: PlannerTask?
    @State private var editingEvent: PlannerEvent?
    @State private var reviewing: Review?
    @State private var addingEvent = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WeekStrip()
                    CaptureBar()
                    if !store.reviews.isEmpty {
                        ReviewSection { reviewing = $0 }
                    }
                    ForEach(Bucket.allCases) { bucket in
                        BucketSection(bucket: bucket) { editingTask = $0 }
                    }
                    if !store.earlier.isEmpty { EarlierSection() }
                    TimelineSection(
                        onTapEvent: { editingEvent = $0 },
                        onTapTask: { editingTask = $0 }
                    )
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(store.day == Day.today()
                             ? "Today" : Day.label(store.day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { store.select(day: Day.today()) }
                        .disabled(store.day == Day.today())
                        .accessibilityIdentifier("todayButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add event") { addingEvent = true }
                        Button("Settings") { showingSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityIdentifier("menuButton")
                    }
                }
            }
            .refreshable { await store.load() }
            .sheet(item: $editingTask) { TaskEditSheet(task: $0) }
            .sheet(item: $editingEvent) { EventEditSheet(event: $0) }
            .sheet(item: $reviewing) { ReviewSheet(review: $0) }
            .sheet(isPresented: $addingEvent) { NewEventSheet() }
            .sheet(isPresented: $showingSettings) { SettingsSheet() }
        }
    }
}

struct CaptureBar: View {
    @EnvironmentObject var store: PlannerStore
    @State private var text = ""
    @State private var busy = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(Theme.urgent)
            TextField("Capture anything — I’ll sort it", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityIdentifier("captureField")
                .onSubmit(submit)
            if busy {
                ProgressView().controlSize(.small)
            } else if !text.isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityIdentifier("captureSubmit")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
        .shadow(color: Theme.ink.opacity(0.05), radius: 12, y: 4)
    }

    private func submit() {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !busy else { return }
        text = ""
        busy = true
        Task {
            await store.capture(line)
            busy = false
        }
    }
}

struct WeekStrip: View {
    @EnvironmentObject var store: PlannerStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(-3...3, id: \.self) { offset in
                let day = Day.add(store.day, offset)
                let parts = Day.shortLabel(day)
                Button {
                    store.select(day: day)
                } label: {
                    VStack(spacing: 3) {
                        Text(parts.weekday.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(day == store.day
                                             ? Theme.paper.opacity(0.7) : Theme.muted)
                        Text(parts.dayNum)
                            .font(.serif(18, .semibold))
                            .foregroundStyle(dayNumColor(day))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(day == store.day ? Theme.ink : Theme.card,
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(day == store.day ? .clear : Theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-\(day)")
            }
        }
    }

    private func dayNumColor(_ day: String) -> Color {
        if day == Day.today() { return day == store.day ? Color(hex: 0xE9A58F) : Theme.urgent }
        return day == store.day ? Theme.paper : Theme.ink
    }
}

struct BucketSection: View {
    @EnvironmentObject var store: PlannerStore
    let bucket: Bucket
    let onEdit: (PlannerTask) -> Void
    @State private var newTitle = ""

    var color: Color { Theme.accent(bucket) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bucket.title).font(.serif(20, .semibold)).foregroundStyle(color)
                Text(bucket.subtitle).font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(store.data.tasks.filter { $0.bucket == bucket }) { task in
                TaskRow(task: task, onEdit: onEdit)
            }
            HStack(spacing: 8) {
                TextField("Add a task…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("addTask-\(bucket.rawValue)")
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink).frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Theme.hairline))
                }
                .accessibilityIdentifier("addTaskButton-\(bucket.rawValue)")
            }
            .padding(.top, 4)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
        .padding(16)
        .padding(.leading, 4)
        .background(alignment: .leading) {
            HStack(spacing: 0) {
                Rectangle().fill(color).frame(width: 4)
                Theme.card
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        .shadow(color: Theme.ink.opacity(0.05), radius: 12, y: 4)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newTitle = ""
        Task { await store.addTask(bucket: bucket, title: title) }
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: PlannerStore
    let task: PlannerTask
    let onEdit: (PlannerTask) -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button {
                store.toggle(task)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? Theme.progress : Theme.muted)
                    .font(.system(size: 19))
            }
            .accessibilityIdentifier("toggle-\(task.title)")

            Text(task.title)
                .font(.system(size: 15))
                .strikethrough(task.done)
                .foregroundStyle(task.done ? Theme.muted : Theme.ink)
            Spacer()
            if !task.note.isEmpty {
                Image(systemName: "text.alignleft").font(.caption).foregroundStyle(Theme.muted)
            }
            if let start = task.scheduledStart {
                Text(Day.time(start))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().stroke(Theme.hairline))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-\(task.title)")
    }
}

struct ReviewSection: View {
    @EnvironmentObject var store: PlannerStore
    let onReview: (Review) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs a look").font(.serif(16, .semibold)).foregroundStyle(Theme.inkSoft)
            Text("Captures I wasn’t sure how to file.")
                .font(.caption).foregroundStyle(Theme.muted)
            ForEach(store.reviews) { review in
                HStack(spacing: 10) {
                    Circle().fill(Theme.accent(review.bucket)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.title).font(.system(size: 14)).foregroundStyle(Theme.ink)
                        Text("\(review.bucket.title) · \(Int(review.confidence * 100))% sure")
                            .font(.caption2).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Review") { onReview(review) }
                        .font(.caption.weight(.semibold)).tint(Theme.ink)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("review-\(review.title)")
                }
            }
        }
        .padding(16)
        .background(Theme.paperDim, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviewSection")
    }
}

struct EarlierSection: View {
    @EnvironmentObject var store: PlannerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earlier").font(.serif(16, .semibold)).foregroundStyle(Theme.inkSoft)
            Text("Unfinished tasks from past days.")
                .font(.caption).foregroundStyle(Theme.muted)
            ForEach(store.earlier) { task in
                HStack(spacing: 10) {
                    Text(String(task.day.suffix(5))).font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                    Text(task.title).font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Button("Today") { store.pullIntoToday(task) }
                        .font(.caption.weight(.semibold)).tint(Theme.ink)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("pull-\(task.title)")
                    Button(role: .destructive) {
                        store.deleteEarlier(task)
                    } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .accessibilityIdentifier("dropEarlier-\(task.title)")
                }
            }
        }
        .padding(16)
        .background(Theme.paperDim, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("earlierSection")
    }
}
