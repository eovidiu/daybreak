import UIKit
import UniformTypeIdentifiers

// Minimal share extension: pull the shared text (or URL) out of the request, write it to
// the shared store as a pending capture, and return. Classification happens in the app on
// next launch — the extension stays light and never blocks on the model.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            if let text = await sharedText(), !text.isEmpty {
                await MainActor.run { SharedCapture.enqueue(text) }
            }
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func sharedText() async -> String? {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else { return nil }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
            return value as? String
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
            return (value as? URL)?.absoluteString
        }
        return nil
    }
}
