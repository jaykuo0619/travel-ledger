import LedgerCore
import SwiftUI

@main
struct TravelLedgerApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.primary)
                .preferredColorScheme(model.settings.theme.colorScheme)
                .dynamicTypeSize(model.settings.fontSize.dynamicType)
                // A .zip opened with 卡溜趴 from LINE, Files or AirDrop.
                .onOpenURL { url in model.receive(url) }
                .modifier(BrandSplashCover())
        }
    }
}

/// Screens reachable by navigation.
enum Route: Hashable {
    case trip(Int64)
    case plan(Int64)
    case expense(Int64)
    case settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var openedAtLaunch = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .trip(let id): TripView(tripId: id)
                    case .plan(let id): PlanDetailView(planId: id)
                    case .expense(let id): ExpenseDetailView(expenseId: id)
                    case .settings: SettingsView()
                    }
                }
        }
        .sheet(item: $model.editing) { target in
            TripEditView(tripId: target.tripId)
        }
        .modifier(ImportHost())
        .overlay(alignment: .bottom) { ToastView() }
        .task {
            // Open the trip that is on (or starts within 30 days) — unless a file is waiting to be imported.
            guard !openedAtLaunch else { return }
            openedAtLaunch = true
            try? await Task.sleep(for: .milliseconds(150))
            if model.incoming == nil, model.path.isEmpty, let id = model.tripToOpenAtLaunch() {
                model.path.append(Route.trip(id))
            }
        }
    }
}

/// A short message at the bottom of the screen, like Android's Toast.
struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let text = model.toast {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(text)
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(text.count > 16 ? 3.5 : 2.2))
                    withAnimation { if model.toast == text { model.toast = nil } }
                }
                .allowsHitTesting(false)
        }
    }
}
