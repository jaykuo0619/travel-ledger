import LedgerCore
import SwiftUI

/// The trip list (ui/HomeScreen.kt).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    /// On an iPad this list is the sidebar: every trip is a compact row and the open one is marked.
    var sidebar = false
    @State private var filter: TripFilter?
    @State private var deleting: TripSummary?

    var body: some View {
        let today = todayEpochDay()
        let trips = model.read { try Q.tripSummaries($0) } ?? []
        let activeCount = trips.filter { $0.endDate >= today }.count
        let current = filter ?? TripFilter.initial(trips, today: today)
        let shown = current.apply(trips, today: today)

        ScrollView {
            LazyVStack(spacing: 12) {
                // With an active or upcoming trip the list is a switcher; adding is a small "+" in the header.
                header(showAdd: sidebar || activeCount > 0)
                if activeCount == 0, !sidebar {
                    PillButton("新增旅程", symbol: "plus", height: 50) { model.editing = EditTarget(tripId: nil) }
                }
                if !trips.isEmpty {
                    FilterTabs(selected: current, counts: [
                        .active: activeCount, .ended: trips.count - activeCount, .all: trips.count,
                    ]) { filter = $0 }
                }
                if shown.isEmpty, !(sidebar && trips.isEmpty) {
                    EmptyState(symbol: "airplane.departure", title: trips.isEmpty ? "還沒有旅程" : "這裡沒有旅程",
                               message: trips.isEmpty ? "建立第一趟旅程,開始記錄每一筆花費" : "切換上方分頁看看其他旅程")
                }
                ForEach(shown) { t in
                    Button { model.openTrip(t.id) } label: {
                        if sidebar {
                            CompactTripCard(trip: t, today: today, selected: t.id == model.selectedTrip)
                        } else if t.id == shown.first?.id {
                            FeaturedTripCard(trip: t, today: today)
                        } else {
                            CompactTripCard(trip: t, today: today)
                        }
                    }
                    .buttonStyle(PressStyle())
                    .tripActions(t, deleting: $deleting)
                }
            }
            .padding(.horizontal, sidebar ? 12 : 16)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .deleteTripAlert($deleting)
    }

    private func header(showAdd: Bool) -> some View {
        HStack(spacing: 12) {
            AppIconView(size: 44)
            // Name + version on one line, the author's signature underneath so it never gets cut off.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("卡溜趴").appFont(size: 21, weight: .bold).lineLimit(1)
                    if !model.appVersion.isEmpty {
                        Text("v\(model.appVersion)").appFont(size: 13, weight: .medium).foregroundStyle(Palette.textMuted).lineLimit(1)
                    }
                }
                AuthorSignature(size: 15)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showAdd {
                Button { model.editing = EditTarget(tripId: nil) } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Palette.secondaryContainer, in: Circle())
                }
                .accessibilityLabel("新增旅程")
            }
            Button { model.openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 20)).frame(width: 44, height: 44)
            }
            .foregroundStyle(Palette.onBackground)
            .accessibilityLabel("設定")
        }
        .padding(.vertical, 10)
    }
}

/// Dims a card slightly while it is pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct FilterTabs: View {
    let selected: TripFilter
    let counts: [TripFilter: Int]
    let onSelect: (TripFilter) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TripFilter.allCases, id: \.self) { f in
                let on = f == selected
                Button { onSelect(f) } label: {
                    Text("\(f.rawValue) \(counts[f] ?? 0)")
                        .appFont(size: 15, weight: .semibold)
                        .lineLimit(1).minimumScaleFactor(0.9)
                        .foregroundStyle(on ? Palette.primary : Palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(on ? Palette.card : Palette.surfaceVariant, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Palette.surfaceVariant, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Who shared it, how many people, which currencies; wraps instead of squeezing.
private struct TripMeta: View {
    let trip: TripSummary

    var body: some View {
        FlowLayout(spacing: 14, lineSpacing: 2) {
            if let by = trip.sharedBy { MetaItem(symbol: "eye", text: "\(by) 分享") }
            if trip.memberCount > 0 { MetaItem(symbol: "person.2", text: "\(trip.memberCount) 人") }
            if !trip.currencies.isEmpty { MetaItem(symbol: "dollarsign.arrow.circlepath", text: trip.currencies.joined(separator: " · ")) }
        }
    }
}

private struct FeaturedTripCard: View {
    let trip: TripSummary
    let today: Int64

    var body: some View {
        let t = trip
        VStack(alignment: .leading, spacing: 0) {
            TripCover(path: t.coverPath, name: t.name, startDate: t.startDate, theme: t.coverTheme)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    CoverBadge(text: tripStatus(start: t.startDate, end: t.endDate, today: today)).padding(12)
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(t.name).appFont(size: 21, weight: .bold).lineLimit(1)
                Text(fmtRange(t.startDate, t.endDate)).appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                TripMeta(trip: t)
                Spacer().frame(height: 4)
                let budget = t.budget.flatMap { $0 > 0 ? $0 : nil }
                if let budget { BudgetBar(fraction: t.totalHome / budget).padding(.bottom, 2) }
                // Spent and budget share a line when they fit; with large text the budget moves underneath.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom) {
                        spent
                        Spacer(minLength: 12)
                        if let budget { budgetText(budget, alignment: .trailing) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        spent
                        if let budget { budgetText(budget, alignment: .leading) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .foregroundStyle(Palette.onBackground)
        .ledgerCard(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }

    private var spent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("已花費").appFont(size: 13, weight: .medium).foregroundStyle(Palette.onSurfaceVariant)
            Text(fmtMoney(trip.totalHome)).appFont(size: 21, weight: .bold).tnum().lineLimit(1).fixedSize()
        }
    }

    private func budgetText(_ budget: Double, alignment: HorizontalAlignment) -> some View {
        let f = trip.totalHome / budget
        return VStack(alignment: alignment, spacing: 0) {
            Text("\(javaRound(f * 100))%").appFont(size: 16, weight: .semibold).foregroundStyle(budgetColor(f))
            Text("預算 \(fmtMoney(budget))").appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant).lineLimit(1).fixedSize()
        }
    }
}

private struct CompactTripCard: View {
    let trip: TripSummary
    let today: Int64
    var selected = false

    var body: some View {
        let t = trip
        // Text gets the full width beside the cover; the amount sits on the last line.
        HStack(spacing: 12) {
            TripCover(path: t.coverPath, name: t.name, startDate: t.startDate, theme: t.coverTheme)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(t.name).appFont(size: 17, weight: .semibold).lineLimit(2).multilineTextAlignment(.leading)
                Text(fmtRange(t.startDate, t.endDate)).appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                Text(tripStatus(start: t.startDate, end: t.endDate, today: today)).appFont(size: 13).foregroundStyle(Palette.primary)
                HStack(alignment: .center) {
                    TripMeta(trip: t).frame(maxWidth: .infinity, alignment: .leading)
                    Text(fmtMoney(t.totalHome)).appFont(size: 16, weight: .semibold).tnum().lineLimit(1).fixedSize()
                        .padding(.leading, 8)
                }
            }
        }
        .foregroundStyle(Palette.onBackground)
        .ledgerCard(padding: 10)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.primary, lineWidth: 2)
            }
        }
    }
}

// MARK: - iPad

/// What the iPad shows beside the sidebar while no trip is open: every trip as a large card.
struct TripOverview: View {
    @Environment(AppModel.self) private var model
    @State private var deleting: TripSummary?

    var body: some View {
        let today = todayEpochDay()
        let trips = TripFilter.all.apply(model.read { try Q.tripSummaries($0) } ?? [], today: today)
        ScrollView {
            if trips.isEmpty {
                VStack(spacing: 20) {
                    EmptyState(symbol: "airplane.departure", title: "還沒有旅程", message: "建立第一趟旅程,開始記錄每一筆花費")
                    PillButton("新增旅程", symbol: "plus", height: 50) { model.editing = EditTarget(tripId: nil) }
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("所有旅程").appFont(size: 21, weight: .bold).foregroundStyle(Palette.onBackground)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(trips) { t in
                            Button { model.openTrip(t.id) } label: { FeaturedTripCard(trip: t, today: today) }
                                .buttonStyle(PressStyle())
                                .tripActions(t, deleting: $deleting)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .deleteTripAlert($deleting)
    }
}

private extension View {
    /// Pointer highlight and the long-press menu on a trip card.
    func tripActions(_ trip: TripSummary, deleting: Binding<TripSummary?>) -> some View {
        modifier(TripActions(trip: trip, deleting: deleting))
    }

    func deleteTripAlert(_ deleting: Binding<TripSummary?>) -> some View {
        modifier(DeleteTripAlert(deleting: deleting))
    }
}

private struct TripActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let trip: TripSummary
    @Binding var deleting: TripSummary?

    func body(content: Content) -> some View {
        content
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .hoverEffect(.highlight)
            .contextMenu {
                if trip.sharedBy == nil {
                    Button { model.editing = EditTarget(tripId: trip.id) } label: { Label("編輯旅程", systemImage: "pencil") }
                }
                Button(role: .destructive) { deleting = trip } label: { Label("刪除旅程", systemImage: "trash") }
            }
    }
}

/// The same question the trip screen asks before deleting.
private struct DeleteTripAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var deleting: TripSummary?

    func body(content: Content) -> some View {
        content.alert("刪除這趟旅程?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { t in
            Button("取消", role: .cancel) {}
            Button("刪除", role: .destructive) {
                model.deleteTrip(t.id)
                if model.selectedTrip == t.id { model.closeTrip() }
            }
        } message: { t in
            Text(t.sharedBy != nil ? "只會刪除你手機上的這份副本,不影響\(t.sharedBy ?? "")的資料。" : "旅程內的所有帳目、行程與照片都會一併刪除,無法復原。")
        }
    }
}
