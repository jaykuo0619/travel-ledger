import LedgerCore
import Photos
import PhotosUI
import SwiftUI
import UIKit
import Vision

/// Which expense the editor is open for (nil expenseId = a new one, optionally for a plan item).
struct ExpenseEditTarget: Identifiable, Hashable {
    let tripId: Int64
    var expenseId: Int64?
    var planId: Int64?
    var id: String { expenseId.map { "e\($0)" } ?? "new-\(tripId)-\(planId.map(String.init) ?? "x")" }
}

/// 記一筆 / 編輯 (ui/ExpenseScreens.kt): what it was, category, how it was paid, and a big keypad for the amount.
struct ExpenseEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.textScale) private var textScale
    let target: ExpenseEditTarget

    @State private var loaded = false
    @State private var original: Expense?
    @State private var title = ""
    @State private var amount = ""
    @State private var currency = homeCurrency
    @State private var rate = "1"
    @State private var categoryId: Int64?
    @State private var paymentId: Int64?
    @State private var date = todayEpochDay()
    @State private var minuteOfDay: Int?
    @State private var note = ""
    @State private var noteOpen = false
    @State private var photos: [Photo] = []
    @State private var currencies: [String] = [homeCurrency]
    @State private var tripRates: [String: Double] = [:]
    @State private var lastExpense: Expense?
    @State private var suggestions: [TitleSuggestion] = []

    @FocusState private var focus: Field?
    @State private var keyboardUp = false
    @State private var pickingDate = false
    @State private var editingRate = false
    @State private var rateDraft = ""
    @State private var pickingCurrency = false
    @State private var confirmDelete = false
    @State private var photoItems: [PhotosPickerItem] = []
    /// The camera is up: for a receipt (read it) or for a memory (just keep it).
    @State private var camera: CameraMode?
    @State private var processing = false
    @State private var ocrText = ""
    /// What was read from the last receipt, waiting for 套用 or 略過.
    @State private var receipt: ReceiptGuess?
    @State private var viewing: Int?
    /// Drawing on one of the photos.
    @State private var drawingOn: Int?
    /// Files to remove once the expense is saved (replaced by a drawn-on copy) or if it is not saved (the copies).
    @State private var replacedFiles: [String] = []
    @State private var copyFiles: [String] = []
    /// Writing 「拉麵 1200」 by hand instead of typing.
    @State private var handwriting = false

    enum Field { case title, note }

    private var amountValue: Double? { Double(amount).flatMap { $0 > 0 ? $0 : nil } }
    private var rateValue: Double? { Double(rate).flatMap { $0 > 0 ? $0 : nil } }
    private var homeAmount: Double? { amountValue.flatMap { a in rateValue.map { toHomeAmount(a, $0) } } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            titleField
                            categoryRow
                            paymentRow
                            noteField
                            if let receipt { receiptCard(receipt).id("receipt") }
                            photoRow
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    // What was read from a receipt comes into view by itself (its buttons sit under the keypad otherwise).
                    .onChange(of: receipt) { _, now in
                        if now != nil { withAnimation { proxy.scrollTo("receipt", anchor: .bottom) } }
                    }
                }
                // The keypad makes room for the keyboard while a text field is being typed in.
                if !keyboardUp {
                    KeypadPanel(amount: amount, currency: currency, rate: rate, home: homeAmount, canSave: homeAmount != nil,
                                currencies: currencies, keyHeight: Binding(get: { model.settings.keypadKeyHeight }, set: { model.settings.keypadKeyHeight = $0 }),
                                onKey: { amount = applyKey(amount, $0) }, onCurrency: setCurrency,
                                onOtherCurrency: { pickingCurrency = true },
                                onRate: { rateDraft = rate; editingRate = true }, onSave: save)
                        .transition(.move(edge: .bottom))
                }
            }
            .background(Palette.background)
            .navigationTitle(original == nil ? "記一筆" : "編輯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close() } label: { Image(systemName: "xmark") }.accessibilityLabel("關閉").disabled(processing)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { pickingDate = true } label: {
                        Text(fmtShortDateTime(date, minuteOfDay)).appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
                    }
                    if original != nil {
                        Button { confirmDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("刪除")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focus = nil }
                }
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .interactiveDismissDisabled()
        .tint(Palette.primary)
        .onAppear(perform: load)
        .onAppear { model.refreshReferenceRates() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in withAnimation(.easeOut(duration: 0.2)) { keyboardUp = true } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in withAnimation(.easeOut(duration: 0.2)) { keyboardUp = false } }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicked(items) }
        }
        .sheet(isPresented: $pickingDate) {
            DateTimeSheet(day: date, minute: minuteOfDay) { d, m in date = d; minuteOfDay = m }
        }
        .sheet(isPresented: $pickingCurrency) {
            CurrencyPickerSheet(current: currency) { setCurrency($0) }
        }
        .fullScreenCover(item: $camera) { mode in
            CameraPicker { image in
                if let image { Task { await addImage(image, mode: mode == .receipt ? PhotoType.receipt : PhotoType.memory) } }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(get: { viewing.map(ViewerStart.init) }, set: { viewing = $0?.index })) { start in
            PhotoViewer(paths: photos.map { ($0.path, $0.type) }, start: start.index)
        }
        .fullScreenCover(item: Binding(get: { drawingOn.map(ViewerStart.init) }, set: { drawingOn = $0?.index })) { start in
            DrawingSheet(title: "在照片上畫記", background: photos.indices.contains(start.index) ? model.storedImage(photos[start.index].path) : nil) { data in
                replacePhoto(start.index, with: data)
            }
        }
        .fullScreenCover(isPresented: $handwriting) {
            DrawingSheet(title: "手寫記帳:寫下名稱和金額", background: nil, pageSize: CGSize(width: 1600, height: 900), saveText: "辨識") { data in
                Task { await readHandwriting(data) }
            }
        }
        .alert("1 \(currency) = ? 新台幣", isPresented: $editingRate) {
            TextField("匯率", text: $rateDraft).keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("確定") { rate = rateDraft.filter { ("0" ... "9").contains($0) || $0 == "." } }
        }
        .alert("刪除這筆支出?", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("刪除", role: .destructive) { delete() }
        } message: {
            Text("照片也會一併刪除。")
        }
    }

    // MARK: Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldBox("名稱") {
                TextField("", text: $title, prompt: Text("店家或項目名稱").foregroundStyle(Palette.textMuted))
                    .appFont(size: 17, weight: .semibold)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
            }
            // Names used before, while the field is being typed in; picking one also brings its category.
            if focus == .title {
                let found = matchSuggestions(suggestions, typed: title)
                if !found.isEmpty {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(found, id: \.title) { s in
                            Button {
                                title = s.title
                                if let c = s.categoryId { categoryId = c }
                                focus = nil
                            } label: {
                                Text(s.title).appFont(size: 15).lineLimit(1)
                                    .padding(.horizontal, 12).frame(minHeight: 36)
                                    .background(Palette.surfaceVariant, in: Capsule())
                                    .foregroundStyle(Palette.onBackground)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var categoryRow: some View {
        let categories = model.read { try Q.categories($0) } ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { c in
                    let style = IconStyle.category(name: c.name, icon: c.icon, color: c.color)
                    SelectPill(c.name, selected: categoryId == c.id) { categoryId = c.id } leading: {
                        Image(systemName: style.symbol).font(.system(size: 14)).foregroundStyle(style.color)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// Up to three ways to pay share the width; more scroll sideways. With large text the icons go.
    private var paymentRow: some View {
        let methods = model.read { try Q.paymentMethods($0) } ?? []
        let pills = ForEach(methods) { m in
            Button { paymentId = m.id } label: {
                HStack(spacing: 6) {
                    if textScale < 1.1 { Image(systemName: Icons.payment(m.name)).font(.system(size: 14)) }
                    Text(m.name).appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
                }
                .foregroundStyle(paymentId == m.id ? Palette.onPrimaryContainer : Palette.onBackground)
                .padding(.horizontal, 10)
                .frame(maxWidth: methods.count <= 3 ? .infinity : nil, minHeight: 40)
                .background(paymentId == m.id ? Palette.primaryContainer : Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(paymentId == m.id ? Palette.primary : Palette.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(paymentId == m.id ? .isSelected : [])
        }
        return Group {
            if methods.count <= 3 {
                HStack(spacing: 8) { pills }
            } else {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { pills }.padding(.vertical, 1) }
            }
        }
    }

    /// Reads what was written by hand (on the device) and fills in the name and the amount; both stay editable.
    private func readHandwriting(_ data: Data) async {
        processing = true
        defer { processing = false }
        let hint = currency
        let lines = await Task.detached(priority: .userInitiated) { recognizeText(data, currency: hint) }.value
        let text = lines.sorted { $0.top < $1.top }.map(\.text).joined(separator: "\n")
        let read = parseHandwritten(text)
        if read.title.isEmpty, read.amount == nil {
            model.show("看不出寫了什麼,再寫大一點試試")
            return
        }
        if !read.title.isEmpty { title = read.title }
        if let a = read.amount { amount = fmtNumber(a) }
        model.show(read.amount == nil ? "讀到名稱「\(read.title)」,金額請用鍵盤補上" : "讀到:\(read.title.isEmpty ? "" : read.title + " ")\(fmtNumber(read.amount ?? 0))")
    }

    @ViewBuilder private var noteField: some View {
        if noteOpen {
            FieldBox("備註") {
                TextField("", text: $note, prompt: Text("例如:點了特製拉麵").foregroundStyle(Palette.textMuted), axis: .vertical)
                    .appFont(size: 16)
                    .focused($focus, equals: .note)
            }
        } else {
            HStack(spacing: 18) {
                Button {
                    noteOpen = true
                    focus = .note
                } label: {
                    Label("加備註", systemImage: "square.and.pencil").appFont(size: 15, weight: .semibold).frame(minHeight: 40)
                }
                Button { handwriting = true } label: {
                    Label("手寫", systemImage: "pencil.and.scribble").appFont(size: 15, weight: .semibold).frame(minHeight: 40)
                }
            }
        }
    }

    private var photoRow: some View {
        let full = photos.count >= maxExpensePhotos
        return VStack(alignment: .leading, spacing: 8) {
            if !photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(photos.indices, id: \.self) { i in
                        Button { viewing = i } label: {
                            LocalImage(path: photos[i].path, maxPixel: 300) { Palette.surfaceVariant }
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("照片 \(i + 1)")
                        .overlay(alignment: .bottomLeading) {
                            // 收據 ↔ 回憶
                            Button { toggleType(i) } label: {
                                PhotoTypeBadge(type: photos[i].type).padding(5).frame(minWidth: 44, minHeight: 36, alignment: .bottomLeading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photos[i].type == PhotoType.receipt ? "收據,點兩下改成回憶" : "回憶,點兩下改成收據")
                        }
                        .overlay(alignment: .topTrailing) {
                            Button { removePhoto(i) } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.black.opacity(0.55), in: Circle())
                                    .frame(width: 40, height: 40, alignment: .topTrailing)
                                    .padding(4)
                            }
                            .accessibilityLabel("移除照片")
                        }
                        .overlay(alignment: .bottomTrailing) {
                            // Circle an amount, mark whose item it is…
                            Button { drawingOn = i } label: {
                                Image(systemName: "pencil.tip.crop.circle.fill").font(.system(size: 24))
                                    .symbolRenderingMode(.palette).foregroundStyle(.white, Palette.primary)
                                    .frame(width: 40, height: 40, alignment: .bottomTrailing).padding(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("在這張照片上畫記")
                        }
                    }
                }
            }
            // 拍收據 reads the amount, shop and date; 拍照 keeps a memory; 相簿 decides from the picture.
            FlowLayout(spacing: 8, lineSpacing: 8) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    photoButton("拍收據", "doc.text.viewfinder") { camera = .receipt }
                    photoButton("拍照", "camera") { camera = .memory }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: max(maxExpensePhotos - photos.count, 1), matching: .images) {
                    photoLabel("相簿", "photo.on.rectangle")
                }
                .disabled(full || processing)
            }
            if processing || full {
                Text(processing ? "處理照片中…" : "已滿 \(maxExpensePhotos) 張").appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
            }
        }
    }

    /// 「從收據讀到」: what was recognized, to apply or ignore.
    private func receiptCard(_ g: ReceiptGuess) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("從收據讀到", systemImage: "doc.text.magnifyingglass").appFont(size: 16, weight: .semibold)
            if let store = g.store { Text("店家:\(store)").appFont(size: 15) }
            if let total = g.total { Text("金額:\(fmtAmount(total, g.currency ?? currency))").appFont(size: 15).tnum() }
            if let d = g.date { Text("時間:\(fmtShortDateTime(d, g.minuteOfDay))").appFont(size: 15) }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("略過") { receipt = nil }.appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant).frame(minWidth: 60, minHeight: 44)
                Button { applyReceipt(g) } label: {
                    Text("套用").appFont(size: 15, weight: .semibold).foregroundStyle(Palette.onPrimary)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(Palette.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Palette.onBackground)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.primaryContainer.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    /// The name only when none was typed; a different currency switches (with its rate); amount, date and time are taken.
    private func applyReceipt(_ g: ReceiptGuess) {
        if let store = g.store, title.isBlank { title = store }
        if let c = g.currency, c != currency { setCurrency(c) }
        if let total = g.total { amount = fmtNumber(total) }
        if let d = g.date { date = d }
        if let m = g.minuteOfDay { minuteOfDay = m }
        receipt = nil
    }

    private func photoButton(_ text: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { photoLabel(text, symbol) }
            .disabled(photos.count >= maxExpensePhotos || processing)
    }

    private func photoLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Palette.secondaryContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        tripRates = Dictionary((model.read { try Q.rates($0, target.tripId) } ?? []).map { ($0.currency, $0.rate) }, uniquingKeysWith: { a, _ in a })
        lastExpense = model.read { try Q.latestExpense($0, target.tripId) } ?? nil
        suggestions = model.read { try Q.titleSuggestions($0) } ?? []
        if let id = target.expenseId, let e = model.read({ try Q.expense($0, id) }) ?? nil {
            original = e
            title = e.title
            amount = fmtNumber(e.amount)
            currency = e.currency
            rate = fmtNumber(e.rate)
            categoryId = e.categoryId
            paymentId = e.paymentMethodId
            date = e.date
            minuteOfDay = e.minuteOfDay
            note = e.note
            noteOpen = !e.note.isBlank
            ocrText = e.ocrText
            photos = model.read { try Q.photos($0, expenseId: id) } ?? []
            var seen = Set<String>()
            currencies = ([homeCurrency] + tripRates.keys.sorted() + [e.currency]).filter { seen.insert($0).inserted }
        } else if let d = model.read({ try Q.expenseDefaults($0, tripId: target.tripId, planId: target.planId) }) {
            title = d.title
            currency = d.currency
            rate = d.rate
            categoryId = d.categoryId
            paymentId = d.paymentId
            currencies = d.currencies
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    private func setCurrency(_ code: String) {
        currency = code
        rate = Q.rateText(code, tripRates: tripRates, last: lastExpense)
        // No rate known for this trip yet: start from today's reference rate (still editable).
        if rate.isEmpty, let suggested = model.suggestedRate(code) { rate = suggested }
        if !currencies.contains(code) { currencies.append(code) }
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        processing = true
        defer { processing = false; photoItems = [] }
        for item in items.prefix(maxExpensePhotos - photos.count) {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                model.show("無法讀取這張照片")
                continue
            }
            await store(data, mode: nil)
        }
    }

    private func addImage(_ image: UIImage, mode: String) async {
        processing = true
        defer { processing = false }
        guard let data = image.jpegData(compressionQuality: 0.95) else { return }
        await store(data, mode: mode)
    }

    /// Keeps a photo (photo/PhotoProcessor.kt). [mode]: RECEIPT reads it, MEMORY just keeps it, nil decides from
    /// the content (pictures from the library). Receipts are kept at 1600 px, memories at 1200.
    private func store(_ data: Data, mode: String?) async {
        guard photos.count < maxExpensePhotos else { return }
        let hint = currency
        let read: (lines: [OcrLine], guess: ReceiptGuess) = mode == PhotoType.memory
            ? ([], ReceiptGuess(isReceipt: false))
            : await Task.detached(priority: .userInitiated) {
                let lines = recognizeText(data, currency: hint)
                return (lines, ReceiptParser.parse(lines, force: mode == PhotoType.receipt))
            }.value
        let type = read.guess.isReceipt ? PhotoType.receipt : PhotoType.memory
        let edge: CGFloat = type == PhotoType.receipt ? 1600 : 1200
        guard let jpeg = await Task.detached(operation: { downscaledJPEG(data, maxEdge: edge, quality: 0.82) }).value,
              let path = try? model.files.write(jpeg, folder: type == PhotoType.receipt ? "photos/receipts" : "photos/memories")
        else {
            model.show("無法讀取這張照片")
            return
        }
        let size = UIImage(data: jpeg)?.size ?? .zero
        photos.append(Photo(expenseId: original?.id ?? 0, type: type, path: path, width: Int(size.width), height: Int(size.height)))
        // The recognized text is kept with the expense (top to bottom), and offered as a receipt when it reads like one.
        let text = read.lines.sorted { $0.top < $1.top }.map(\.text).joined(separator: "\n")
        if !text.isBlank { ocrText = [ocrText, text].filter { !$0.isBlank }.joined(separator: "\n") }
        if type == PhotoType.receipt, read.guess.hasData { receipt = read.guess }
    }

    /// An expense holds three photos at most, so the drawn-on copy takes the photo's place.
    private func replacePhoto(_ i: Int, with data: Data) {
        guard photos.indices.contains(i) else { return }
        let folder = photos[i].type == PhotoType.receipt ? "photos/receipts" : "photos/memories"
        guard let path = try? model.files.write(data, folder: folder) else {
            model.show("儲存失敗")
            return
        }
        let old = photos[i].path
        if photos[i].id == nil { model.files.delete(old) } else { replacedFiles.append(old) } // a saved one goes on save
        copyFiles.append(path)
        let size = UIImage(data: data)?.size ?? .zero
        photos[i].path = path
        photos[i].width = Int(size.width)
        photos[i].height = Int(size.height)
    }

    private func toggleType(_ i: Int) {
        guard photos.indices.contains(i) else { return }
        photos[i].type = photos[i].type == PhotoType.receipt ? PhotoType.memory : PhotoType.receipt
    }

    private func removePhoto(_ i: Int) {
        guard photos.indices.contains(i) else { return }
        let p = photos.remove(at: i)
        if p.id == nil { model.files.delete(p.path) } // saved photos are removed on save
    }

    /// Leaving without saving: photos added this time are thrown away.
    private func close() {
        photos.filter { $0.id == nil }.forEach { model.files.delete($0.path) }
        model.files.delete(copyFiles) // drawn-on copies of photos whose originals stay
        dismiss()
    }

    private func save() {
        guard let a = amountValue, let r = rateValue, let home = homeAmount else { return }
        var e = original ?? Expense(tripId: target.tripId, date: date, amount: a, currency: currency, rate: r, homeAmount: home)
        e.date = date
        e.minuteOfDay = minuteOfDay
        e.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        e.amount = a
        e.currency = currency
        e.rate = r
        e.homeAmount = home
        e.categoryId = categoryId
        e.paymentMethodId = paymentId
        e.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        e.ocrText = ocrText
        if original == nil { e.planItemId = target.planId }

        // New memory photos also go to the photo library when the setting says so.
        let toLibrary = model.settings.saveMemoriesToGallery
        var toSave = photos
        var libraryFiles: [URL] = []
        for i in toSave.indices where toSave[i].id == nil && toSave[i].type == PhotoType.memory && toLibrary {
            toSave[i].savedToGallery = true
            libraryFiles.append(model.files.url(toSave[i].path))
        }
        var removed: [String] = []
        if model.write({ removed = try Q.saveExpense($0, e, photos: toSave).removed }) {
            model.files.delete(removed)
            model.files.delete(replacedFiles)
            libraryFiles.forEach(saveToPhotoLibrary)
            dismiss()
        } else {
            model.show("儲存失敗")
        }
    }

    private func delete() {
        guard let id = original?.id else { return }
        var paths: [String] = []
        if model.write({ paths = try Q.deleteExpense($0, id) }) {
            model.files.delete(paths)
            photos.filter { $0.id == nil }.forEach { model.files.delete($0.path) }
            dismiss()
        }
    }
}

enum CameraMode: String, Identifiable {
    case receipt, memory
    var id: String { rawValue }
}

/// Reads the text in a picture on the device (Vision), as lines with their boxes in pixels from the top-left.
/// The script follows the currency being recorded: JPY → Japanese, KRW → Korean, otherwise Chinese + English.
func recognizeText(_ data: Data, currency: String) -> [OcrLine] {
    guard let jpeg = downscaledJPEG(data, maxEdge: 2400, quality: 0.9), let image = UIImage(data: jpeg)?.cgImage else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    switch currency {
    case "JPY": request.recognitionLanguages = ["ja-JP", "en-US"]
    case "KRW": request.recognitionLanguages = ["ko-KR", "en-US"]
    default: request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
    }
    do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch { return [] }
    let w = Double(image.width), h = Double(image.height)
    return (request.results ?? []).compactMap { o in
        guard let text = o.topCandidates(1).first?.string else { return nil }
        let b = o.boundingBox // normalized, origin at the bottom-left
        return OcrLine(text, Int(b.minX * w), Int((1 - b.maxY) * h), Int(b.maxX * w), Int((1 - b.minY) * h))
    }
}

/// Adds a picture file to the photo library (asks for add-only access the first time).
func saveToPhotoLibrary(_ file: URL) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else { return }
        PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: nil)
        }
    }
}

/// The system camera, for one picture.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onDone: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onDone(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDone(nil)
            parent.dismiss()
        }
    }
}

// MARK: - Keypad

/// The calculator at the bottom (ui/Keypad.kt): currency and amount, the rate line, digits and 儲存.
/// Drag the handle to make the keys taller or shorter; the height is remembered.
private struct KeypadPanel: View {
    let amount: String
    let currency: String
    let rate: String
    let home: Double?
    let canSave: Bool
    let currencies: [String]
    @Binding var keyHeight: Double
    let onKey: (String) -> Void
    let onCurrency: (String) -> Void
    let onOtherCurrency: () -> Void
    let onRate: () -> Void
    let onSave: () -> Void
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 8) {
            Capsule().fill(Palette.outline).frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            let start = dragStart ?? keyHeight
                            dragStart = start
                            keyHeight = min(max(start - v.translation.height / 4, 40), 80)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .accessibilityLabel("調整按鍵高度")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Menu {
                    ForEach(currencies, id: \.self) { c in
                        Button { onCurrency(c) } label: {
                            if c == currency { Label("\(c) \(currencyNames[c] ?? "")", systemImage: "checkmark") } else { Text("\(c) \(currencyNames[c] ?? "")") }
                        }
                    }
                    Divider()
                    Button("其他幣別…", action: onOtherCurrency)
                } label: {
                    HStack(spacing: 4) {
                        Text(currency).appFont(size: 17, weight: .bold)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Palette.primaryContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Palette.onPrimaryContainer)
                }
                Text(amount.isEmpty ? "0" : fmtTyped(amount))
                    .font(.system(size: 38, weight: .bold)).tnum()
                    .foregroundStyle(amount.isEmpty ? Palette.textMuted : Palette.onBackground)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("金額 \(amount.isEmpty ? "0" : amount)")
            }

            rateLine

            // Three columns of digits; the fourth has ⌫, C and a 儲存 two keys tall.
            GeometryReader { geo in
                let gap: CGFloat = 8
                let w = (geo.size.width - gap * 3) / 4
                HStack(alignment: .top, spacing: gap) {
                    Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                        GridRow { key("7"); key("8"); key("9") }
                        GridRow { key("4"); key("5"); key("6") }
                        GridRow { key("1"); key("2"); key("3") }
                        GridRow { key("00"); key("0"); key(".") }
                    }
                    .frame(width: w * 3 + gap * 2)
                    VStack(spacing: gap) {
                        backspace
                        key("C")
                        Button(action: onSave) {
                            Text("儲存").appFont(size: 17, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: keyHeight * 2 + gap)
                                .foregroundStyle(canSave ? Palette.onPrimary : Palette.onSurfaceVariant)
                                .background(canSave ? Palette.primary : Palette.surfaceVariant, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                    }
                    .frame(width: w)
                }
            }
            .frame(height: keyHeight * 4 + 8 * 3)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Palette.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(Palette.hairline) }
    }

    @ViewBuilder private var rateLine: some View {
        HStack(spacing: 6) {
            if currency == homeCurrency {
                Text("新台幣").appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
                Spacer(minLength: 0)
            } else {
                Button(action: onRate) {
                    HStack(spacing: 4) {
                        if rate.isEmpty || Double(rate) == nil || (Double(rate) ?? 0) <= 0 {
                            Text("請設定匯率").appFont(size: 15, weight: .semibold).foregroundStyle(Palette.danger)
                        } else {
                            Text("匯率 \(rate)").appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
                        }
                        Image(systemName: "pencil").font(.system(size: 13, weight: .semibold))
                    }
                    .frame(minHeight: 36)
                }
                Spacer(minLength: 8)
                if let home { Text("≈ \(fmtMoney(home))").appFont(size: 15, weight: .semibold).tnum().lineLimit(1) }
            }
        }
        .frame(minHeight: 36)
    }

    private func key(_ k: String) -> some View {
        Button { onKey(k) } label: {
            Text(k).font(.system(size: 24, weight: .semibold)).tnum()
                .frame(maxWidth: .infinity, minHeight: keyHeight)
                .foregroundStyle(k == "C" ? Palette.danger : Palette.onBackground)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(k == "C" ? "清除" : k)
    }

    /// ⌫ deletes one digit; holding it clears.
    private var backspace: some View {
        Image(systemName: "delete.left").font(.system(size: 22, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: keyHeight)
            .foregroundStyle(Palette.onBackground)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onKey("⌫") }
            .onLongPressGesture { onKey("C") }
            .accessibilityLabel("刪除一位")
            .accessibilityAddTraits(.isButton)
    }
}

/// Date first (「下一步:時間」), then a 24-hour time: 「確定」 or 「不記時間」.
private struct DateTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: Int64
    let minute: Int?
    let onPick: (Int64, Int?) -> Void
    @State private var date = Date()
    @State private var time = Date()
    @State private var onTime = false

    var body: some View {
        NavigationStack {
            Group {
                if onTime {
                    DatePicker("時間", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden()
                        .environment(\.locale, Locale(identifier: "en_GB"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.locale, Locale(identifier: "zh_TW"))
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .navigationTitle(onTime ? "時間" : "日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if onTime {
                        Button("不記時間") { onPick(CivilDate.today(date).epochDay, nil); dismiss() }
                    } else {
                        Button("取消") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if onTime {
                        Button("確定") {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                            onPick(CivilDate.today(date).epochDay, (c.hour ?? 0) * 60 + (c.minute ?? 0))
                            dismiss()
                        }
                    } else {
                        Button("下一步:時間") { onTime = true }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .tint(Palette.primary)
        .onAppear {
            date = day.civil.date()
            let m = minute ?? 12 * 60
            time = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }
    }
}
