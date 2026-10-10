import LedgerCore
import PhotosUI
import SwiftUI
import UIKit

/// New / edit trip (ui/TripEditScreen.kt). Opened as a sheet; a new trip opens right after saving.
struct TripEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tripId: Int64?

    @State private var loaded = false
    @State private var initial: Trip?
    @State private var name = ""
    @State private var budget = ""
    @State private var split = false
    @State private var navApp: String?
    @State private var theme: String?
    @State private var cover: String?
    @State private var members: [String] = []
    @State private var rates: [RateDraft] = []
    @State private var start = todayEpochDay()
    @State private var end = todayEpochDay() + 4
    @State private var picking: DayField?
    @State private var addingMember = false
    @State private var newMember = ""
    @State private var addingCurrency = false
    @State private var photoItem: PhotosPickerItem?
    @State private var coverBusy = false

    struct RateDraft: Identifiable, Equatable {
        let currency: String
        var value: String
        var id: String { currency }
    }

    enum DayField: String, Identifiable { case start, end; var id: String { rawValue } }

    /// The first-run tutorial for a new trip.
    static let tourSteps = [
        CoachStep(target: .editCover, title: "封面", text: "每趟旅程有一張封面。可以用下面的插畫,或按「從相簿選封面」換成自己的照片。"),
        CoachStep(target: .editName, title: "旅程名稱", text: "幫這趟旅行取個名字,例如「首爾賞楓」。這一欄一定要填。"),
        CoachStep(target: .editDates, title: "出發與回程", text: "點日期選出發日和回程日。改出發日時,天數會保持不變。"),
        CoachStep(target: .editMembers, title: "同行成員", text: "把一起旅行的人加進來,帳本會算每個人平均花多少。"),
        CoachStep(title: "匯率、預算與儲存", text: "往下滑還有導航軟體、外幣匯率(1 外幣等於多少新台幣)和預算。填好後按右上角的 ✓ 儲存,旅程就建立了。"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    coverBox.coachTarget(.editCover)
                    if cover == nil {
                        CoverThemePicker(name: name, start: start, selected: theme) { theme = $0 }
                    } else {
                        Button { removeCover() } label: {
                            Label("不用照片,改用插畫", systemImage: "paintbrush.pointed").appFont(size: 15, weight: .semibold)
                        }
                        .padding(.vertical, 4)
                    }

                    FieldBox("旅程名稱") {
                        TextField("", text: $name, prompt: Text("例如:東京美食之旅").foregroundStyle(Palette.textMuted), axis: .vertical)
                            .lineLimit(1 ... 2)
                            .appFont(size: 16)
                    }
                    .coachTarget(.editName)

                    HStack(spacing: 10) {
                        dateBox("出發", start) { picking = .start }
                        dateBox("回程", end) { picking = .end }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .coachTarget(.editDates)
                    Text(verbatim: "\(start.civil.year) 年 · 共 \(end - start + 1) 天")
                        .appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant).padding(.leading, 4)

                    SectionHeader("旅行成員 · \(members.count) 人")
                    membersGrid.coachTarget(.editMembers)

                    SectionHeader("導航軟體")
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        SelectPill("每次詢問", selected: navApp == nil) { navApp = nil }
                        ForEach(NavApp.allCases, id: \.self) { app in
                            SelectPill(app.label, selected: navApp == app.rawValue) { navApp = app.rawValue }
                        }
                    }
                    Text("行程的「導航」會用這個 App。韓國建議 Naver Map 或 KakaoMap,大眾運輸和步行路線比較準。")
                        .appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)

                    SectionHeader("預設匯率") {
                        Text("1 外幣 = ? 新台幣").appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                    }
                    if !rates.isEmpty { ratesCard }
                    AddChip("新增幣別") { addingCurrency = true }
                    Text("所有總計以新台幣計算;記帳時每筆的匯率仍可個別修改。")
                        .appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)

                    FieldBox("預算(選填)") {
                        TextField("", text: $budget, prompt: Text("不設定").foregroundStyle(Palette.textMuted))
                            .keyboardType(.decimalPad)
                            .appFont(size: 16)
                            .onChange(of: budget) { _, v in
                                let f = v.filter { $0.isNumber || $0 == "." }
                                if f != v { budget = f }
                            }
                    } trailing: {
                        Text("NT$").appFont(size: 15, weight: .semibold).foregroundStyle(Palette.onSurfaceVariant)
                    }

                    HStack(spacing: 12) {
                        IconTile(symbol: "person.2.fill", color: Palette.category(4))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("分帳功能").appFont(size: 16, weight: .semibold)
                            Text("與朋友旅遊時開啟").appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                        }
                        Spacer(minLength: 8)
                        Toggle("分帳功能", isOn: $split).labelsHidden()
                    }
                    .ledgerCard(padding: 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background)
            .coachTour(.edit, steps: Self.tourSteps, active: tripId == nil, advanceOn: 0)
            .navigationTitle(tripId == nil ? "新增旅程" : "編輯旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close() } label: { Image(systemName: "xmark") }.accessibilityLabel("關閉")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark").fontWeight(.bold) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("儲存")
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: load)
        .sheet(item: $picking) { field in
            if field == .start {
                DayPickerSheet(title: "出發日期", initial: start) { d in
                    // Keep the trip length when the departure moves.
                    end = d + max(end - start, 0)
                    start = d
                }
            } else {
                DayPickerSheet(title: "回程日期", initial: end, minDay: start) { end = $0 }
            }
        }
        .sheet(isPresented: $addingCurrency) {
            CurrencyPickerSheet(current: "") { c in
                if c != homeCurrency, !rates.contains(where: { $0.currency == c }) { rates.append(RateDraft(currency: c, value: "")) }
            }
        }
        .alert("新增成員", isPresented: $addingMember) {
            TextField("名字", text: $newMember)
            Button("取消", role: .cancel) { newMember = "" }
            Button("確定") {
                let n = newMember.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty, !members.contains(n) { members.append(n) }
                newMember = ""
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importCover(item) }
        }
    }

    // MARK: Pieces

    private var coverBox: some View {
        TripCover(path: cover, name: name, startDate: start, theme: theme)
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay {
                if coverBusy {
                    ZStack { Color.black.opacity(0.35); ProgressView().tint(.white) }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 14))
                        Text(cover == nil ? "從相簿選封面" : "更換封面").appFont(size: 15, weight: .semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                }
                .padding(10)
            }
    }

    private func dateBox(_ label: String, _ day: Int64, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FieldBox(label) {
                Text(fmtShortDate(day)).appFont(size: 17, weight: .semibold).tnum().lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(Palette.onBackground)
            } trailing: {
                Image(systemName: "calendar").foregroundStyle(Palette.onSurfaceVariant)
            }
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var membersGrid: some View {
        let cells = members + ["+"]
        return VStack(spacing: 10) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { i in
                HStack(spacing: 10) {
                    ForEach(cells[i ..< min(i + 2, cells.count)], id: \.self) { m in
                        if m == "+" {
                            Button { addingMember = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.badge.plus")
                                    Text("新增成員").appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
                                }
                                .foregroundStyle(Palette.primary)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Palette.primaryContainer, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack(spacing: 10) {
                                Avatar(name: m, size: 32)
                                Text(m).appFont(size: 16).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Button { members.removeAll { $0 == m } } label: {
                                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMuted)
                                        .frame(width: 36, height: 40)
                                }
                                .accessibilityLabel("移除")
                            }
                            .padding(.leading, 10)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline))
                        }
                    }
                    if i + 1 >= cells.count { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }
    }

    private var ratesCard: some View {
        VStack(spacing: 0) {
            ForEach($rates) { $r in
                if r.currency != rates.first?.currency { Divider().overlay(Palette.hairline).padding(.leading, 64) }
                HStack(spacing: 12) {
                    CurrencyBadge(code: r.currency, size: 40)
                    Text(currencyNames[r.currency] ?? r.currency).appFont(size: 16).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("", text: $r.value, prompt: Text("匯率").foregroundStyle(Palette.textMuted))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .appFont(size: 16).tnum()
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(width: 110)
                        .background(Palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onChange(of: r.value) { _, v in
                            let f = v.filter { $0.isNumber || $0 == "." }
                            if f != v { r.value = f }
                        }
                    Button { rates.removeAll { $0.currency == r.currency } } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMuted)
                            .frame(width: 32, height: 40)
                    }
                    .accessibilityLabel("移除")
                }
                .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 8)
            }
        }
        .ledgerCard(padding: 0)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let tripId, let trip = model.read({ try Q.trip($0, tripId) }) ?? nil else { return }
        initial = trip
        name = trip.name
        budget = trip.budget.map(fmtNumber) ?? ""
        split = trip.splitEnabled
        navApp = trip.navApp
        theme = trip.coverTheme
        cover = trip.coverPath
        start = trip.startDate
        end = trip.endDate
        members = (model.read { try Q.members($0, tripId) } ?? []).map(\.name)
        rates = (model.read { try Q.rates($0, tripId) } ?? []).map { RateDraft(currency: $0.currency, value: fmtNumber($0.rate)) }
    }

    /// A picked photo, downscaled to 1600 px and kept as covers/….jpg.
    private func importCover(_ item: PhotosPickerItem) async {
        coverBusy = true
        defer { coverBusy = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = await Task.detached(operation: { downscaledJPEG(data, maxEdge: 1600, quality: 0.85) }).value,
              let path = try? model.files.write(jpeg, folder: "covers")
        else {
            model.show("無法讀取這張照片")
            return
        }
        if cover != initial?.coverPath { model.files.delete(cover) }
        cover = path
    }

    private func removeCover() {
        if cover != initial?.coverPath { model.files.delete(cover) } // an unsaved pick; a saved one goes on save
        cover = nil
    }

    private func close() {
        if cover != initial?.coverPath { model.files.delete(cover) }
        dismiss()
    }

    private func save() {
        var trip = initial ?? Trip(name: "", startDate: 0, endDate: 0)
        trip.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.startDate = start
        trip.endDate = end
        trip.budget = Double(budget).flatMap { $0 > 0 ? $0 : nil }
        trip.splitEnabled = split
        trip.coverPath = cover
        trip.coverTheme = theme
        trip.navApp = navApp
        let id = trip.id ?? 0
        let rateRows = rates.compactMap { r in Double(r.value).flatMap { $0 > 0 ? TripCurrencyRate(tripId: id, currency: r.currency, rate: $0) : nil } }
        if let old = initial?.coverPath, old != cover { model.files.delete(old) }
        if initial == nil {
            var newId: Int64?
            if model.write({ newId = try Q.createTrip($0, trip, members: members, rates: rateRows) }), let newId {
                dismiss()
                model.openTrip(newId)
            }
        } else {
            if model.write({ try Q.updateTrip($0, trip, members: members, rates: rateRows) }) { dismiss() }
        }
    }
}

/// Re-encodes a picture as JPEG with its long edge at most [maxEdge] pixels.
func downscaledJPEG(_ data: Data, maxEdge: CGFloat, quality: CGFloat) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxEdge,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
}

/// "自動" plus one small preview per scene; tapping one fixes the illustration for this trip.
private struct CoverThemePicker: View {
    let name: String
    let start: Int64
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("封面插畫").appFont(size: 16, weight: .semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach([CoverTheme?.none] + CoverTheme.allCases.map(Optional.some), id: \.self) { t in
                        let on = t?.rawValue == selected
                        Button { onSelect(t?.rawValue) } label: {
                            VStack(spacing: 3) {
                                CoverArtwork(spec: CoverArt.pick(name: name, start: start.civil, chosen: t))
                                    .frame(width: 76, height: 48)
                                    .overlay {
                                        if t == nil {
                                            ZStack {
                                                Color.black.opacity(0.25)
                                                Image(systemName: "sparkles").foregroundStyle(.white)
                                            }
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(on ? Palette.primary : Palette.hairline, lineWidth: on ? 2.5 : 1))
                                Text(t?.label ?? "自動").appFont(size: 13, weight: .medium)
                                    .foregroundStyle(on ? Palette.primary : Palette.onSurfaceVariant)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Shared pickers

/// A three-letter currency code in a tinted square.
struct CurrencyBadge: View {
    let code: String
    var size: CGFloat = 42

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Palette.primaryContainer)
            .frame(width: size, height: size)
            .overlay(
                // Sized from the badge, not the text setting, so a three-letter code always fits on one line.
                Text(code).font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(Palette.onPrimaryContainer)
                    .lineLimit(1).fixedSize()
            )
            .dynamicTypeSize(.large)
    }
}

/// "+ 新增…" pill.
struct AddChip: View {
    let text: String
    let action: () -> Void

    init(_ text: String, action: @escaping () -> Void) { self.text = text; self.action = action }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                Text(text).appFont(size: 15, weight: .semibold)
            }
            .foregroundStyle(Palette.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Palette.primaryContainer, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Single-day picker with a short header; [minDay] disables earlier days (e.g. return before departure).
struct DayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initial: Int64
    var minDay: Int64?
    let onPick: (Int64) -> Void
    @State private var date = Date()

    init(title: String, initial: Int64, minDay: Int64? = nil, onPick: @escaping (Int64) -> Void) {
        self.title = title; self.initial = initial; self.minDay = minDay; self.onPick = onPick
        _date = State(initialValue: initial.civil.date())
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(fmtShortDate(CivilDate.today(date).epochDay)).appFont(size: 28, weight: .bold).tnum()
                    .padding(.horizontal, 20)
                Group {
                    if let minDay {
                        DatePicker(title, selection: $date, in: minDay.civil.date()..., displayedComponents: .date)
                    } else {
                        DatePicker(title, selection: $date, displayedComponents: .date)
                    }
                }
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確定") { onPick(CivilDate.today(date).epochDay); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Common currencies, or any three-letter code.
struct CurrencyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: String
    let onPick: (String) -> Void
    @State private var custom = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(commonCurrencies, id: \.self) { c in
                            SelectPill(c, selected: c == current) { onPick(c); dismiss() }
                        }
                    }
                    FieldBox("其他幣別代碼(3 碼)") {
                        TextField("", text: $custom)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .appFont(size: 16)
                            .onChange(of: custom) { _, v in
                                let f = String(v.uppercased().filter { $0.isLetter }.prefix(3))
                                if f != v { custom = f }
                            }
                    } trailing: {
                        Button("使用") { onPick(custom); dismiss() }.disabled(custom.count != 3)
                    }
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle("選擇幣別")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
