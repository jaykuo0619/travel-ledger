import LedgerCore
import SwiftUI
import UIKit

// Reading one plan item or one expense (ui/ReadOnlyScreens.kt), the photo viewer, and tappable links.

/// Text whose web addresses and phone numbers are underlined and open when tapped.
struct LinkText: View {
    let text: String

    var body: some View { Text(Self.attributed(text)).tint(Palette.primary) }

    static func attributed(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return out }
        let ns = text as NSString
        for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(m.range, in: text), let r = Range(range, in: out) else { continue }
            let url: URL?
            if m.resultType == .phoneNumber, let phone = m.phoneNumber {
                url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" })
            } else {
                url = m.url
            }
            guard let url else { continue }
            out[r].link = url
            out[r].underlineStyle = .single
        }
        return out
    }
}

/// Icon · label · value rows in one card.
private struct DetailCard: View {
    let lines: [(symbol: String, label: String, value: String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(lines.indices, id: \.self) { i in
                if i > 0 { Divider().overlay(Palette.hairline).padding(.leading, 50) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: lines[i].symbol).foregroundStyle(Palette.onSurfaceVariant).frame(width: 24)
                    Text(lines[i].label).font(.system(size: 15)).foregroundStyle(Palette.onSurfaceVariant).frame(width: 72, alignment: .leading)
                    LinkText(text: lines[i].value).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .ledgerCard(padding: 0)
    }
}

/// One plan item, to read; editing comes with stage 3.
struct PlanDetailView: View {
    @Environment(AppModel.self) private var model
    let planId: Int64
    @State private var viewing: Int?

    var body: some View {
        let plan = model.read { try Q.plan($0, planId) } ?? nil
        let trip = plan.flatMap { p in model.read { try Q.trip($0, p.tripId) } ?? nil }
        ScrollView {
            if let p = plan, let t = trip {
                content(p, t)
            }
        }
        .background(Palette.background)
        .navigationTitle("行程")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(get: { viewing.map(ViewerStart.init) }, set: { viewing = $0?.index })) { start in
            PhotoViewer(paths: (model.read { try Q.planPhotos($0, planId: planId) } ?? []).map { ($0.path, nil) }, start: start.index)
        }
    }

    private func content(_ p: PlanItem, _ t: Trip) -> some View {
        let categories = model.read { try Q.categories($0) } ?? []
        let category = categories.first { $0.id == p.categoryId }
        let style = IconStyle.category(name: category?.name, icon: category?.icon, color: category?.color)
        let expenses = (model.read { try Q.expenseRows($0, t.id ?? 0) } ?? []).filter { $0.planItemId == p.id }
        let pictures = model.read { try Q.planPhotos($0, planId: planId) } ?? []
        let spent = expenses.reduce(0) { $0 + $1.homeAmount }
        var lines: [(symbol: String, label: String, value: String)] = []
        let note = p.reservationNote.isBlank ? "" : "\n\(p.reservationNote)"
        if p.reservation == Reservation.needed { lines.append(("chair", "訂位", "需要訂位" + note)) }
        if p.reservation == Reservation.booked { lines.append(("chair", "訂位", "已訂好" + note)) }
        if !p.location.isBlank { lines.append(("mappin.and.ellipse", "地點", p.location)) }
        if spent > 0 { lines.append(("list.bullet.rectangle.portrait", "已花", fmtMoney(spent))) }
        let status = p.status == PlanStatus.done ? "已去" : p.status == PlanStatus.skipped ? "跳過" : "未去"
        let meta = [category?.name ?? "未分類", status, p.addedBy.map { "\($0) 補充" }, p.pending ? "我的補充" : nil].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 12) {
            Text(t.name).font(.system(size: 13)).foregroundStyle(Palette.onSurfaceVariant).padding(.leading, 4)
            HStack(spacing: 14) {
                IconTile(symbol: style.symbol, color: style.color, size: 48, corner: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.system(size: 21, weight: .bold))
                    Text((p.date.map { "Day \($0 - t.startDate + 1) · \(fmtShortDate($0))" } ?? "待排") + (p.minuteOfDay.map { " · \(fmtTime($0))" } ?? ""))
                        .font(.system(size: 15)).foregroundStyle(Palette.onSurfaceVariant)
                    Text(meta.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(Palette.onSurfaceVariant)
                }
            }
            .ledgerCard()

            if !lines.isEmpty { DetailCard(lines: lines) }

            if !p.note.isBlank {
                VStack(alignment: .leading, spacing: 6) {
                    Label("筆記", systemImage: "text.alignleft").font(.system(size: 16, weight: .semibold))
                    LinkText(text: p.note).font(.system(size: 16)).textSelection(.enabled)
                }
                .ledgerCard(padding: 14)
            }

            if !pictures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pictures.indices, id: \.self) { i in
                            Button { viewing = i } label: {
                                LocalImage(path: pictures[i].path, maxPixel: 300) { Palette.surfaceVariant }
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !expenses.isEmpty {
                SectionHeader("為這個行程記的帳")
                VStack(spacing: 0) {
                    ForEach(expenses) { e in
                        if e.id != expenses.first?.id { Divider().overlay(Palette.hairline).padding(.leading, 66) }
                        ExpenseRowItem(row: e)
                    }
                }
                .ledgerCard(padding: 0)
            }
        }
        .foregroundStyle(Palette.onBackground)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .readableWidth()
    }
}

/// An expense, to read (「支出明細」); editing comes with stage 4.
struct ExpenseDetailView: View {
    @Environment(AppModel.self) private var model
    let expenseId: Int64
    @State private var viewing: Int?

    var body: some View {
        let expense = model.read { try Q.expense($0, expenseId) } ?? nil
        let photos = model.read { try Q.photos($0, expenseId: expenseId) } ?? []
        ScrollView {
            if let e = expense { content(e, photos: photos) }
        }
        .background(Palette.background)
        .navigationTitle("支出明細")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(get: { viewing.map(ViewerStart.init) }, set: { viewing = $0?.index })) { start in
            PhotoViewer(paths: photos.map { ($0.path, $0.type) }, start: start.index)
        }
    }

    private func content(_ s: Expense, photos: [Photo]) -> some View {
        let category = (model.read { try Q.categories($0) } ?? []).first { $0.id == s.categoryId }
        let method = (model.read { try Q.paymentMethods($0) } ?? []).first { $0.id == s.paymentMethodId }
        let style = IconStyle.category(name: category?.name, icon: category?.icon, color: category?.color)
        var lines: [(symbol: String, label: String, value: String)] = [
            ("square.grid.2x2", "分類", category?.name ?? "未分類"),
            ("creditcard", "付款", method?.name ?? "未指定"),
        ]
        if !s.note.isBlank { lines.append(("text.alignleft", "備註", s.note)) }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    IconTile(symbol: style.symbol, color: style.color, size: 48, corner: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title.isBlank ? (category?.name ?? "支出") : s.title).font(.system(size: 21, weight: .bold))
                        Text(fmtShortDateTime(s.date, s.minuteOfDay)).font(.system(size: 15)).foregroundStyle(Palette.onSurfaceVariant)
                    }
                }
                Text(fmtAmount(s.amount, s.currency)).font(.system(size: 28, weight: .semibold)).tnum().padding(.top, 14)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if s.currency != homeCurrency {
                    Text("≈ \(fmtMoney(s.homeAmount)) · 匯率 \(fmtNumber(s.rate))").font(.system(size: 15)).foregroundStyle(Palette.onSurfaceVariant)
                }
            }
            .ledgerCard()

            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.indices, id: \.self) { i in
                            Button { viewing = i } label: {
                                LocalImage(path: photos[i].path, maxPixel: 240) { Palette.surfaceVariant }
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .bottomLeading) { PhotoTypeBadge(type: photos[i].type).padding(4) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            DetailCard(lines: lines)
        }
        .foregroundStyle(Palette.onBackground)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .readableWidth()
    }
}

struct PhotoTypeBadge: View {
    let type: String

    var body: some View {
        let receipt = type == PhotoType.receipt
        HStack(spacing: 3) {
            Image(systemName: receipt ? "doc.text" : "photo").font(.system(size: 10))
            Text(receipt ? "收據" : "回憶").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .dynamicTypeSize(.large)
    }
}

struct ViewerStart: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Full-screen photos: swipe between them, pinch to zoom.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let paths: [(String, String?)]
    @State private var page: Int

    init(paths: [(String, String?)], start: Int) {
        self.paths = paths
        _page = State(initialValue: min(max(start, 0), max(paths.count - 1, 0)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("關閉")
                Text("\(page + 1) / \(paths.count)").font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            TabView(selection: $page) {
                ForEach(paths.indices, id: \.self) { i in
                    ZoomableImage(path: paths[i].0).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color(hex: 0x0B0B0E).ignoresSafeArea())
    }
}

private struct ZoomableImage: View {
    let path: String
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        LocalImage(path: path, maxPixel: 2000, contentMode: .fit) { ProgressView().tint(.white) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale * pinch)
            .gesture(
                MagnificationGesture()
                    .updating($pinch) { v, s, _ in s = v }
                    .onEnded { v in scale = min(max(scale * v, 1), 4) }
            )
            .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
    }
}
