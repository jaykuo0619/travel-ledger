import LedgerCore
import PhotosUI
import SwiftUI
import UIKit

/// Which plan item the editor sheet is open for (nil planId = a new one, on [date] or 待排).
struct PlanEditTarget: Identifiable, Hashable {
    let tripId: Int64
    var planId: Int64?
    var date: Int64?
    var id: String { planId.map { "p\($0)" } ?? "new-\(tripId)-\(date.map(String.init) ?? "x")" }
}

let maxPlanPictures = 9

/// New / edit plan item (ui/PlanScreens.kt PlanEditScreen).
struct PlanEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: PlanEditTarget

    @State private var loaded = false
    @State private var trip: Trip?
    @State private var plan = PlanItem(tripId: 0, title: "")
    @State private var pictures: [PlanPhoto] = []
    @State private var pickingTime = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var addingPictures = false
    @State private var mapTarget: MapTarget?

    private var isNew: Bool { target.planId == nil }

    var body: some View {
        let categories = model.read { try Q.categories($0) } ?? []
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FieldBox("名稱") {
                        TextField("", text: $plan.title, prompt: Text("景點、餐廳或活動名稱").foregroundStyle(Palette.textMuted), axis: .vertical)
                            .lineLimit(1 ... 2)
                            .appFont(size: 17, weight: .semibold)
                            .onChange(of: plan.title) { _, v in
                                if v.contains(where: \.isNewline) { plan.title = v.filter { !$0.isNewline } }
                            }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories) { c in
                                let style = IconStyle.category(name: c.name, icon: c.icon, color: c.color)
                                SelectPill(c.name, selected: plan.categoryId == c.id) {
                                    plan.categoryId = plan.categoryId == c.id ? nil : c.id
                                } leading: {
                                    Image(systemName: style.symbol).font(.system(size: 14)).foregroundStyle(style.color)
                                }
                            }
                        }
                        .padding(.vertical, 1)
                    }

                    SectionHeader("哪一天") {
                        Button { pickingTime = true } label: {
                            Label(plan.minuteOfDay.map { "時間 \(fmtTime($0))" } ?? "加時間", systemImage: "clock")
                                .appFont(size: 15, weight: .semibold)
                                .frame(minHeight: 36)
                        }
                    }
                    if let trip { DayGrid(trip: trip, selected: $plan.date) }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { choices }
                        VStack(spacing: 10) { choices }
                    }

                    if plan.reservation != Reservation.none {
                        FieldBox("訂位資訊") {
                            TextField("", text: $plan.reservationNote, prompt: Text("例如:19:00 · 4 位 · 確認碼 AB123").foregroundStyle(Palette.textMuted), axis: .vertical)
                                .appFont(size: 16)
                        }
                        LinkButtons(text: plan.reservationNote)
                    }

                    FieldBox("地點") {
                        TextField("", text: $plan.location, prompt: Text("地址或 Google 地圖連結").foregroundStyle(Palette.textMuted), axis: .vertical)
                            .appFont(size: 16)
                            .autocorrectionDisabled()
                    } trailing: {
                        Button { mapTarget = MapTarget(title: plan.title, location: plan.location, app: trip?.navApp) } label: {
                            Image(systemName: "map").font(.system(size: 20)).frame(width: 44, height: 44)
                        }
                        .disabled(plan.title.isBlank && plan.location.isBlank)
                        .accessibilityLabel("在地圖開啟")
                    }
                    LinkButtons(text: plan.location)

                    FieldBox("筆記") {
                        TextField("", text: $plan.note, prompt: Text("必點菜色、營業時間、注意事項…").foregroundStyle(Palette.textMuted), axis: .vertical)
                            .lineLimit(2...)
                            .appFont(size: 16)
                    }
                    LinkButtons(text: plan.note)

                    pictureStrip
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background)
            .navigationTitle(isNew ? "新增行程" : "編輯行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close() } label: { Image(systemName: "xmark") }.accessibilityLabel("關閉").disabled(addingPictures)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark").fontWeight(.bold) }
                        .disabled(plan.title.isBlank || addingPictures)
                        .accessibilityLabel("儲存")
                }
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .interactiveDismissDisabled()
        .onAppear(perform: load)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPictures(items) }
        }
        .sheet(isPresented: $pickingTime) {
            TimePickerSheet(minute: plan.minuteOfDay) { plan.minuteOfDay = $0 }
        }
        .mapLauncher($mapTarget)
        .tint(Palette.primary)
    }

    // MARK: Pieces

    /// Status (existing items only) and reservation, each a compact menu showing the current choice.
    @ViewBuilder private var choices: some View {
        if !isNew {
            ChoiceMenu(options: [(PlanStatus.todo, "未去", "circle"), (PlanStatus.done, "已去", "checkmark.circle.fill"), (PlanStatus.skipped, "跳過", "minus.circle")],
                       selected: $plan.status)
        }
        ChoiceMenu(options: [(Reservation.none, "不用訂位", "calendar.badge.minus"), (Reservation.needed, "需要訂位", "bell.badge"), (Reservation.booked, "已訂好", "calendar.badge.checkmark")],
                   selected: $plan.reservation)
    }

    private var pictureStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pictures.indices, id: \.self) { i in
                    LocalImage(path: pictures[i].path, maxPixel: 300) { Palette.surfaceVariant }
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { removePicture(i) } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.black.opacity(0.55), in: Circle())
                                    .frame(width: 40, height: 40, alignment: .topTrailing)
                                    .padding(4)
                            }
                            .accessibilityLabel("移除圖片")
                        }
                }
                if pictures.count < maxPlanPictures {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: maxPlanPictures - pictures.count, matching: .images) {
                        VStack(spacing: 4) {
                            if addingPictures { ProgressView() } else { Image(systemName: "photo.badge.plus").font(.system(size: 22)) }
                            Text("截圖/圖片").appFont(size: 13, weight: .medium).lineLimit(1).fixedSize()
                        }
                        .foregroundStyle(Palette.primary)
                        .frame(minWidth: 88, minHeight: 88)
                        .padding(.horizontal, 6)
                        .background(Palette.primaryContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(addingPictures)
                }
            }
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        trip = model.read { try Q.trip($0, target.tripId) } ?? nil
        if let id = target.planId, let p = model.read({ try Q.plan($0, id) }) ?? nil {
            plan = p
            pictures = model.read { try Q.planPhotos($0, planId: id) } ?? []
        } else {
            plan = PlanItem(tripId: target.tripId, title: "", date: target.date)
        }
    }

    /// Picked pictures, downscaled to 1600 px and kept under photos/plans.
    private func importPictures(_ items: [PhotosPickerItem]) async {
        addingPictures = true
        defer { addingPictures = false; photoItems = [] }
        for item in items.prefix(maxPlanPictures - pictures.count) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = await Task.detached(operation: { downscaledJPEG(data, maxEdge: 1600, quality: 0.82) }).value,
                  let path = try? model.files.write(jpeg, folder: "photos/plans")
            else {
                model.show("無法讀取這張照片")
                continue
            }
            let size = UIImage(data: jpeg)?.size ?? .zero
            pictures.append(PlanPhoto(planItemId: plan.id ?? 0, path: path, width: Int(size.width), height: Int(size.height)))
        }
    }

    private func removePicture(_ index: Int) {
        guard pictures.indices.contains(index) else { return }
        let p = pictures.remove(at: index)
        if p.id == nil { model.files.delete(p.path) } // saved ones go on save
    }

    /// Leaving without saving: pictures added this time are thrown away.
    private func close() {
        pictures.filter { $0.id == nil }.forEach { model.files.delete($0.path) }
        dismiss()
    }

    private func save() {
        var p = plan
        p.title = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
        p.location = p.location.trimmingCharacters(in: .whitespacesAndNewlines)
        p.note = p.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.title.isEmpty else { return }
        // On someone else's trip a new item is my own addition until the owner takes it.
        if isNew { p.pending = trip?.readOnly == true }
        var removed: [String] = []
        if model.write({ removed = try Q.savePlan($0, p, pictures: pictures).removed }) {
            model.files.delete(removed)
            dismiss()
        } else {
            model.show("儲存失敗")
        }
    }
}

/// Which day: one row of square tiles (date, weekday underneath) that scrolls sideways; the first is 待排.
private struct DayGrid: View {
    @Environment(\.textScale) private var textScale
    let trip: Trip
    @Binding var selected: Int64?

    var body: some View {
        let days: [Int64?] = [nil] + Array(trip.startDate ... max(trip.startDate, trip.endDate)).map(Optional.some)
        let size = (72 * textScale).rounded()
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { d in
                        let on = selected == d
                        Button { selected = d } label: {
                            VStack(spacing: 0) {
                                Text(d.map(fmtMonthDay) ?? "待排").appFont(size: 17, weight: .semibold).lineLimit(1).fixedSize()
                                    .foregroundStyle(on ? Palette.onPrimary : Palette.onBackground)
                                Text(d.map(weekdayText) ?? "未定").appFont(size: 13, weight: .medium).lineLimit(1).fixedSize()
                                    .foregroundStyle(on ? Palette.onPrimary.opacity(0.85) : Palette.onSurfaceVariant)
                            }
                            .frame(minWidth: size, minHeight: size)
                            .background(on ? Palette.primary : Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Palette.primary : Palette.hairline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(d)
                    }
                }
                .padding(.vertical, 1)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
    }

    /// "週四" for the tile's second line.
    private func weekdayText(_ day: Int64) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return "週" + names[Int(((day % 7) + 11) % 7)] // 1970-01-01 was a Thursday
    }
}

/// One compact choice: shows the current option, tap for a menu of all of them.
private struct ChoiceMenu: View {
    let options: [(value: String, label: String, symbol: String)]
    @Binding var selected: String

    var body: some View {
        let current = options.first { $0.value == selected } ?? options[0]
        Menu {
            ForEach(options, id: \.value) { o in
                Button { selected = o.value } label: { Label(o.label, systemImage: o.symbol) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: current.symbol).font(.system(size: 18)).foregroundStyle(Palette.primary)
                Text(current.label).appFont(size: 16).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.onSurfaceVariant)
            }
            .foregroundStyle(Palette.onBackground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline))
        }
    }
}

/// 24-hour time, 12:00 until one is chosen; 「不指定時間」 clears it.
struct TimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let minute: Int?
    var clearText = "不指定時間"
    let onPick: (Int?) -> Void
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DatePicker("時間", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB")) // 24-hour wheel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("時間")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(clearText) { onPick(nil); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("確定") {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                            onPick((c.hour ?? 0) * 60 + (c.minute ?? 0))
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.height(320)])
        .onAppear {
            let m = minute ?? 12 * 60
            date = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }
    }
}

/// Buttons under an editable field for each link in it (in an editor a tap on the text moves the cursor).
struct LinkButtons: View {
    @Environment(AppModel.self) private var model
    let text: String

    var body: some View {
        let links = unique(Links.find(text))
        if !links.isEmpty {
            FlowLayout(spacing: 8, lineSpacing: 6) {
                ForEach(links, id: \.uri) { l in
                    Button { openLink(l.uri, model: model) } label: {
                        Label(Links.label(l), systemImage: l.isPhone ? "phone" : "arrow.up.right.square")
                            .appFont(size: 15, weight: .medium).lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .overlay(Capsule().strokeBorder(Palette.primary.opacity(0.5)))
                    }
                }
            }
        }
    }

    /// At most three different links.
    private func unique(_ links: [FoundLink]) -> [FoundLink] {
        var seen = Set<String>()
        return Array(links.filter { seen.insert($0.uri).inserted }.prefix(3))
    }
}

@MainActor
func openLink(_ uri: String, model: AppModel) {
    guard let url = URL(string: uri) else {
        model.show("找不到可以開啟的 App")
        return
    }
    UIApplication.shared.open(url) { ok in
        if !ok { Task { @MainActor in model.show("找不到可以開啟的 App") } }
    }
}

// MARK: - 導航

/// A place to open in a map app; [app] is the trip's choice (nil: ask each time).
struct MapTarget: Identifiable {
    let title: String
    let location: String
    let app: String?
    var id: String { title + "\n" + location }
}

extension View {
    /// Opens [target] in the trip's map app, or asks which map to use when the trip has none set.
    func mapLauncher(_ target: Binding<MapTarget?>) -> some View { modifier(MapLauncher(target: target)) }
}

private struct MapLauncher: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var target: MapTarget?
    @State private var asking: MapTarget?

    func body(content: Content) -> some View {
        content
            .onChange(of: target?.id) { _, _ in
                guard let t = target else { return }
                target = nil
                if let app = NavApp(rawValue: t.app ?? "") { open(app, t) } else { asking = t }
            }
            // iOS has no system chooser for maps: list Apple Maps and the map apps that are installed.
            .confirmationDialog("用哪個地圖開啟?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), presenting: asking) { t in
                Button("Apple 地圖") { openURL(MapLinks.url(nil, title: t.title, location: t.location, bundleId: bundleId)) }
                ForEach(NavApp.allCases.filter(installed), id: \.self) { app in
                    Button(app.label) { open(app, t) }
                }
                if !installed(.google) {
                    Button("Google 地圖(網頁)") { openURL(MapLinks.googleWeb(title: t.title, location: t.location)) }
                }
                Button("取消", role: .cancel) {}
            }
    }

    private var bundleId: String { Bundle.main.bundleIdentifier ?? "" }

    private func scheme(_ app: NavApp) -> String {
        switch app {
        case .google: return "comgooglemaps://"
        case .naver: return "nmap://"
        case .kakao: return "kakaomap://"
        }
    }

    private func installed(_ app: NavApp) -> Bool {
        URL(string: scheme(app)).map(UIApplication.shared.canOpenURL) ?? false
    }

    private func open(_ app: NavApp, _ t: MapTarget) {
        if installed(app) {
            openURL(MapLinks.url(app, title: t.title, location: t.location, bundleId: bundleId))
        } else if app == .google {
            openURL(MapLinks.googleWeb(title: t.title, location: t.location))
        } else {
            model.show("沒有安裝 \(app.label),改用其他地圖")
            openURL(MapLinks.url(nil, title: t.title, location: t.location, bundleId: bundleId))
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else {
            model.show("找不到地圖 App")
            return
        }
        UIApplication.shared.open(url) { ok in
            if !ok { Task { @MainActor in model.show("找不到地圖 App") } }
        }
    }
}

// MARK: - Day notes

/// Which day's note is being edited ([unscheduledDay] for 待排).
struct DayNoteTarget: Identifiable, Hashable {
    let tripId: Int64
    let day: Int64
    var id: String { "\(tripId)-\(day)" }
}

/// Edit one day's note; saving blank text removes it.
struct DayNoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: DayNoteTarget
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextField("", text: $text, prompt: Text("例如:今天早點出門、記得帶護照…").foregroundStyle(Palette.textMuted), axis: .vertical)
                .lineLimit(4...)
                .appFont(size: 16)
                .focused($focused)
                .padding(14)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Palette.background)
                .navigationTitle(target.day == unscheduledDay ? "待排筆記" : "\(fmtShortDate(target.day)) 當日筆記")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("儲存") {
                            if model.write({ try Q.setDayNote($0, tripId: target.tripId, day: target.day, text: text) }) { dismiss() }
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .tint(Palette.primary)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = (model.read { try Q.dayNote($0, tripId: target.tripId, day: target.day) } ?? nil)?.text ?? ""
            focused = true
        }
    }
}

// MARK: - 貼上多筆、拆筆記

/// Pasting several places into a trip's 待排.
struct PasteTarget: Identifiable, Hashable {
    let tripId: Int64
    var id: Int64 { tripId }
}

/// Splitting one plan item's note into plan items.
struct SplitTarget: Identifiable, Hashable {
    let planId: Int64
    var id: Int64 { planId }
}

/// 「貼上多筆」: one place per line goes to 待排, with the time and a guessed category.
struct PasteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: PasteTarget
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let count = PlanParser.splitNote(text).count
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("一行一個地點,會加到「待排」,並自動猜分類。").appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
                TextEditor(text: $text)
                    .appFont(size: 16)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline))
                    .frame(minHeight: 160)
                HStack(spacing: 10) {
                    Button {
                        if let s = UIPasteboard.general.string { text = text.isEmpty ? s : text + "\n" + s }
                    } label: {
                        Label("貼上", systemImage: "doc.on.clipboard").appFont(size: 15, weight: .semibold).frame(minHeight: 44)
                    }
                    Spacer(minLength: 0)
                    if count > 0 { Text("會加入 \(count) 項").appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant) }
                }
            }
            .padding(16)
            .background(Palette.background)
            .navigationTitle("貼上多筆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("加入待排") { add() }.disabled(count == 0) }
            }
        }
        .tint(Palette.primary)
        .presentationDetents([.large])
        .onAppear { focused = true }
    }

    private func add() {
        let parsed = PlanParser.splitNote(text)
        let shared = (model.read { try Q.trip($0, target.tripId) } ?? nil)?.readOnly == true
        let categories = model.read { try Q.categories($0) } ?? []
        let ok = model.write { db in
            for p in parsed {
                let cat = p.categoryHint.flatMap { hint in categories.first { $0.name == hint }?.id }
                _ = try Q.savePlan(db, PlanItem(tripId: target.tripId, title: p.title, categoryId: cat, minuteOfDay: p.minuteOfDay,
                                                location: p.location, pending: shared), pictures: [])
            }
        }
        if ok {
            model.show("已加入 \(parsed.count) 項到待排")
            dismiss()
        }
    }
}

/// 「把筆記拆成多個行程」: every line is listed (nothing is silently dropped) with the guessed time and category;
/// untick lines that are not places, tap a category to change it.
struct SplitNoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: SplitTarget
    @State private var source: PlanItem?
    @State private var parsed: [ParsedPlace] = []
    @State private var chosen: [Bool] = []
    @State private var cats: [Int64?] = []

    var body: some View {
        let categories = model.read { try Q.categories($0) } ?? []
        let where_ = source?.date.map { " \(fmtShortDate($0)) " } ?? "「待排」"
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("每一行一個行程,排在\(where_)。不是地點的行取消勾選;分類猜錯點一下改。")
                        .appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
                    VStack(spacing: 0) {
                        ForEach(parsed.indices, id: \.self) { i in
                            if i > 0 { Divider().overlay(Palette.hairline).padding(.leading, 52) }
                            row(i, categories)
                        }
                    }
                    .ledgerCard(padding: 0)
                    if let s = source {
                        Text(s.pending ? "原本的「\(s.title)」會保留。" : "原本的「\(s.title)」整段筆記會移到\(where_)的「當日筆記」,方便對照;拆完也可以按「復原」。")
                            .appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                    }
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle("拆成 \(chosen.filter { $0 }.count) 個行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("建立") { create() }.disabled(!chosen.contains(true)) }
            }
        }
        .tint(Palette.primary)
        .onAppear(perform: load)
    }

    private func row(_ i: Int, _ categories: [LedgerCore.Category]) -> some View {
        let item = parsed[i]
        let cat = categories.first { $0.id == cats[i] }
        return HStack(spacing: 4) {
            Button { chosen[i].toggle() } label: {
                Image(systemName: chosen[i] ? "checkmark.square.fill" : "square").font(.system(size: 22))
                    .foregroundStyle(chosen[i] ? Palette.primary : Palette.textMuted)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .accessibilityAddTraits(chosen[i] ? .isSelected : [])
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).appFont(size: 16).foregroundStyle(Palette.onBackground)
                HStack(spacing: 8) {
                    if let m = item.minuteOfDay { Text(fmtTime(m)).appFont(size: 13, weight: .semibold).foregroundStyle(Palette.primary).tnum() }
                    Menu {
                        ForEach(categories) { c in Button(c.name) { cats[i] = c.id } }
                        Button("未分類") { cats[i] = nil }
                    } label: {
                        Text((cat?.name ?? "未分類") + " ▾").appFont(size: 13, weight: .semibold)
                            .foregroundStyle(cat == nil ? Palette.warning : Palette.onSurfaceVariant)
                            .frame(minHeight: 32)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 12).padding(.vertical, 4)
    }

    private func load() {
        guard source == nil, let p = model.read({ try Q.plan($0, target.planId) }) ?? nil else { return }
        source = p
        parsed = PlanParser.splitNote(p.note)
        chosen = Array(repeating: true, count: parsed.count)
        let categories = model.read { try Q.categories($0) } ?? []
        cats = parsed.map { place in place.categoryHint.flatMap { hint in categories.first { $0.name == hint }?.id } }
    }

    private func create() {
        guard let s = source else { return }
        let items = parsed.indices.filter { chosen[$0] }.map { i in
            PlanItem(tripId: s.tripId, title: parsed[i].title, categoryId: cats[i], date: s.date, minuteOfDay: parsed[i].minuteOfDay,
                     location: parsed[i].location, pending: s.pending)
        }
        // On someone else's trip, or for my own pending item, the original stays.
        let shared = (model.read { try Q.trip($0, s.tripId) } ?? nil)?.readOnly == true || s.pending
        var undo: SplitUndo?
        guard model.write({ undo = try Q.splitPlan($0, original: s, items: items, shared: shared) }), let undo else { return }
        dismiss()
        if !shared { model.closeDetail() } // the item this screen was showing is gone
        model.show("已拆成 \(items.count) 個行程" + (shared ? "" : ",原筆記放在當日筆記"), action: "復原") {
            model.write { try Q.undoSplit($0, undo) }
        }
    }
}
