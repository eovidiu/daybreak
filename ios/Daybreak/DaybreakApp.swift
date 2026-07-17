import SwiftUI

@main
struct DaybreakApp: App {
    @StateObject private var store = PlannerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.bootstrap() }
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: PlannerStore

    var body: some View {
        Group {
            if !store.checkedSession {
                ZStack { Theme.paper.ignoresSafeArea(); ProgressView().tint(Theme.muted) }
            } else if store.user == nil {
                AuthView()
            } else {
                PlannerView()
                    .tint(Theme.ink)
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
