import LedgerCore
import SwiftUI

/// The tabs of a trip: plans, the ledger and statistics (今天 is not built yet), with 記一筆 in the middle.
enum ShownTab: String, CaseIterable {
    case plan = "行程", ledger = "帳本", stats = "統計"

    var symbol: String { self == .plan ? "map" : self == .ledger ? "list.bullet.rectangle.portrait" : "chart.pie" }

    /// Before or during the trip: plans; after it: the statistics.
    static func `default`(_ trip: Trip, today: Int64) -> ShownTab {
        switch TripTab.default(start: trip.startDate, end: trip.endDate, today: today) {
        case .plan, .today: return .plan
        case .ledger: return .ledger
        case .stats: return .stats
        }
    }
}

/// One trip (ui/TripDetail.kt): header with the ⋮ menu, read-only banner, and the plan / ledger tabs.
struct TripView: View {
    @Environment(AppModel.self) private var model
    let tripId: Int64
    @State private var tab: ShownTab?
    @State private var confirmDelete = false
    @AppStorage(CoachTour.home.rawValue) private var homeTourDone = false

    var body: some View {
        let today = todayEpochDay()
        if let trip = model.read({ try Q.trip($0, tripId) }) ?? nil {
            let current = tab ?? ShownTab.default(trip, today: today)
            GeometryReader { geo in
                // On an iPad with room for two columns the plan and the ledger are both on screen, no tabs.
                let columns = model.wide && geo.size.width >= 720
                VStack(spacing: 0) {
                    header(trip, today: today).frame(maxWidth: columns ? .infinity : 700).frame(maxWidth: .infinity)
                    if trip.readOnly {
                        ReadOnlyBanner(trip: trip).padding(.horizontal, 16).padding(.vertical, 4)
                            .frame(maxWidth: columns ? .infinity : 700).frame(maxWidth: .infinity)
                    }
                    if columns {
                        HStack(spacing: 0) {
                            column(ShownTab.plan) { PlanTab(trip: trip) }
                                .frame(width: (geo.size.width * 0.54).rounded())
                            Divider().overlay(Palette.hairline)
                            // The right column is the ledger or the statistics; 記一筆 sits in its heading.
                            let right = current == .stats ? ShownTab.stats : ShownTab.ledger
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 10) {
                                    Segmented(options: [ShownTab.ledger.rawValue, ShownTab.stats.rawValue], selected: right == .stats ? 1 : 0) {
                                        tab = $0 == 1 ? .stats : .ledger
                                    }
                                    .frame(maxWidth: 240)
                                    Spacer(minLength: 0)
                                    SmallAdd("記一筆") { model.expenseEditing = ExpenseEditTarget(tripId: tripId) }
                                }
                                .padding(.horizontal, 16).padding(.bottom, 2)
                                if right == .stats { StatsTab(trip: trip) } else { LedgerTab(trip: trip, today: today) }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        Group {
                            switch current {
                            case .plan: PlanTab(trip: trip)
                            case .ledger: LedgerTab(trip: trip, today: today)
                            case .stats: StatsTab(trip: trip)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        TabBar(current: current, onAdd: { model.expenseEditing = ExpenseEditTarget(tripId: tripId) }) { tab = $0 }
                            .coachTarget(.tripTabs)
                    }
                }
            }
            .background(Palette.background)
            .toolbar(.hidden, for: .navigationBar)
            // On an iPad the trip list's tutorial comes first; this one follows it.
            .coachTour(.trip, steps: tourSteps(trip), active: !model.wide || homeTourDone, advanceOn: 0)
            .alert("刪除這趟旅程?", isPresented: $confirmDelete) {
                Button("取消", role: .cancel) {}
                Button("刪除", role: .destructive) {
                    model.deleteTrip(tripId)
                    model.closeTrip()
                }
            } message: {
                Text(trip.readOnly ? "只會刪除你手機上的這份副本,不影響\(trip.sharedBy ?? "")的資料。" : "旅程內的所有帳目、行程與照片都會一併刪除,無法復原。")
            }
        } else {
            Color.clear.background(Palette.background)
        }
    }

    /// The first-run tutorial for a trip.
    private func tourSteps(_ trip: Trip) -> [CoachStep] {
        [
            CoachStep(target: .tripTitle, title: "這趟旅程",
                      text: model.wide ? "這裡是旅程名稱、狀態和日期。左邊的列表可以直接切換到別趟旅程。" : "這裡是旅程名稱、狀態和日期。點它或左邊的箭頭,回到旅程列表。"),
            CoachStep(target: .tripTabs, title: "行程與帳本",
                      text: "「行程」是每天的安排和還沒排日期的「待排」;「帳本」是每一筆花費;「統計」是圖表。中間的「+」是記一筆:輸入金額、選分類就記好了。"),
            CoachStep(target: .planGrouping, title: "依天或依類型", text: "行程可以照日期排,也可以照吃、交通、景點等類型分組。點一個行程或一筆支出,看它的詳細內容。"),
            CoachStep(target: .tripMenu, title: "更多功能",
                      text: trip.readOnly ? "這趟是同伴分享的,對方的內容只能看。你可以補充行程和支出,再按上面的「傳給記帳人」。這裡可以再分享、回到所有旅程,或刪除你手機上的這份副本。" : "這裡可以編輯旅程(名稱、日期、成員、匯率)、把旅程分享給同伴(做成檔案傳到 LINE)、傳到電腦排行程,或刪除旅程。"),
        ]
    }

    /// One of the two side-by-side columns on an iPad, under a small title.
    private func column<Content: View>(_ tab: ShownTab, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(tab.rawValue, systemImage: tab.symbol)
                .appFont(size: 15, weight: .semibold)
                .foregroundStyle(Palette.onSurfaceVariant)
                .modifier(ColumnTitleTarget(on: tab == .plan))
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 6)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ trip: Trip, today: Int64) -> some View {
        HStack(spacing: 4) {
            // Beside the sidebar there is nothing to go back to.
            if !model.wide {
                Button { model.closeTrip() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("所有旅程")
            }
            Button { model.closeTrip() } label: {
                HStack(spacing: 10) {
                    TripCover(path: trip.coverPath, name: trip.name, startDate: trip.startDate, theme: trip.coverTheme)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(trip.name).appFont(size: 21, weight: .bold).lineLimit(1)
                        // One line when it fits; otherwise the status goes above the dates. Never shrunk or cut.
                        let status = tripStatus(start: trip.startDate, end: trip.endDate, today: today)
                        let dates = "\(fmtShortDate(trip.startDate)) – \(fmtShortDate(trip.endDate))"
                        ViewThatFits(in: .horizontal) {
                            Text(verbatim: "\(status) · \(dates)").lineLimit(1)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(status).lineLimit(1)
                                Text(dates).lineLimit(1)
                            }
                        }
                        .appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .coachTarget(.tripTitle)
            Menu {
                if !trip.readOnly {
                    Button { model.editing = EditTarget(tripId: tripId) } label: { Label("編輯旅程", systemImage: "pencil") }
                }
                Button { model.sharing = .trip(tripId) } label: { Label("分享給同伴", systemImage: "square.and.arrow.up") }
                if !trip.readOnly {
                    Button { model.sharing = .desktop(tripId) } label: { Label("傳到電腦排行程", systemImage: "desktopcomputer") }
                }
                Button { model.closeTrip() } label: { Label("所有旅程", systemImage: "suitcase.rolling") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("刪除旅程", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).rotationEffect(.degrees(90))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("更多")
            .coachTarget(.tripMenu)
        }
        .foregroundStyle(Palette.onBackground)
        .padding(.leading, model.wide ? 16 : 0)
        .padding(.trailing, 4)
        .frame(minHeight: 64)
    }
}

/// "X 記帳 · 10/12 21:05 更新" on a trip someone shared with us.
struct ReadOnlyBanner: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    var body: some View {
        let pending = model.read { try Q.pendingCount($0, trip.id ?? 0) } ?? 0
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "eye").font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).appFont(size: 15)
                if pending > 0 { Text(verbatim: "我補充了 \(pending) 項").appFont(size: 13).foregroundStyle(Palette.warning) }
            }
            Spacer(minLength: 0)
            if pending > 0 {
                Button { model.sharing = .additions(trip.id ?? 0) } label: {
                    Text("傳給記帳人").appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
                        .foregroundStyle(Palette.onPrimary)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(Palette.primary, in: Capsule())
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Palette.onSecondaryContainer)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.secondaryContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var text: String {
        var s = "\(trip.sharedBy ?? "") 記帳"
        if let at = trip.sharedAt {
            let c = localDateTime(millis: at)
            s += String(format: " · %d/%d %02d:%02d 更新", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        }
        return s
    }
}

private struct TabBar: View {
    let current: ShownTab
    let onAdd: () -> Void
    let onSelect: (ShownTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.hairline)
            HStack(spacing: 0) {
                item(.plan)
                // 記一筆: the big button in the middle.
                Button(action: onAdd) {
                    Image(systemName: "plus").font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.onPrimary)
                        .frame(width: 56, height: 56)
                        .background(Palette.primary, in: Circle())
                        .shadow(color: Palette.primary.opacity(0.35), radius: 6, y: 3)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("記一筆")
                item(.ledger)
                item(.stats)
            }
            .readableWidth()
        }
        .background(Palette.card.ignoresSafeArea(edges: .bottom))
    }

    private func item(_ t: ShownTab) -> some View {
        let on = t == current
        return Button { onSelect(t) } label: {
            VStack(spacing: 2) {
                Image(systemName: t.symbol).font(.system(size: 18))
                    .padding(.horizontal, 16).padding(.vertical, 3)
                    .background(on ? Palette.primaryContainer : .clear, in: Capsule())
                Text(t.rawValue).appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
            }
            .foregroundStyle(on ? Palette.primary : Palette.onSurfaceVariant)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A small "+ 新增" / "+ 加入" button beside a heading.
struct SmallAdd: View {
    let text: String
    let action: () -> Void

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(text, systemImage: "plus").appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Palette.primaryContainer, in: Capsule())
                .foregroundStyle(Palette.primary)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

/// In two-column mode there is no tab bar; the tutorial points at the first column's title instead.
private struct ColumnTitleTarget: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.coachTarget(.tripTabs) } else { content }
    }
}

// MARK: - Plans

/// Two-way switch ("依天 / 依類型").
struct Segmented: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = i == selected
                Button { onSelect(i) } label: {
                    Text(options[i]).appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
                        .foregroundStyle(on ? Palette.primary : Palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? Palette.card : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.surfaceVariant, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PlanTab: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    @AppStorage("plan_by_type") private var byType = false

    var body: some View {
        let id = trip.id ?? 0
        let plans = model.read { try Q.planRows($0, id) } ?? []
        let notes = Dictionary((model.read { try Q.dayNotes($0, id) } ?? []).map { ($0.day, $0.text) }, uniquingKeysWith: { a, _ in a })
        let needBooking = plans.filter { $0.reservation == Reservation.needed && $0.status == PlanStatus.todo }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Segmented(options: ["依天", "依類型"], selected: byType ? 1 : 0) { byType = $0 == 1 }.coachTarget(.planGrouping)
                    Button { model.pasting = PasteTarget(tripId: id) } label: {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 17)).frame(width: 44, height: 44)
                    }
                    .foregroundStyle(Palette.primary)
                    .accessibilityLabel("貼上多筆")
                    SmallAdd("新增") { model.planEditing = PlanEditTarget(tripId: id) }
                }
                if plans.isEmpty, notes.isEmpty {
                    EmptyState(symbol: "map", title: trip.readOnly ? "對方還沒有安排行程" : "把出發前做的功課放進來",
                               message: trip.readOnly ? "你想去的地方可以先加進來,再按上方「傳給記帳人」。" : "想去的景點、要訂位的餐廳都可以先放進「待排」,之後再排到某一天。")
                } else {
                    if !needBooking.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.badge").foregroundStyle(Palette.danger)
                            Text("\(needBooking.count) 項需要訂位:" + needBooking.map(\.title).joined(separator: "、"))
                                .appFont(size: 15).lineLimit(2)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    }
                    if byType { byTypeList(plans) } else { byDayList(plans, notes: notes) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .readableWidth()
        }
    }

    @ViewBuilder
    private func byDayList(_ plans: [PlanRow], notes: [Int64: String]) -> some View {
        let unscheduled = plans.filter { $0.date == nil }
        let looseNote = notes[unscheduledDay]
        if !unscheduled.isEmpty || looseNote != nil {
            SectionHeader("待排 · \(unscheduled.count) 項")
            if let looseNote { DayNoteCard(text: looseNote, onEdit: noteEditor(unscheduledDay)).id(looseNote) }
            if !unscheduled.isEmpty { PlanCard(rows: unscheduled, trip: trip, showDate: false) }
        }
        ForEach(Array(trip.startDate ... max(trip.startDate, trip.endDate)), id: \.self) { day in
            let rows = plans.filter { $0.date == day }
            HStack(spacing: 0) {
                Text("Day \(day - trip.startDate + 1)").appFont(size: 16, weight: .semibold).foregroundStyle(Palette.primary).fixedSize()
                Text("  \(fmtShortDate(day))").appFont(size: 16, weight: .semibold).lineLimit(1)
                Spacer(minLength: 0)
                if !trip.readOnly, notes[day] == nil {
                    Button { model.dayNoteEditing = DayNoteTarget(tripId: trip.id ?? 0, day: day) } label: {
                        Image(systemName: "note.text.badge.plus").font(.system(size: 17)).frame(width: 44, height: 36)
                    }
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .accessibilityLabel("加當日筆記")
                }
                SmallAdd("加入") { model.planEditing = PlanEditTarget(tripId: trip.id ?? 0, date: day) }
            }
            .padding(.leading, 4).padding(.top, 6)
            if let n = notes[day] { DayNoteCard(text: n, onEdit: noteEditor(day)).id(n) }
            if rows.isEmpty {
                Text("還沒有安排").appFont(size: 15).foregroundStyle(Palette.textMuted).padding(.leading, 4)
            } else {
                PlanCard(rows: rows, trip: trip, showDate: false)
            }
        }
        let outside = plans.filter { p in p.date.map { $0 < trip.startDate || $0 > trip.endDate } ?? false }
        if !outside.isEmpty {
            SectionHeader("旅程日期以外")
            PlanCard(rows: outside, trip: trip, showDate: true)
        }
    }

    /// Editing a day's note; nil on someone else's trip (the note is theirs).
    private func noteEditor(_ day: Int64) -> (() -> Void)? {
        trip.readOnly ? nil : { model.dayNoteEditing = DayNoteTarget(tripId: trip.id ?? 0, day: day) }
    }

    @ViewBuilder
    private func byTypeList(_ plans: [PlanRow]) -> some View {
        let groups = orderedGroups(plans) { $0.categoryName ?? "未分類" }
            .enumerated().sorted { a, b in
                a.element.items.count != b.element.items.count ? a.element.items.count > b.element.items.count : a.offset < b.offset
            }
            .map { $0.element }
        ForEach(groups) { g in
            let name = g.key, rows = g.items
            let style = IconStyle.category(name: rows[0].categoryName, icon: rows[0].categoryIcon, color: rows[0].categoryColor)
            let pending = rows.filter { $0.reservation == Reservation.needed && $0.status == PlanStatus.todo }.count
            HStack(spacing: 6) {
                Image(systemName: style.symbol).font(.system(size: 15)).foregroundStyle(style.color)
                Text("\(name) · \(rows.count)").appFont(size: 16, weight: .semibold)
                Spacer(minLength: 8)
                if pending > 0 { Text("\(pending) 項待訂位").appFont(size: 13, weight: .medium).foregroundStyle(Palette.danger) }
            }
            .padding(.leading, 4).padding(.top, 6)
            PlanCard(rows: rows, trip: trip, showDate: true)
        }
    }
}

struct KeyedGroup<K: Hashable, T>: Identifiable {
    let key: K
    let items: [T]
    var id: K { key }
}

/// Groups in first-seen order (Kotlin's groupBy).
func orderedGroups<T, K: Hashable>(_ items: [T], by key: (T) -> K) -> [KeyedGroup<K, T>] {
    var order: [K] = []
    var map: [K: [T]] = [:]
    for item in items {
        let k = key(item)
        if map[k] == nil { order.append(k) }
        map[k, default: []].append(item)
    }
    return order.map { KeyedGroup(key: $0, items: map[$0]!) }
}

private struct PlanCard: View {
    let rows: [PlanRow]
    let trip: Trip
    let showDate: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { p in
                if p.id != rows.first?.id { Divider().overlay(Palette.hairline).padding(.leading, 60) }
                PlanRowItem(plan: p, trip: trip, showDate: showDate)
            }
        }
        .ledgerCard(padding: 0)
        .padding(.vertical, 0)
    }
}

private struct PlanRowItem: View {
    @Environment(AppModel.self) private var model
    let plan: PlanRow
    let trip: Trip
    let showDate: Bool

    var body: some View {
        let p = plan
        let style = IconStyle.category(name: p.categoryName, icon: p.categoryIcon, color: p.categoryColor)
        let done = p.status == PlanStatus.done
        let skipped = p.status == PlanStatus.skipped
        // Official items on someone else's trip can't be ticked; my own additions can.
        let canTick = !trip.readOnly || p.pending
        HStack(spacing: 4) {
            Button {
                // 已去 ↔ 未去; a skipped one becomes 已去.
                model.write { try Q.setPlanStatus($0, p.id, done ? PlanStatus.todo : PlanStatus.done) }
            } label: {
                ZStack {
                    if done {
                        Circle().fill(Palette.success).frame(width: 26, height: 26)
                            .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
                    } else if skipped {
                        Image(systemName: "minus.circle").font(.system(size: 24)).foregroundStyle(Palette.textMuted)
                    } else {
                        Circle().strokeBorder(style.color, lineWidth: 2).frame(width: 24, height: 24)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canTick)
            .accessibilityLabel(done ? "已去" : skipped ? "跳過" : "未去")
            .accessibilityHint(canTick ? (done ? "點兩下改成未去" : "點兩下標記已去") : "")
            .sensoryFeedback(.success, trigger: done)
            Button { model.path.append(Route.plan(p.id)) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let m = p.minuteOfDay {
                            Text(fmtTime(m)).appFont(size: 16, weight: .semibold).foregroundStyle(Palette.primary).tnum().fixedSize()
                                .padding(.trailing, 2)
                        }
                        Image(systemName: style.symbol).font(.system(size: 14)).foregroundStyle(style.color)
                        Text(p.title).appFont(size: 16, weight: .medium).strikethrough(skipped).lineLimit(1)
                            .foregroundStyle(done || skipped ? Palette.onSurfaceVariant : Palette.onBackground)
                    }
                    let tags = tags(p)
                    if !tags.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 4) {
                            ForEach(tags.indices, id: \.self) { i in Tag(text: tags[i].0, color: tags[i].1) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 5)
    }

    private func tags(_ p: PlanRow) -> [(String, Color)] {
        var out: [(String, Color)] = []
        if showDate { out.append((p.date.map { "Day \($0 - trip.startDate + 1) \(fmtShortDate($0))" } ?? "待排", Palette.onSurfaceVariant)) }
        if p.reservation == Reservation.needed { out.append(("需訂位", Palette.danger)) }
        if p.reservation == Reservation.booked { out.append(("已訂" + (p.reservationNote.isBlank ? "" : " \(p.reservationNote)"), Palette.success)) }
        if p.pending { out.append(("我的補充", Palette.warning)) }
        if let by = p.addedBy { out.append(("\(by) 補充", Palette.warning)) }
        if p.spent > 0 { out.append(("已花 \(fmtMoney(p.spent))", Palette.primary)) }
        if p.photoCount > 0 { out.append(("圖 \(p.photoCount)", Palette.onSurfaceVariant)) }
        return out
    }
}

extension String {
    /// Kotlin's isBlank().
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text).appFont(size: 13, weight: .medium).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A day's note under its heading: one line until tapped, then the whole text with tappable links.
struct DayNoteCard: View {
    let text: String
    /// nil: the note can't be edited here.
    var onEdit: (() -> Void)?
    @State private var open: Bool

    init(text: String, onEdit: (() -> Void)? = nil) {
        self.text = text
        self.onEdit = onEdit
        _open = State(initialValue: text.components(separatedBy: "\n").count <= 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "note.text").font(.system(size: 16)).foregroundStyle(Palette.warning)
                Text(open ? "當日筆記" : "當日筆記 · " + firstLine).appFont(size: 16, weight: .semibold).lineLimit(1)
                Spacer(minLength: 0)
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .accessibilityLabel("編輯筆記")
                }
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .accessibilityLabel(open ? "收起" : "展開")
            }
            if open { LinkText(text: text).appFont(size: 15) }
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
    }

    private var firstLine: String {
        text.components(separatedBy: "\n").first { !$0.isBlank }?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

// MARK: - Ledger

private struct LedgerTab: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    let today: Int64
    @State private var filter: Int64??

    var body: some View {
        let id = trip.id ?? 0
        let expenses = model.read { try Q.expenseRows($0, id) } ?? []
        let memberCount = (model.read { try Q.members($0, id) } ?? []).count
        let shown = filter.map { f in expenses.filter { $0.categoryId == f } } ?? expenses
        let days = orderedGroups(shown) { $0.date }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                SummaryCard(trip: trip, memberCount: memberCount, expenses: expenses, today: today)
                if !expenses.isEmpty {
                    CategoryCard(expenses: expenses, selected: filter) { c in filter = filter == .some(c) ? nil : .some(c) }
                } else {
                    EmptyState(symbol: "list.bullet.rectangle.portrait", title: "還沒有支出",
                               message: trip.readOnly ? "對方還沒有記帳;你記的會先算「我的補充」" : "點「+ 記一筆」記下第一筆")
                }
                ForEach(days) { g in
                    let date = g.key, rows = g.items
                    DayHeader(trip: trip, date: date, trailing: fmtMoney(rows.reduce(0) { $0 + $1.homeAmount }))
                    VStack(spacing: 0) {
                        ForEach(rows) { e in
                            if e.id != rows.first?.id { Divider().overlay(Palette.hairline).padding(.leading, 66) }
                            ExpenseRowItem(row: e, tripReadOnly: trip.readOnly)
                        }
                    }
                    .ledgerCard(padding: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .readableWidth()
        }
    }
}

/// "6月12日 週三  第 3 天 ............ NT$ 1,707"
struct DayHeader: View {
    let trip: Trip
    let date: Int64
    let trailing: String?

    var body: some View {
        HStack(spacing: 0) {
            Text(fmtDayHeader(date)).appFont(size: 16, weight: .semibold).lineLimit(1).fixedSize()
            Text(date < trip.startDate ? "  出發前" : date > trip.endDate ? "  旅程後" : "  第 \(date - trip.startDate + 1) 天")
                .appFont(size: 13).foregroundStyle(Palette.textMuted).lineLimit(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).appFont(size: 16, weight: .semibold).foregroundStyle(Palette.onSurfaceVariant).tnum().lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

private struct SummaryCard: View {
    let trip: Trip
    let memberCount: Int
    let expenses: [ExpenseRow]
    let today: Int64

    var body: some View {
        let total = expenses.reduce(0) { $0 + $1.homeAmount }
        let length = max(trip.endDate - trip.startDate + 1, 1)
        let elapsed = min(max(today - trip.startDate + 1, 1), length)
        let onTrip = today >= trip.startDate && today <= trip.endDate
        let budget = trip.budget.flatMap { $0 > 0 ? $0 : nil }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("總花費(新台幣)").appFont(size: 13, weight: .medium).foregroundStyle(Palette.onSurfaceVariant)
                    Text(fmtMoney(total)).appFont(size: 28, weight: .bold).foregroundStyle(Palette.primary).tnum()
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                if let budget {
                    let f = total / budget
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: "\(javaRound(f * 100))%").appFont(size: 17, weight: .semibold).foregroundStyle(budgetColor(f))
                        Text("預算 \(fmtMoney(budget))").appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant).lineLimit(1).fixedSize()
                    }
                }
            }
            if let budget { BudgetBar(fraction: total / budget).padding(.top, 10) }
            HStack(alignment: .top) {
                if onTrip {
                    stat("今天", fmtPlain(Double(javaRound(expenses.filter { $0.date == today }.reduce(0) { $0 + $1.homeAmount }))))
                }
                stat("日均", fmtPlain(Double(javaRound(total / Double(elapsed)))))
                stat("人均", memberCount > 0 ? fmtPlain(Double(javaRound(total / Double(memberCount)))) : "—")
                if !onTrip { stat("筆數", "\(expenses.count)") }
            }
            .padding(.top, 12)
        }
        .foregroundStyle(Palette.onBackground)
        .ledgerCard(padding: 16)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).appFont(size: 13, weight: .medium).foregroundStyle(Palette.onSurfaceVariant)
            Text(value).appFont(size: 17, weight: .semibold).tnum().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stacked share bar plus a two-column legend; tapping a category filters the list below.
private struct CategoryCard: View {
    @Environment(\.colorScheme) private var scheme
    let expenses: [ExpenseRow]
    /// nil = everything; .some(nil) = 未分類.
    let selected: Int64??
    let onSelect: (Int64?) -> Void

    private struct CatTotal: Identifiable {
        let id: Int64?
        let name: String
        let style: IconStyle
        let amount: Double
    }

    var body: some View {
        let total = expenses.reduce(0) { $0 + $1.homeAmount }
        if total > 0 {
            let cats = orderedGroups(expenses) { $0.categoryId }.map { g -> CatTotal in
                let rows = g.items
                return CatTotal(id: g.key, name: rows[0].categoryName ?? "未分類",
                         style: IconStyle.category(name: rows[0].categoryName, icon: rows[0].categoryIcon, color: rows[0].categoryColor),
                         amount: rows.reduce(0) { $0 + $1.homeAmount })
            }.sorted { $0.amount > $1.amount }
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(cats.indices, id: \.self) { i in
                            let c = cats[i]
                            Rectangle().fill(selected == nil || selected == .some(c.id) ? c.style.color : c.style.color.opacity(0.25))
                                .frame(width: geo.size.width * CGFloat(max(c.amount / total, 0.001)))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                VStack(spacing: 8) {
                    ForEach(Array(stride(from: 0, to: cats.count, by: 2)), id: \.self) { i in
                        HStack(spacing: 8) {
                            ForEach(cats[i ..< min(i + 2, cats.count)]) { c in legend(c, total: total) }
                            if i + 1 >= cats.count { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                        }
                    }
                }
                if selected != nil {
                    HStack { Spacer(); Button("顯示全部") { if case .some(let s) = selected { onSelect(s) } } }
                }
            }
            .ledgerCard(padding: 14)
        }
    }

    private func legend(_ c: CatTotal, total: Double) -> some View {
        let on = selected == .some(c.id)
        return Button { onSelect(c.id) } label: {
            HStack(spacing: 8) {
                IconTile(symbol: c.style.symbol, color: c.style.color, size: 30, corner: 9)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(c.name).appFont(size: 15).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: "\(javaRound(c.amount / total * 100))%").appFont(size: 13, weight: .medium).foregroundStyle(c.style.color).fixedSize()
                    }
                    Text(fmtMoney(c.amount)).appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant).tnum().lineLimit(1)
                }
            }
            .foregroundStyle(Palette.onBackground)
            .padding(.horizontal, 6).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(on ? c.style.color.opacity(scheme == .dark ? 0.2 : 0.1) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? c.style.color : .clear))
        }
        .buttonStyle(.plain)
    }
}

struct ExpenseRowItem: View {
    @Environment(AppModel.self) private var model
    let row: ExpenseRow
    /// The trip is someone else's: only my own additions open the editor, the rest are read-only.
    var tripReadOnly = false
    /// The trip the expense belongs to (for opening the editor).
    var tripId: Int64?

    var body: some View {
        let e = row
        let style = IconStyle.category(name: e.categoryName, icon: e.categoryIcon, color: e.categoryColor)
        Button {
            let owner = tripId ?? (model.read { try Q.expense($0, e.id) } ?? nil)?.tripId
            if let owner, !tripReadOnly || e.pending {
                model.expenseEditing = ExpenseEditTarget(tripId: owner, expenseId: e.id)
            } else {
                model.path.append(Route.expense(e.id))
            }
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: style.symbol, color: style.color, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title.isBlank ? (e.categoryName ?? "未分類") : e.title).appFont(size: 16, weight: .medium).lineLimit(1)
                    Text([e.categoryName ?? "未分類", e.paymentMethodName, e.minuteOfDay.map(fmtTime)].compactMap { $0 }.joined(separator: " · "))
                        .appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant).lineLimit(1)
                    if let who = e.pending ? "我的補充 · 還沒傳給記帳人" : e.addedBy.map({ "\($0) 補充" }) {
                        Text(who).appFont(size: 13, weight: .medium).foregroundStyle(Palette.warning).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 1) {
                    if e.currency != homeCurrency {
                        Text(fmtAmount(e.amount, e.currency)).appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant).tnum().lineLimit(1).fixedSize()
                    }
                    Text(fmtMoney(e.homeAmount)).appFont(size: 16, weight: .semibold).tnum().lineLimit(1).fixedSize()
                }
                if let thumb = e.thumbPath {
                    LocalImage(path: thumb, maxPixel: 160) { Palette.surfaceVariant }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .foregroundStyle(Palette.onBackground)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
