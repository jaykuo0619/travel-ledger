import LedgerCore
import SwiftUI
import UIKit

@main
struct TravelLedgerApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.primary)
                .preferredColorScheme(model.settings.theme.colorScheme)
                .environment(\.textScale, model.settings.fontSize.factor)
                // Beyond this the layouts stop fitting; the app's own setting adds up to 25% on top.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
    @Environment(\.horizontalSizeClass) private var widthClass
    @State private var openedAtLaunch = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.wide {
                // iPad: the trips stay on the left, the open trip (or the overview) fills the rest.
                HStack(spacing: 0) {
                    HomeView(sidebar: true)
                        .frame(width: 320)
                    Divider().overlay(Palette.hairline).ignoresSafeArea()
                    NavigationStack(path: $model.path) {
                        Group {
                            if let id = model.selectedTrip { TripView(tripId: id).id(id) } else { TripOverview() }
                        }
                        .navigationDestination(for: Route.self) { destination($0) }
                    }
                }
                .background(Palette.background)
                .coachTour(.home, steps: HomeView.tourSteps(hasTrips: model.read { try Q.tripSummaries($0) }?.isEmpty == false),
                           advanceOn: model.editing != nil)
            } else {
                NavigationStack(path: $model.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { destination($0) }
                }
            }
        }
        .onChange(of: widthClass, initial: true) { _, new in model.layoutChanged(wide: new == .regular) }
        // Swiping back to the list on a phone-width window: no trip is open any more.
        .onChange(of: model.path.isEmpty) { _, empty in
            if empty, !model.wide { model.selectedTrip = nil }
        }
        .sheet(item: $model.editing) { target in
            TripEditView(tripId: target.tripId)
        }
        .sheet(isPresented: $model.showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { model.showSettings = false } }
                    }
            }
            .tint(Palette.primary)
        }
        .background { shortcuts }
        .modifier(ImportHost())
        .overlay(alignment: .bottom) { ToastView() }
        .task {
            // Open the trip that is on (or starts within 30 days) — unless a file is waiting to be imported.
            guard !openedAtLaunch else { return }
            openedAtLaunch = true
            try? await Task.sleep(for: .milliseconds(150))
            if model.incoming == nil, model.path.isEmpty, model.selectedTrip == nil, let id = model.tripToOpenAtLaunch() {
                model.openTrip(id)
            }
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .trip(let id): TripView(tripId: id)
        case .plan(let id): PlanDetailView(planId: id)
        case .expense(let id): ExpenseDetailView(expenseId: id)
        case .settings: SettingsView()
        }
    }

    /// With a keyboard attached: ⌘N new trip, ⌘, settings.
    private var shortcuts: some View {
        Group {
            Button("新增旅程") { model.editing = EditTarget(tripId: nil) }.keyboardShortcut("n", modifiers: .command)
            Button("設定") { model.openSettings() }.keyboardShortcut(",", modifiers: .command)
        }
        // Not on top of a sheet that is already open, or of a settings screen that is already showing.
        .disabled(model.editing != nil || model.showSettings || model.incoming != nil || (!model.wide && !model.path.isEmpty))
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// A short message at the bottom of the screen, like Android's Toast.
struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let text = model.toast {
            Text(text)
                .appFont(size: 15)
                .foregroundStyle(Palette.background)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                // Dark on a light screen, light on a dark one, so it always stands out.
                .background(Palette.onBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

/// The trip screens hide the navigation bar, which also turns off the swipe-back gesture; this keeps it.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
