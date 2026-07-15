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
                Picker("Bucket", selection: $bucket) {
                    ForEach(Bucket.allCases) { Text($0.title).tag($0) }
                }
                TimeControls(start: $start, minutes: $minutes)
                Section("Private note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("editNote")
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

struct TimeControls: View {
    @Binding var start: Int
    @Binding var minutes: Int

    var body: some View {
        Stepper(value: $start, in: 6 * 60...(22 * 60 - 15), step: 15) {
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
