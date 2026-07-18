import Foundation
import SwiftData

// On-device persistence for the local-first iOS app. Bucket is stored as its raw
// string to keep SwiftData predicates simple.

@Model
final class TaskEntity {
    @Attribute(.unique) var id: String
    var day: String
    var bucketRaw: String
    var title: String
    var note: String
    var done: Bool
    var scheduledStart: Int?
    var scheduledMinutes: Int?
    var position: Int
    var completedAt: Date?
    var updatedAt: Date
    var createdAt: Date
    var auditRecordId: String?

    init(id: String = UUID().uuidString, day: String, bucket: Bucket, title: String,
         note: String = "", done: Bool = false, scheduledStart: Int? = nil,
         scheduledMinutes: Int? = nil, position: Int = 0, auditRecordId: String? = nil,
         now: Date) {
        self.id = id
        self.day = day
        self.bucketRaw = bucket.rawValue
        self.title = title
        self.note = note
        self.done = done
        self.scheduledStart = scheduledStart
        self.scheduledMinutes = scheduledMinutes
        self.position = position
        self.completedAt = done ? now : nil
        self.updatedAt = now
        self.createdAt = now
        self.auditRecordId = auditRecordId
    }

    var bucket: Bucket { Bucket(rawValue: bucketRaw) ?? .extra }

    func asTask() -> PlannerTask {
        PlannerTask(id: id, day: day, bucket: bucket, title: title, note: note, done: done,
                    scheduledStart: scheduledStart, scheduledMinutes: scheduledMinutes,
                    position: position)
    }

    func asEarlier() -> EarlierTask {
        EarlierTask(id: id, day: day, bucket: bucket, title: title, note: note)
    }
}

@Model
final class EventEntity {
    @Attribute(.unique) var id: String
    var day: String
    var bucketRaw: String
    var title: String
    var note: String
    var startMin: Int
    var durationMin: Int
    var createdAt: Date

    init(id: String = UUID().uuidString, day: String, bucket: Bucket, title: String,
         note: String = "", startMin: Int, durationMin: Int, now: Date) {
        self.id = id
        self.day = day
        self.bucketRaw = bucket.rawValue
        self.title = title
        self.note = note
        self.startMin = startMin
        self.durationMin = durationMin
        self.createdAt = now
    }

    var bucket: Bucket { Bucket(rawValue: bucketRaw) ?? .extra }

    func asEvent() -> PlannerEvent {
        PlannerEvent(id: id, day: day, bucket: bucket, title: title, note: note,
                     startMin: startMin, durationMin: durationMin)
    }
}

enum CaptureSource: String, Codable { case typed, share }
enum CaptureStatus: String, Codable { case pending, classified, filed, reviewed }
enum ModelTier: String, Codable { case foundationModels, ruleBased }

@Model
final class CaptureItem {
    @Attribute(.unique) var id: String
    var text: String
    var sourceRaw: String
    var statusRaw: String
    var createdAt: Date

    init(id: String = UUID().uuidString, text: String, source: CaptureSource,
         status: CaptureStatus = .pending, now: Date) {
        self.id = id
        self.text = text
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
        self.createdAt = now
    }

    var source: CaptureSource { CaptureSource(rawValue: sourceRaw) ?? .typed }
    var status: CaptureStatus { CaptureStatus(rawValue: statusRaw) ?? .pending }
}

@Model
final class ReviewItem {
    @Attribute(.unique) var id: String
    var captureId: String
    var cleanedTitle: String
    var suggestedBucketRaw: String
    var suggestedDay: String
    var suggestedStart: Int?
    var suggestedMinutes: Int?
    var confidence: Double
    var auditRecordId: String
    var createdAt: Date

    init(id: String = UUID().uuidString, captureId: String, cleanedTitle: String,
         suggestedBucket: Bucket, suggestedDay: String, suggestedStart: Int? = nil,
         suggestedMinutes: Int? = nil, confidence: Double, auditRecordId: String, now: Date) {
        self.id = id
        self.captureId = captureId
        self.cleanedTitle = cleanedTitle
        self.suggestedBucketRaw = suggestedBucket.rawValue
        self.suggestedDay = suggestedDay
        self.suggestedStart = suggestedStart
        self.suggestedMinutes = suggestedMinutes
        self.confidence = confidence
        self.auditRecordId = auditRecordId
        self.createdAt = now
    }

    var suggestedBucket: Bucket { Bucket(rawValue: suggestedBucketRaw) ?? .extra }

    func asReview() -> Review {
        Review(id: id, title: cleanedTitle, bucket: suggestedBucket, day: suggestedDay,
               start: suggestedStart, minutes: suggestedMinutes, confidence: confidence)
    }
}

@Model
final class AuditRecord {
    @Attribute(.unique) var id: String
    var captureId: String
    var rawInput: String
    var chosenBucketRaw: String
    var confidence: Double
    var autoFiled: Bool
    var modelTierRaw: String
    var correctionsJSON: String
    var createdAt: Date

    init(id: String = UUID().uuidString, captureId: String, rawInput: String,
         chosenBucket: Bucket, confidence: Double, autoFiled: Bool, modelTier: ModelTier,
         correctionsJSON: String = "[]", now: Date) {
        self.id = id
        self.captureId = captureId
        self.rawInput = rawInput
        self.chosenBucketRaw = chosenBucket.rawValue
        self.confidence = confidence
        self.autoFiled = autoFiled
        self.modelTierRaw = modelTier.rawValue
        self.correctionsJSON = correctionsJSON
        self.createdAt = now
    }

    var chosenBucket: Bucket { Bucket(rawValue: chosenBucketRaw) ?? .extra }
    var modelTier: ModelTier { ModelTier(rawValue: modelTierRaw) ?? .ruleBased }
}
