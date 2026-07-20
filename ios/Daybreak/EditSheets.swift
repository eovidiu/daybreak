import SwiftUI

struct TaskEditSheet: View {
    @EnvironmentObject var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let task: PlannerTask

    @State private var title = ""
    @State private var note = ""
    @State private var bucket = Bucket.urgent
    @State private var scheduled = false
    @State private var start = 9 * 60
    @State private var minutes = 60

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("editTitle")
                    .foregroundStyle(Theme.ink)
                Picker("Bucket", selection: $bucket) {
                    ForEach(Bucket.allCases) { Text($0.title).tag($0) }
                }
                Section("Time block") {
                    Toggle("Scheduled", isOn: $scheduled)
                        .accessibilityIdentifier("scheduledToggle")
                    if scheduled {
                        TimeControls(start: $start, minutes: $minutes)
                    }
                }
                Section("Private note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("editNote")
                        .foregroundStyle(Theme.ink)
                }
                Button("Delete task", role: .destructive) {
                    store.delete(task)
                    dismiss()
                }
                .accessibilityIdentifier("deleteItem")
            }
            .navigationTitle("Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("saveItem")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            title = task.title
            note = task.note
            bucket = task.bucket
            scheduled = task.scheduledStart != nil
            start = task.scheduledStart ?? 9 * 60
            minutes = task.scheduledMinutes ?? 60
        }
    }

    private func save() {
        store.update(task, title: title, note: note, bucket: bucket)
        store.schedule(task, start: scheduled ? start : nil,
                       minutes: scheduled ? minutes : nil)
        dismiss()
    }
}

struct EventEditSheet: View {
    @EnvironmentObject var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let event: PlannerEvent

    @State private var title = ""
    @State private var note = ""
    @State private var bucket = Bucket.extra
    @State private var start = 9 * 60
    @State private var minutes = 60

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("editTitle")
                    .foregroundStyle(Theme.ink)
                Picker("Bucket", selection: $bucket) {
                    ForEach(Bucket.allCases) { Text($0.title).tag($0) }
                }
                TimeControls(start: $start, minutes: $minutes)
                Section("Private note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("editNote")
                        .foregroundStyle(Theme.ink)
                }
                Button("Delete event", role: .destructive) {
                    store.delete(event)
                    dismiss()
                }
                .accessibilityIdentifier("deleteItem")
            }
            .navigationTitle("Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.update(event, title: title, note: note, bucket: bucket,
                                     start: start, minutes: minutes)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveItem")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            title = event.title
            note = event.note
            bucket = event.bucket
            start = event.startMin
            minutes = event.durationMin
        }
    }
}

struct NewEventSheet: View {
    @EnvironmentObject var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bucket = Bucket.extra
    @State private var start = 9 * 60
    @State private var minutes = 60

    var body: some View {
        NavigationStack {
            Form {
                TextField("Event title", text: $title)
                    .accessibilityIdentifier("newEventTitle")
                    .foregroundStyle(Theme.ink)
                Picker("Bucket", selection: $bucket) {
                    ForEach(Bucket.allCases) { Text($0.title).tag($0) }
                }
                TimeControls(start: $start, minutes: $minutes)
            }
            .navigationTitle("New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let t = title.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        Task {
                            await store.addEvent(title: t, bucket: bucket,
                                                 start: start, minutes: minutes)
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("saveItem")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// Edits a queued low-confidence capture, then accepts it (creates the task) or dismisses
// it. Prefilled from the classifier's suggestion.
struct ReviewSheet: View {
    @EnvironmentObject var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let review: Review

    @State private var title = ""
    @State private var bucket = Bucket.extra
    @State private var scheduled = false
    @State private var start = 9 * 60
    @State private var minutes = 60

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("editTitle")
                        .foregroundStyle(Theme.ink)
                    Picker("Bucket", selection: $bucket) {
                        ForEach(Bucket.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Suggested · \(Int(review.confidence * 100))% sure")
                }
                Section("Time block") {
                    Toggle("Scheduled", isOn: $scheduled)
                        .accessibilityIdentifier("scheduledToggle")
                    if scheduled { TimeControls(start: $start, minutes: $minutes) }
                }
                Button("Dismiss", role: .destructive) {
                    Task { await store.dismissReview(review) }
                    dismiss()
                }
                .accessibilityIdentifier("dismissReview")
            }
            .navigationTitle("Review capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept") {
                        Task {
                            await store.acceptReview(review, bucket: bucket, day: review.day,
                                                     title: title,
                                                     start: scheduled ? start : nil,
                                                     minutes: scheduled ? minutes : nil)
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("acceptReview")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            title = review.title
            bucket = review.bucket
            scheduled = review.start != nil
            start = review.start ?? 9 * 60
            minutes = review.minutes ?? 60
        }
    }
}

// The immutable audit trail: every capture, how it was filed, and any later corrections.
struct HistorySheet: View {
    @EnvironmentObject var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [AuditEntry] = []

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("No captures yet.").foregroundStyle(Theme.muted)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.rawInput).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        Text(summary(entry)).font(.caption2).foregroundStyle(Theme.muted)
                        ForEach(Array(entry.corrections.enumerated()), id: \.offset) { _, c in
                            Text("↳ \(c.field): \(show(c.old)) → \(show(c.new))")
                                .font(.caption2).foregroundStyle(Theme.urgent)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("audit-\(entry.rawInput)")
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeHistory")
                }
            }
        }
        .task { entries = await store.auditHistory() }
    }

    private func summary(_ e: AuditEntry) -> String {
        let tier = e.tier == .foundationModels ? "on-device AI" : "rules"
        return "\(e.bucket.title) · \(Int(e.confidence * 100))% · "
            + (e.autoFiled ? "filed" : "queued") + " · \(tier)"
    }

    private func show(_ value: String) -> String { value.isEmpty ? "—" : value }
}

// Adjusts the Bouncer's auto-file threshold.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var threshold = CaptureThreshold.load()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Auto-file at")
                        Spacer()
                        Text("\(Int(threshold * 100))%").foregroundStyle(.secondary)
                            .accessibilityIdentifier("thresholdValue")
                    }
                    Slider(value: $threshold, in: CaptureThreshold.range, step: 0.05)
                        .accessibilityIdentifier("thresholdSlider")
                        .onChange(of: threshold) { _, value in CaptureThreshold.save(value) }
                } footer: {
                    Text("Captures this confident file straight into a bucket. Less confident "
                         + "ones wait in the review queue.")
                }
                Section {
                    HStack {
                        Text("On-device AI")
                        Spacer()
                        Text(Capture.foundationModelsActive ? "Active" : "Built-in rules")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("aiStatus")
                    }
                } footer: {
                    Text(Capture.foundationModelsActive
                         ? "Apple Intelligence is on — captures are sorted by the on-device model."
                         : "Captures are sorted by built-in rules. Turn on Apple Intelligence "
                           + "(iPhone 15 Pro or newer) for smarter sorting.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeSettings")
                }
            }
        }
    }
}

struct TimeControls: View {
    @Binding var start: Int
    @Binding var minutes: Int

    var body: some View {
        Stepper(value: $start, in: 0...(24 * 60 - 15), step: 15) {
            HStack {
                Text("Start")
                Spacer()
                Text(Day.time(start)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("startValue")
            }
        }
        .accessibilityIdentifier("startStepper")
        Stepper(value: $minutes, in: 15...720, step: 15) {
            HStack {
                Text("Duration")
                Spacer()
                Text("\(minutes)m").foregroundStyle(.secondary)
                    .accessibilityIdentifier("durationValue")
            }
        }
        .accessibilityIdentifier("durationStepper")
    }
}
