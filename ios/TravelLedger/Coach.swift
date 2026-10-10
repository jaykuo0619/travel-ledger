import SwiftUI

/// Places the first-run tutorial can point at.
enum CoachTarget: Hashable {
    case addTrip, settings, tripList
    case editCover, editName, editDates, editMembers
    case tripTitle, tripTabs, planGrouping, tripMenu
}

/// One step of a tutorial: what lights up, and what it says.
struct CoachStep {
    /// nil: nothing is highlighted, the card sits in the middle of the screen.
    var target: CoachTarget?
    let title: String
    let text: String
    /// The highlighted control can be tapped for real; doing so moves the tutorial on.
    var tappable = false
}

/// The three tutorials; each is shown once (設定 →「重看教學」 brings them back).
enum CoachTour: String, CaseIterable {
    case home = "tour_home_done", edit = "tour_edit_done", trip = "tour_trip_done"

    static func reset(_ defaults: UserDefaults = .standard) {
        allCases.forEach { defaults.set(false, forKey: $0.rawValue) }
    }
}

private struct CoachFramesKey: PreferenceKey {
    static let defaultValue: [CoachTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachTarget: Anchor<CGRect>], nextValue: () -> [CoachTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as something a tutorial step can light up.
    func coachTarget(_ target: CoachTarget) -> some View {
        anchorPreference(key: CoachFramesKey.self, value: .bounds) { [target: $0] }
    }

    /// Shows [steps] over this view the first time: the screen dims, the step's target stays lit, a card explains
    /// it. [advanceOn]: when this value changes during a tappable step (the user did what it asked), the tutorial
    /// moves on by itself.
    func coachTour<Trigger: Equatable>(_ tour: CoachTour, steps: [CoachStep], active: Bool = true, advanceOn: Trigger) -> some View {
        modifier(CoachOverlay(tour: tour, steps: steps, active: active, trigger: advanceOn))
    }
}

private struct CoachOverlay<Trigger: Equatable>: ViewModifier {
    let tour: CoachTour
    let steps: [CoachStep]
    let active: Bool
    let trigger: Trigger
    @AppStorage private var done: Bool
    @State private var index = 0

    init(tour: CoachTour, steps: [CoachStep], active: Bool, trigger: Trigger) {
        self.tour = tour
        self.steps = steps
        self.active = active
        self.trigger = trigger
        _done = AppStorage(wrappedValue: false, tour.rawValue)
    }

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(CoachFramesKey.self) { anchors in
                if active, !done, steps.indices.contains(index) {
                    GeometryReader { geo in
                        let step = steps[index]
                        let hole = step.target.flatMap { anchors[$0] }.map { geo[$0].insetBy(dx: -6, dy: -6) }
                        layer(step, hole: hole, in: geo.size)
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: trigger) { _, _ in
                if active, !done, steps.indices.contains(index), steps[index].tappable { next() }
            }
            .onChange(of: done) { _, now in if !now { index = 0 } }
    }

    private func layer(_ step: CoachStep, hole: CGRect?, in size: CGSize) -> some View {
        let shade = Spotlight(hole: hole)
        // Card under the lit area when that is in the upper half, above it otherwise; centred when nothing is lit.
        let below = hole.map { $0.midY < size.height / 2 } ?? false
        return ZStack(alignment: hole == nil ? .center : below ? .top : .bottom) {
            shade.fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                // Outside the lit area taps do nothing; inside it they reach the control when the step allows.
                .contentShape(step.tappable && hole != nil ? AnyShape(shade) : AnyShape(Rectangle().inset(by: -3000)), eoFill: true)
                .onTapGesture {}
            if let hole {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)
                    .allowsHitTesting(false)
            }
            card(step)
                .padding(.horizontal, 16)
                .padding(.top, hole != nil && below ? min((hole?.maxY ?? 0) + 14, size.height - 220) : 0)
                .padding(.bottom, hole != nil && !below ? max(size.height - (hole?.minY ?? 0) + 14, 0) : 0)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private func card(_ step: CoachStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title).appFont(size: 17, weight: .bold)
            Text(step.text).appFont(size: 15).fixedSize(horizontal: false, vertical: true)
            if step.tappable {
                Label("點亮起來的地方試試看", systemImage: "hand.tap").appFont(size: 13, weight: .medium)
                    .foregroundStyle(Palette.primary)
            }
            // Side by side when they fit; stacked with large text.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { skip; Spacer(minLength: 8); forward }
                VStack(alignment: .trailing, spacing: 6) { forward; skip }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Palette.onBackground)
        .padding(16)
        .frame(maxWidth: 380, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    private var skip: some View {
        Button("跳過教學") { withAnimation { done = true } }
            .appFont(size: 15)
            .foregroundStyle(Palette.onSurfaceVariant)
            .frame(minHeight: 44)
    }

    private var forward: some View {
        Button { next() } label: {
            Text(index == steps.count - 1 ? "完成" : "下一步 \(index + 1)/\(steps.count)")
                .appFont(size: 15, weight: .semibold)
                .foregroundStyle(Palette.onPrimary)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Palette.primary, in: Capsule())
        }
    }

    private func next() {
        withAnimation {
            if index >= steps.count - 1 { done = true } else { index += 1 }
        }
    }
}

/// Everything (well beyond the view, so the whole screen dims) except a rounded hole.
private struct Spotlight: Shape {
    let hole: CGRect?

    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -3000, dy: -3000))
        if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14), style: .continuous) }
        return p
    }
}
