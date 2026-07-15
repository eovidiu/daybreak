import SwiftUI

struct PlannerView: View {
    @EnvironmentObject var store: PlannerStore
    @State private var editingTask: PlannerTask?
    @State private var editingEvent: PlannerEvent?
    @State private var addingEvent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WeekStrip()
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
            .navigationTitle(store.day == Day.today()
                             ? "Today" : Day.label(store.day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { store.select(day: Day.today()) }
                        .disabled(store.day == Day.today())
                        .accessibilityIdentifier("todayButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add event") { addingEvent = true }
                        Button("Sign out", role: .destructive) {
                            Task { await store.signOut() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityIdentifier("menuButton")
                    }
                }
            }
            .refreshable { await store.load() }
            .sheet(item: $editingTask) { TaskEditSheet(task: $0) }
            .sheet(item: $editingEvent) { EventEditSheet(event: $0) }
            .sheet(isPresented: $addingEvent) { NewEventSheet() }
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
                    VStack(spacing: 2) {
                        Text(parts.weekday).font(.caption2)
                        Text(parts.dayNum).font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(day == store.day ? Color.primary : Color(.systemGray6))
                    .foregroundStyle(day == store.day
                                     ? Color(.systemBackground) : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        if day == Day.today() {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.orange, lineWidth: day == store.day ? 0 : 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-\(day)")
            }
        }
    }
}

struct BucketSection: View {
    @EnvironmentObject var store: PlannerStore
    let bucket: Bucket
    let onEdit: (PlannerTask) -> Void
    @State private var newTitle = ""

    var color: Color {
        switch bucket {
        case .urgent: .red
        case .progress: .green
        case .extra: .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(bucket.title).font(.headline).foregroundStyle(color)
                Text(bucket.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.data.tasks.filter { $0.bucket == bucket }) { task in
                TaskRow(task: task, onEdit: onEdit)
            }
            HStack {
                TextField("Add a task…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("addTask-\(bucket.rawValue)")
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(color)
                }
                .accessibilityIdentifier("addTaskButton-\(bucket.rawValue)")
            }
            .padding(10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
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
        HStack(spacing: 10) {
            Button {
                store.toggle(task)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? .green : .secondary)
                    .font(.title3)
            }
            .accessibilityIdentifier("toggle-\(task.title)")

            Text(task.title)
                .strikethrough(task.done)
                .foregroundStyle(task.done ? .secondary : .primary)
            Spacer()
            if !task.note.isEmpty {
                Image(systemName: "note.text").font(.caption).foregroundStyle(.secondary)
            }
            if let start = task.scheduledStart {
                Text(Day.time(start))
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().stroke(.secondary.opacity(0.4)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-\(task.title)")
    }
}

struct EarlierSection: View {
    @EnvironmentObject var store: PlannerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earlier").font(.headline).foregroundStyle(.secondary)
            Text("Unfinished tasks from past days.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(store.earlier) { task in
                HStack {
                    Text(String(task.day.suffix(5))).font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(task.title).foregroundStyle(.secondary)
                    Spacer()
                    Button("Today") { store.pullIntoToday(task) }
                        .font(.caption).buttonStyle(.bordered)
                        .accessibilityIdentifier("pull-\(task.title)")
                    Button(role: .destructive) {
                        store.deleteEarlier(task)
                    } label: {
                        Image(systemName: "xmark").font(.caption)
                    }
                    .accessibilityIdentifier("dropEarlier-\(task.title)")
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("earlierSection")
    }
}
