import LedgerCore
import SwiftUI
import UIKit

/// The journal of a trip: one page per day.
struct JournalTarget: Identifiable, Hashable {
    let tripId: Int64
    var id: Int64 { tripId }
}

/// What one day's page shows, loaded up front so the page can be drawn into an image.
private struct JournalDay {
    let tripName: String
    let dayNumber: Int
    let date: Int64
    let note: String?
    let plans: [PlanRow]
    let expenses: [ExpenseRow]
    let total: Double
    let photos: [UIImage]
}

/// 旅行手帳: a day of the trip laid out as a page — where we went, what we spent, the photos — that can be drawn
/// on with Apple Pencil and shared as a long picture or a PDF. Nothing here is stored in the trip's data.
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: JournalTarget
    @State private var day: Int64?
    /// The page with drawings on it, once the user has drawn.
    @State private var decorated: UIImage?
    @State private var drawingOn: UIImage?
    @State private var sharing: [Any]?

    var body: some View {
        let trip = model.read { try Q.trip($0, target.tripId) } ?? nil
        let days = trip.map { Array($0.startDate ... max($0.startDate, $0.endDate)) } ?? []
        let current = day ?? days.first ?? 0
        let data = trip.map { load($0, current) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days, id: \.self) { d in
                                SelectPill("Day \(d - (trip?.startDate ?? d) + 1)", selected: d == current) {
                                    day = d
                                    decorated = nil
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 1)
                    }
                    if let decorated {
                        Image(uiImage: decorated).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                    } else if let data {
                        JournalPage(day: data)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                    }
                    if let data {
                        VStack(spacing: 10) {
                            PillButton(decorated == nil ? "用筆畫上去" : "繼續畫", symbol: "pencil.and.scribble", height: 48) { drawingOn = decorated ?? render(data) }
                            HStack(spacing: 10) {
                                PillButton("分享圖片", symbol: "photo", height: 48) { share(data, pdf: false) }
                                PillButton("分享 PDF", symbol: "doc.richtext", height: 48) { share(data, pdf: true) }
                            }
                            if decorated != nil {
                                Button("清掉畫的,回到原本的頁面") { decorated = nil }.appFont(size: 15).frame(minHeight: 44)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
                .readableWidth()
            }
            .background(Palette.background)
            .navigationTitle("旅行手帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } } }
        }
        .tint(Palette.primary)
        .fullScreenCover(item: Binding(get: { drawingOn.map(PageToDraw.init) }, set: { drawingOn = $0?.image })) { page in
            DrawingSheet(title: "在手帳上畫", background: page.image, saveText: "完成") { data in decorated = UIImage(data: data) }
        }
        .sheet(item: Binding(get: { sharing.map(ShareItems.init) }, set: { sharing = $0?.items })) { s in
            ActivityView(items: s.items, subject: "旅行手帳") { _ in }.ignoresSafeArea()
        }
    }

    private struct PageToDraw: Identifiable {
        let image: UIImage
        var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    private struct ShareItems: Identifiable {
        let items: [Any]
        let id = UUID()
    }

    private func load(_ trip: Trip, _ day: Int64) -> JournalDay {
        let id = trip.id ?? 0
        let plans = (model.read { try Q.planRows($0, id) } ?? []).filter { $0.date == day }
        let expenses = (model.read { try Q.expenseRows($0, id) } ?? []).filter { $0.date == day }.reversed()
        // Memories of the day first, then the day's plan pictures; six at most.
        var paths: [String] = []
        for e in expenses {
            paths += (model.read { try Q.photos($0, expenseId: e.id) } ?? []).filter { $0.type == PhotoType.memory }.map(\.path)
        }
        for p in plans { paths += (model.read { try Q.planPhotos($0, planId: p.id) } ?? []).map(\.path) }
        let photos = paths.prefix(6).compactMap { path -> UIImage? in
            guard let data = try? Data(contentsOf: model.files.url(path)), let small = downscaledJPEG(data, maxEdge: 700, quality: 0.85) else { return nil }
            return UIImage(data: small)
        }
        return JournalDay(tripName: trip.name, dayNumber: Int(day - trip.startDate) + 1, date: day,
                          note: (model.read { try Q.dayNote($0, tripId: id, day: day) } ?? nil)?.text,
                          plans: plans, expenses: Array(expenses), total: expenses.reduce(0) { $0 + $1.homeAmount }, photos: photos)
    }

    /// The page as a picture, 1080 px wide.
    @MainActor private func render(_ data: JournalDay) -> UIImage? {
        let renderer = ImageRenderer(content: JournalPage(day: data).frame(width: 540).environment(\.colorScheme, .light))
        renderer.scale = 2
        return renderer.uiImage
    }

    @MainActor private func share(_ data: JournalDay, pdf: Bool) {
        guard let image = decorated ?? render(data) else {
            model.show("產生檔案失敗")
            return
        }
        let name = "卡溜趴手帳-\(safeFileName(data.tripName))-Day\(data.dayNumber)"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("outgoing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if pdf {
            let bounds = CGRect(origin: .zero, size: image.size)
            let url = dir.appendingPathComponent(name + ".pdf")
            let bytes = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
                context.beginPage()
                image.draw(in: bounds)
            }
            guard (try? bytes.write(to: url)) != nil else { return }
            sharing = [url]
        } else {
            let url = dir.appendingPathComponent(name + ".jpg")
            guard let bytes = image.jpegData(compressionQuality: 0.9), (try? bytes.write(to: url)) != nil else { return }
            sharing = [url]
        }
    }
}

/// One day as a page. Always on light paper, with fixed type sizes: it is a picture to share, not a screen to read.
private struct JournalPage: View {
    let day: JournalDay
    private let ink = Color(red: 0.13, green: 0.13, blue: 0.16)
    private let soft = Color(red: 0.42, green: 0.43, blue: 0.5)
    private let paper = Color(red: 0.99, green: 0.98, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.tripName).font(.system(size: 15, weight: .semibold)).foregroundStyle(soft)
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "Day \(day.dayNumber)").font(.system(size: 34, weight: .heavy, design: .serif))
                    Text(fmtDayHeader(day.date)).font(.system(size: 17, weight: .medium)).foregroundStyle(soft)
                    Spacer(minLength: 0)
                }
            }
            if day.total > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("今天花了").font(.system(size: 15)).foregroundStyle(soft)
                    Text(fmtMoney(day.total)).font(.system(size: 24, weight: .bold)).monospacedDigit()
                }
            }
            if let note = day.note, !note.isBlank {
                Text(note).font(.system(size: 15)).italic()
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1, green: 0.95, blue: 0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if !day.plans.isEmpty {
                section("去了哪裡")
                ForEach(day.plans) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(p.status == PlanStatus.done ? "✓" : p.status == PlanStatus.skipped ? "–" : "○").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(p.status == PlanStatus.done ? Color(red: 0.11, green: 0.7, blue: 0.48) : soft).frame(width: 18)
                        if let m = p.minuteOfDay { Text(fmtTime(m)).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(soft) }
                        Text(p.title).font(.system(size: 16, weight: .medium))
                        Spacer(minLength: 0)
                    }
                }
            }
            if !day.expenses.isEmpty {
                section("花了什麼")
                ForEach(day.expenses) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(e.title.isBlank ? (e.categoryName ?? "支出") : e.title).font(.system(size: 16))
                        Spacer(minLength: 8)
                        if e.currency != homeCurrency { Text(fmtAmount(e.amount, e.currency)).font(.system(size: 13)).foregroundStyle(soft).monospacedDigit() }
                        Text(fmtMoney(e.homeAmount)).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                    }
                }
            }
            if !day.photos.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(day.photos.indices, id: \.self) { i in
                        Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                            .overlay(Image(uiImage: day.photos[i]).resizable().scaledToFill())
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            if day.plans.isEmpty, day.expenses.isEmpty, day.photos.isEmpty, (day.note ?? "").isBlank {
                Text("這一天還沒有紀錄,可以直接在這一頁畫畫、寫字。").font(.system(size: 15)).foregroundStyle(soft)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            HStack {
                Spacer(minLength: 0)
                Text("卡溜趴").font(.system(size: 12, weight: .semibold)).foregroundStyle(soft)
            }
            .padding(.top, 6)
        }
        .foregroundStyle(ink)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(soft).padding(.top, 4)
    }
}
