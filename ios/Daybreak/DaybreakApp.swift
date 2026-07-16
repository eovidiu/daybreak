import SwiftUI

@main
struct DaybreakApp: App {
    @StateObject private var store = PlannerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.bootstrap() }
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
    }
}
