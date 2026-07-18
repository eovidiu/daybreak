import Foundation

// Extracts a day/time/duration from a captured line and returns the phrases it
// consumed so the title can be cleaned. All matching is case-insensitive on a
// lowercased copy; "today" is supplied as yyyy-MM-dd (device-local).
enum DateTimeParser {
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday",
                                   "thursday", "friday", "saturday"]

    private static func firstMatch(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        else { return nil }
        var groups: [String] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: s) { groups.append(String(s[r])) }
            else { groups.append("") }
        }
        return groups
    }

    // "for 30 min", "30 minutes", "1 hour", "30m", "1h" -> minutes + matched phrase.
    static func duration(in s: String) -> (Int?, String?) {
        guard let g = firstMatch(#"(for\s+)?(\d+)\s*(hours?|hrs?|h|minutes?|mins?|m)\b"#, in: s)
        else { return (nil, nil) }
        let n = Int(g[2]) ?? 0
        let unit = g[3].lowercased()
        let minutes = unit.hasPrefix("h") ? n * 60 : n
        return (minutes, g[0])
    }

    // "3pm", "3:30pm", "15:00", "at 9" -> minutes-from-midnight + matched phrase.
    static func time(in s: String) -> (Int?, String?) {
        if let g = firstMatch(#"\b(?:at\s+)?(\d{1,2}):(\d{2})\s*(am|pm)?"#, in: s) {
            var h = Int(g[1]) ?? 0
            let m = Int(g[2]) ?? 0
            let mer = g[3].lowercased()
            if mer == "pm" && h < 12 { h += 12 }
            if mer == "am" && h == 12 { h = 0 }
            return (h * 60 + m, g[0])
        }
        if let g = firstMatch(#"\b(?:at\s+)?(\d{1,2})\s*(am|pm)\b"#, in: s) {
            var h = Int(g[1]) ?? 0
            let mer = g[2].lowercased()
            if mer == "pm" && h < 12 { h += 12 }
            if mer == "am" && h == 12 { h = 0 }
            return (h * 60, g[0])
        }
        if let g = firstMatch(#"\bat\s+(\d{1,2})(:(\d{2}))?\b"#, in: s) {
            let h = Int(g[1]) ?? 0
            let m = Int(g[3]) ?? 0
            return (h * 60 + m, g[0])
        }
        return (nil, nil)
    }

    // Returns (day yyyy-MM-dd?, matched phrase?, tonight flag).
    static func date(in s: String, today: String) -> (String?, String?, Bool) {
        if s.range(of: #"\btonight\b"#, options: .regularExpression) != nil {
            return (today, "tonight", true)
        }
        if s.range(of: #"\btoday\b"#, options: .regularExpression) != nil {
            return (today, "today", false)
        }
        if s.range(of: #"\btomorrow\b"#, options: .regularExpression) != nil {
            return (add(today, 1), "tomorrow", false)
        }
        if let g = firstMatch(#"\bin\s+(\d+)\s+days?\b"#, in: s), let n = Int(g[1]) {
            return (add(today, n), g[0], false)
        }
        if let g = firstMatch(#"\bnext\s+(\#(weekdays.joined(separator: "|")))\b"#, in: s) {
            return (weekdayDate(g[1], today: today, next: true), g[0], false)
        }
        if let g = firstMatch(#"\b(\#(weekdays.joined(separator: "|")))\b"#, in: s) {
            return (weekdayDate(g[1], today: today, next: false), g[0], false)
        }
        return (nil, nil, false)
    }

    // Removes the consumed phrases from the ORIGINAL text and tidies it.
    static func cleanTitle(original: String, remove phrases: [String]) -> String {
        var t = original
        for p in phrases where !p.isEmpty {
            if let r = t.range(of: p, options: .caseInsensitive) {
                t.replaceSubrange(r, with: " ")
            }
        }
        let collapsed = t.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    // MARK: date math

    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }

    private static func parse(_ day: String) -> Date? {
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func add(_ day: String, _ n: Int) -> String {
        guard let d = parse(day), let moved = cal.date(byAdding: .day, value: n, to: d)
        else { return day }
        return format(moved)
    }

    // Next future occurrence of a weekday (today excluded); +7 more for "next".
    private static func weekdayDate(_ name: String, today: String, next: Bool) -> String {
        guard let d = parse(today), let target = weekdays.firstIndex(of: name.lowercased())
        else { return today }
        let todayWeekday = cal.component(.weekday, from: d) - 1  // 0=Sunday
        var delta = (target - todayWeekday + 7) % 7
        if delta == 0 { delta = 7 }               // not today
        if next { delta += 7 }
        return add(today, delta)
    }
}
