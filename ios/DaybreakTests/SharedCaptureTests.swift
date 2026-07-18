import XCTest
import SwiftData
@testable import Daybreak

@MainActor
final class SharedCaptureTests: XCTestCase {
    static let container: ModelContainer = {
        try! ModelContainer(
            for: TaskEntity.self, EventEntity.self, CaptureItem.self,
                ReviewItem.self, AuditRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()

    override func setUp() {
        try? Self.container.mainContext.delete(model: CaptureItem.self)
    }

    private func pending() throws -> [CaptureItem] {
        try Self.container.mainContext.fetch(FetchDescriptor<CaptureItem>())
    }

    func testEnqueueWritesPendingShareCapture() throws {
        SharedCapture.enqueue("read this article", into: Self.container)
        let items = try pending()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].text, "read this article")
        XCTAssertEqual(items[0].source, .share)
        XCTAssertEqual(items[0].status, .pending)
    }

    func testEnqueueTrimsAndIgnoresBlank() throws {
        SharedCapture.enqueue("   ", into: Self.container)
        XCTAssertTrue(try pending().isEmpty)
        SharedCapture.enqueue("  hello  ", into: Self.container)
        XCTAssertEqual(try pending().first?.text, "hello")
    }
}
