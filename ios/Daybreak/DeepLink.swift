import Foundation

// URLs the app opens itself with (from the widget). The widget doesn't capture text; it
// just deep-links to the capture field.
enum DeepLink: Equatable {
    case capture

    static let scheme = "daybreak"

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == scheme else { return nil }
        return url.host == "capture" ? .capture : nil
    }
}
