import Foundation

// One append-only correction to an audited task: which field changed, from what to what,
// and when. Values are stringified (bucket raw / day / minutes-from-midnight or "").
struct Correction: Codable, Equatable {
    let field: String
    let old: String
    let new: String
    let at: Date
}

// UI-facing view of one immutable AuditRecord and its corrections.
struct AuditEntry: Identifiable, Equatable {
    let id: String
    let rawInput: String
    let bucket: Bucket
    let confidence: Double
    let autoFiled: Bool
    let tier: ModelTier
    let createdAt: Date
    let corrections: [Correction]
}

// Serializes the correction log stored on AuditRecord.correctionsJSON.
enum CorrectionLog {
    static func decode(_ json: String) -> [Correction] {
        guard let data = json.data(using: .utf8),
              let list = try? decoder.decode([Correction].self, from: data) else { return [] }
        return list
    }

    static func encode(_ list: [Correction]) -> String {
        guard let data = try? encoder.encode(list),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
