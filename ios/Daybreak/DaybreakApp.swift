import SwiftUI
import SwiftData

@main
struct DaybreakApp: App {
    @StateObject private var store: PlannerStore

    init() {
        let container = SharedStore.container()
        // App.init runs on the main thread; LocalStore/PlannerStore are @MainActor.
        let store = MainActor.assumeIsolated { () -> PlannerStore in
            let local = LocalStore(container: container)
            if ProcessInfo.processInfo.arguments.contains("UITEST_RESET") {
                try? local.deleteAll()
                UserDefaults.standard.removeObject(forKey: CaptureThreshold.key)
            }
            return PlannerStore(api: local)
        }
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.bootstrap() }
                .onOpenURL { store.open($0) }
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: PlannerStore

    var body: some View {
        Group {
            if store.checkedSession {
                PlannerView()
                    .tint(Theme.ink)
            } else {
                ZStack { Theme.paper.ignoresSafeArea(); ProgressView().tint(Theme.muted) }
            }
        }
        .alert("Something went wrong", isPresented: .init(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .background(AppearanceProbe())
    }
}

// Exposes the resolved color scheme to UI tests so they can assert the app stays
// light even when the system is in Dark Mode.
struct AppearanceProbe: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(scheme == .dark ? "appearance-dark" : "appearance-light")
    }
}
