import LedgerCore
import SwiftUI

/// 統計 (ui/StatsTab.kt): totals, a category donut, what was spent each day, and how it was paid.
struct StatsTab: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    var body: some View {
        let id = trip.id ?? 0
        let expenses = model.read { try Q.expenseRows($0, id) } ?? []
        let memberCount = (model.read { try Q.members($0, id) } ?? []).count
        let total = expenses.reduce(0) { $0 + $1.homeAmount }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if expenses.isEmpty {
                    EmptyState(symbol: "chart.pie", title: "還沒有資料", message: "記幾筆之後,這裡會出現圖表")
                } else {
                    overview(expenses, total: total, memberCount: memberCount)
                    CategoryDonut(expenses: expenses, total: total)
                    DailyBars(trip: trip, expenses: expenses)
                    PaymentBreakdown(expenses: expenses, total: total)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .readableWidth()
        }
    }

    /// Here 日均 is the total over every day of the trip (the ledger card divides by the days so far).
    private func overview(_ expenses: [ExpenseRow], total: Double, memberCount: Int) -> some View {
        let days = max(trip.endDate - trip.startDate + 1, 1)
        let biggest = expenses.max { $0.homeAmount < $1.homeAmount }
        return VStack(alignment: .leading, spacing: 0) {
            Text("總花費(新台幣)").appFont(size: 13, weight: .medium).foregroundStyle(Palette.onSurfaceVariant)
            Text(fmtMoney(total)).appFont(size: 28, weight: .bold).foregroundStyle(Palette.primary).tnum().lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .top) {
                num("日均", fmtPlain(Double(javaRound(total / Double(days)))))
                num("人均", memberCount > 0 ? fmtPlain(Double(javaRound(total / Double(memberCount)))) : "—")
                num("筆數", String(expenses.count))
            }
            .padding(.top, 12)
            if let b = biggest {
                Text(verbatim: "最大一筆:\(b.title.isBlank ? (b.categoryName ?? "") : b.title) \(fmtMoney(b.homeAmount))")
                    .appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant).lineLimit(2).padding(.top, 10)
            }
        }
        .foregroundStyle(Palette.onBackground)
        .ledgerCard(padding: 16)
    }

    private func num(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).appFont(size: 13, weight: .medium).foregroundStyle(Palette.onSurfaceVariant)
            Text(value).appFont(size: 17, weight: .semibold).tnum().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CategoryTotal: Identifiable {
    let name: String
    let style: IconStyle
    let amount: Double
    var id: String { name }
}

private struct CategoryDonut: View {
    let expenses: [ExpenseRow]
    let total: Double

    var body: some View {
        let cats = orderedGroups(expenses) { $0.categoryId }.map { g -> CategoryTotal in
            let r = g.items[0]
            return CategoryTotal(name: r.categoryName ?? "未分類",
                                 style: IconStyle.category(name: r.categoryName, icon: r.categoryIcon, color: r.categoryColor),
                                 amount: g.items.reduce(0) { $0 + $1.homeAmount })
        }.sorted { $0.amount > $1.amount }
        VStack(alignment: .leading, spacing: 10) {
            Text("分類").appFont(size: 16, weight: .semibold)
            // The legend sits beside the ring when it fits, under it with large text.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { ring(cats); legend(cats) }
                VStack(spacing: 12) { ring(cats); legend(cats) }
            }
            Divider().overlay(Palette.hairline)
            ForEach(cats) { c in
                HStack(spacing: 10) {
                    IconTile(symbol: c.style.symbol, color: c.style.color, size: 32)
                    Text(c.name).appFont(size: 15).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(fmtMoney(c.amount)).appFont(size: 15, weight: .semibold).tnum().lineLimit(1).fixedSize()
                }
            }
        }
        .foregroundStyle(Palette.onBackground)
        .ledgerCard(padding: 16)
    }

    private func ring(_ cats: [CategoryTotal]) -> some View {
        ZStack {
            Canvas { context, size in
                let w: CGFloat = 26
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: w / 2, dy: w / 2)
                let center = CGPoint(x: rect.midX, y: rect.midY), radius = rect.width / 2
                context.stroke(Path(ellipseIn: rect), with: .color(Palette.surfaceVariant), lineWidth: w)
                var start = -90.0
                for c in cats where total > 0 {
                    let sweep = c.amount / total * 360
                    var arc = Path()
                    arc.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + max(sweep - 1.2, 0.5)), clockwise: false)
                    context.stroke(arc, with: .color(c.style.color), lineWidth: w)
                    start += sweep
                }
            }
            VStack(spacing: 0) {
                Text("總計").appFont(size: 13, weight: .medium).foregroundStyle(Palette.onSurfaceVariant)
                Text(fmtPlain(Double(javaRound(total)))).appFont(size: 17, weight: .semibold).tnum().lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 30)
        }
        .frame(width: 150, height: 150)
        .accessibilityElement(children: .combine)
    }

    private func legend(_ cats: [CategoryTotal]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(cats.prefix(7)) { c in
                HStack(spacing: 6) {
                    Circle().fill(c.style.color).frame(width: 10, height: 10)
                    Text(c.name).appFont(size: 13).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(verbatim: "\(javaRound(c.amount / total * 100))%").appFont(size: 13, weight: .medium).tnum().fixedSize()
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
        }
        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
    }
}

/// 「每天花多少」: one bar per day of the trip, plus 出發前 when something was paid before it. What was paid
/// after the trip is in the totals but in no bar (as on Android).
private struct DailyBars: View {
    let trip: Trip
    let expenses: [ExpenseRow]

    var body: some View {
        let before = expenses.filter { $0.date < trip.startDate }.reduce(0) { $0 + $1.homeAmount }
        let days = Array(trip.startDate ... max(trip.startDate, trip.endDate))
        let sums = days.map { d in expenses.filter { $0.date == d }.reduce(0) { $0 + $1.homeAmount } }
        var bars: [(label: String, sub: String, value: Double)] = before > 0 ? [("出發前", "", before)] : []
        bars += zip(days, sums).enumerated().map { i, p in ("D\(i + 1)", fmtMonthDay(p.0), p.1) }
        let top = max(bars.map(\.value).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("每天花多少").appFont(size: 16, weight: .semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(bars.indices, id: \.self) { i in
                        let b = bars[i]
                        VStack(spacing: 4) {
                            Text(b.value > 0 ? fmtPlain(Double(javaRound(b.value))) : "").appFont(size: 11).tnum().lineLimit(1).fixedSize()
                                .foregroundStyle(Palette.onSurfaceVariant)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(b.value > 0 ? Palette.primary : Palette.surfaceVariant)
                                .frame(width: 28, height: max(CGFloat(b.value / top) * 110, 4))
                            Text(b.label).appFont(size: 13, weight: .semibold).lineLimit(1).fixedSize()
                            Text(b.sub).appFont(size: 11).foregroundStyle(Palette.onSurfaceVariant).lineLimit(1).fixedSize()
                        }
                        .frame(minWidth: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(b.label) \(b.sub) \(fmtMoney(b.value))")
                    }
                }
                .frame(minHeight: 170, alignment: .bottom)
            }
        }
        .foregroundStyle(Palette.onBackground)
        .ledgerCard(padding: 16)
    }
}

private struct PaymentBreakdown: View {
    let expenses: [ExpenseRow]
    let total: Double

    var body: some View {
        let groups = orderedGroups(expenses) { $0.paymentMethodName ?? "未指定" }
            .map { (name: $0.key, amount: $0.items.reduce(0) { $0 + $1.homeAmount }) }
            .sorted { $0.amount > $1.amount }
        VStack(alignment: .leading, spacing: 10) {
            Text("付款方式").appFont(size: 16, weight: .semibold)
            ForEach(groups, id: \.name) { g in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: Icons.payment(g.name)).font(.system(size: 15)).foregroundStyle(Palette.primary).frame(width: 24)
                        Text(g.name).appFont(size: 15).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: "\(javaRound(total > 0 ? g.amount / total * 100 : 0))%").appFont(size: 13, weight: .medium)
                            .foregroundStyle(Palette.onSurfaceVariant).tnum().fixedSize()
                        Text(fmtMoney(g.amount)).appFont(size: 15, weight: .semibold).tnum().lineLimit(1).fixedSize()
                    }
                    BudgetBar(fraction: total > 0 ? g.amount / total : 0)
                }
            }
        }
        .foregroundStyle(Palette.onBackground)
        .ledgerCard(padding: 16)
    }
}

// MARK: - 分類管理、付款方式管理 (ui/ManageScreens.kt)

struct CategoryManageView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: CategoryDraft?
    @State private var deleting: LedgerCore.Category?

    var body: some View {
        let list = model.read { try Q.categories($0) } ?? []
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Divider().overlay(Palette.hairline).padding(.leading, 64) }
                    let style = IconStyle.category(name: c.name, icon: c.icon, color: c.color)
                    HStack(spacing: 4) {
                        Button { editing = CategoryDraft(c) } label: {
                            HStack(spacing: 12) {
                                IconTile(symbol: style.symbol, color: style.color, size: 40)
                                Text(c.name).appFont(size: 16).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        MoveButtons(index: i, count: list.count) { from, to in model.write { try Q.moveCategory($0, from: from, to: to) } }
                        // 「其他」 is where a deleted category's expenses go, so it stays.
                        Button { deleting = c } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                            .foregroundStyle(c.name == "其他" ? Palette.textMuted : Palette.danger)
                            .disabled(c.name == "其他")
                            .accessibilityLabel("刪除 \(c.name)")
                    }
                    .padding(.leading, 12).padding(.vertical, 6)
                }
            }
            .foregroundStyle(Palette.onBackground)
            .ledgerCard(padding: 0)
            .padding(16)
            .readableWidth()
        }
        .background(Palette.background)
        .navigationTitle("分類管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = CategoryDraft(nil) } label: { Image(systemName: "plus") }.accessibilityLabel("新增分類")
            }
        }
        .sheet(item: $editing) { CategoryEditSheet(draft: $0) }
        .alert("刪除「\(deleting?.name ?? "")」?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { c in
            Button("取消", role: .cancel) {}
            Button("刪除", role: .destructive) { if let id = c.id { model.write { try Q.deleteCategory($0, id) } } }
        } message: { _ in
            Text("使用此分類的支出會改歸「其他」。")
        }
    }
}

struct CategoryDraft: Identifiable {
    let original: LedgerCore.Category?
    var name: String
    var icon: String
    var color: Int
    var id: String { original?.id.map(String.init) ?? "new" }

    init(_ c: LedgerCore.Category?) {
        original = c
        let style = CategoryStyle.resolve(name: c?.name ?? "", icon: c?.icon, color: c?.color)
        name = c?.name ?? ""
        icon = style.icon
        color = style.color
    }
}

private struct CategoryEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: CategoryDraft

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        IconTile(symbol: Icons.category(draft.icon), color: Palette.category(draft.color), size: 48, corner: 14)
                        FieldBox("名稱") {
                            TextField("", text: $draft.name, prompt: Text("例如:按摩").foregroundStyle(Palette.textMuted)).appFont(size: 16)
                        }
                    }
                    SectionHeader("顏色")
                    FlowLayout(spacing: 10, lineSpacing: 10) {
                        ForEach(CategoryStyle.paletteHex.indices, id: \.self) { i in
                            Button { draft.color = i } label: {
                                Circle().fill(Palette.category(i)).frame(width: 36, height: 36)
                                    .overlay { if draft.color == i { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white) } }
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("顏色 \(i + 1)")
                            .accessibilityAddTraits(draft.color == i ? .isSelected : [])
                        }
                    }
                    SectionHeader("圖示")
                    FlowLayout(spacing: 10, lineSpacing: 10) {
                        ForEach(CategoryStyle.iconKeys, id: \.self) { k in
                            Button { draft.icon = k } label: {
                                Image(systemName: Icons.category(k)).font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(draft.icon == k ? Palette.onPrimary : Palette.onBackground)
                                    .background(draft.icon == k ? Palette.category(draft.color) : Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(k)
                            .accessibilityAddTraits(draft.icon == k ? .isSelected : [])
                        }
                    }
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle(draft.original == nil ? "新增分類" : "編輯分類")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if var c = draft.original {
                            c.name = name; c.icon = draft.icon; c.color = draft.color
                            model.write { try Q.updateCategory($0, c) }
                        } else {
                            model.write { try Q.addCategory($0, name: name, icon: draft.icon, color: draft.color) }
                        }
                        dismiss()
                    }
                    .disabled(draft.name.isBlank)
                }
            }
        }
        .tint(Palette.primary)
    }
}

struct PaymentManageView: View {
    @Environment(AppModel.self) private var model
    @State private var naming: PaymentMethod?
    @State private var adding = false
    @State private var name = ""
    @State private var deleting: PaymentMethod?

    var body: some View {
        let list = model.read { try Q.paymentMethods($0) } ?? []
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Divider().overlay(Palette.hairline).padding(.leading, 64) }
                    HStack(spacing: 4) {
                        Button {
                            name = m.name
                            naming = m
                        } label: {
                            HStack(spacing: 12) {
                                IconTile(symbol: Icons.payment(m.name), color: Palette.primary, size: 40)
                                Text(m.name).appFont(size: 16).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        MoveButtons(index: i, count: list.count) { from, to in model.write { try Q.movePaymentMethod($0, from: from, to: to) } }
                        Button { deleting = m } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                            .foregroundStyle(Palette.danger)
                            .accessibilityLabel("刪除 \(m.name)")
                    }
                    .padding(.leading, 12).padding(.vertical, 6)
                }
            }
            .foregroundStyle(Palette.onBackground)
            .ledgerCard(padding: 0)
            .padding(16)
            .readableWidth()
        }
        .background(Palette.background)
        .navigationTitle("付款方式管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    name = ""
                    adding = true
                } label: { Image(systemName: "plus") }.accessibilityLabel("新增付款方式")
            }
        }
        .alert("新增付款方式", isPresented: $adding) {
            TextField("名稱", text: $name)
            Button("取消", role: .cancel) {}
            Button("新增") {
                let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                model.write { try Q.addPaymentMethod($0, name: n) }
            }
            .disabled(name.isBlank)
        }
        .alert("重新命名", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } }), presenting: naming) { m in
            TextField("名稱", text: $name)
            Button("取消", role: .cancel) {}
            Button("儲存") {
                var changed = m
                changed.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                model.write { try Q.updatePaymentMethod($0, changed) }
            }
            .disabled(name.isBlank)
        }
        .alert("刪除「\(deleting?.name ?? "")」?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { m in
            Button("取消", role: .cancel) {}
            Button("刪除", role: .destructive) { if let id = m.id { model.write { try Q.deletePaymentMethod($0, id) } } }
        } message: { _ in
            Text("使用此付款方式的支出會變成未指定。")
        }
    }
}

/// ↑ / ↓ to reorder a list row.
private struct MoveButtons: View {
    let index: Int
    let count: Int
    let move: (Int, Int) -> Void

    var body: some View {
        Button { move(index, index - 1) } label: { Image(systemName: "arrow.up").frame(width: 40, height: 44) }
            .disabled(index == 0)
            .accessibilityLabel("上移")
        Button { move(index, index + 1) } label: { Image(systemName: "arrow.down").frame(width: 40, height: 44) }
            .disabled(index >= count - 1)
            .accessibilityLabel("下移")
    }
}
