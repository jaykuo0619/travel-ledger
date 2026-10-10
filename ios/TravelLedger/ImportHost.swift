import LedgerCore
import SwiftUI

/// What an incoming file will do, worked out before anything is written.
enum ImportStep: Identifiable, Sendable {
    case confirm(TripArchive.Summary, existing: Set<String>, newer: [String])
    case additions(TripArchive.Additions)
    case plans(TripArchive.PlansPreview)

    var id: String {
        switch self {
        case .confirm: return "confirm"
        case .additions: return "additions"
        case .plans: return "plans"
        }
    }
}

/// Watches AppModel.incoming: reads the file, asks for confirmation, imports it and opens the trip
/// (ui/ShareBackup.kt ImportHost). Sits at the root so a file can arrive on any screen.
struct ImportHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var step: ImportStep?
    @State private var busy = false

    func body(content: Content) -> some View {
        content
            // Another sheet (trip editor, settings) has to close first; the file waits.
            .task(id: Waiting(file: model.incoming, blocked: model.editing != nil || model.showSettings)) { await prepare() }
            .sheet(item: $step, onDismiss: { if !busy, model.incoming != nil { model.cancelImport() } }) { s in
                Group {
                    switch s {
                    case let .confirm(summary, existing, newer):
                        ImportConfirmSheet(summary: summary, existing: existing, newerHere: newer, busy: busy,
                                           onCancel: cancel) { run { $0.importFile($1) } }
                    case .additions(let adds):
                        ReviewAdditionsSheet(additions: adds, busy: busy, onCancel: cancel) { chosen in
                            run { $0.importAdditions($1, accepted: chosen) }
                        }
                    case .plans(let preview):
                        PlansPreviewSheet(preview: preview, busy: busy, onCancel: cancel) { run { $0.importPlans($1) } }
                    }
                }
                .interactiveDismissDisabled(busy)
                .presentationDetents([.medium, .large])
            }
    }

    private struct Waiting: Equatable {
        let file: URL?
        let blocked: Bool
    }

    private func prepare() async {
        guard let url = model.incoming, model.editing == nil, !model.showSettings else { return }
        // Give a closing sheet time to leave before the next one is presented.
        try? await Task.sleep(for: .milliseconds(350))
        guard model.incoming == url else { return }
        let archive = model.archive
        let outcome: Result<ImportStep, Error> = await Task.detached(priority: .userInitiated) {
            Result<ImportStep, Error> {
                let s = try TripArchive.readSummary(url)
                switch s.kind {
                case TripArchive.kindAdditions: return .additions(try TripArchive.readAdditions(url))
                case TripArchive.kindPlans: return .plans(try archive.previewPlans(url))
                default:
                    let newer = s.kind == TripArchive.kindBackup ? try archive.newerOnPhone(s) : []
                    return .confirm(s, existing: try archive.existing(s), newer: newer)
                }
            }
        }.value
        guard model.incoming == url else { return }
        switch outcome {
        case .success(let s): step = s
        case .failure(let e):
            model.cancelImport()
            model.show((e as? TripArchive.BadArchive)?.message ?? "無法開啟這個檔案")
        }
    }

    private func cancel() {
        step = nil
        model.cancelImport()
    }

    private func run(_ work: @escaping @Sendable (TripArchive, URL) -> TripArchive.Result) {
        guard let url = model.incoming else { return }
        busy = true
        let archive = model.archive
        Task {
            let result = await Task.detached(priority: .userInitiated) { work(archive, url) }.value
            busy = false
            step = nil
            model.finishImport(result)
        }
    }
}

/// "3/5 21:04" from epoch millis.
private func stamp(_ millis: Int64) -> String {
    let c = localDateTime(millis: millis)
    return String(format: "%d/%d %02d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
}

/// Header + scrolling body + buttons, the shape of an Android dialog.
private struct DialogSheet<Body: View>: View {
    let symbol: String
    let title: String
    let busy: Bool
    let cancelText: String
    let confirmText: String?
    var confirmEnabled = true
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var content: Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Palette.primary)
                        Text(title).appFont(size: 21, weight: .bold)
                    }
                    content
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Palette.hairline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(spacing: 10) { buttons }
            }
            .padding(16)
        }
        .foregroundStyle(Palette.onBackground)
        .background(Palette.card)
    }

    @ViewBuilder private var buttons: some View {
        Button(action: onCancel) {
            Text(cancelText).appFont(size: 16, weight: .semibold).frame(maxWidth: .infinity, minHeight: 48)
                .background(Palette.secondaryContainer, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        if let confirmText {
            PillButton(confirmText, height: 48, enabled: confirmEnabled && !busy, action: onConfirm)
        }
    }
}

private struct ImportConfirmSheet: View {
    let summary: TripArchive.Summary
    let existing: Set<String>
    /// Trips on this phone holding more recent records than the backup; restoring would lose them.
    let newerHere: [String]
    let busy: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let shared = summary.kind == TripArchive.kindTrip
        let confirm = !shared && !newerHere.isEmpty ? "仍要還原" : !shared ? "還原" : summary.trips.contains { existing.contains($0.uuid) } ? "更新" : "匯入"
        DialogSheet(symbol: shared ? "person.2.badge.plus" : "arrow.counterclockwise", title: shared ? "\(summary.sharedBy ?? "同伴") 分享的旅程" : "還原備份",
                    busy: busy, cancelText: "取消", confirmText: confirm, onCancel: onCancel, onConfirm: onConfirm) {
            ForEach(summary.trips.prefix(6), id: \.uuid) { t in
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).appFont(size: 17, weight: .semibold)
                    Text("\(fmtShortDate(t.startDate)) – \(fmtShortDate(t.endDate)) · \(t.expenseCount) 筆 · \(fmtMoney(t.totalHome))")
                        .appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                    if existing.contains(t.uuid) {
                        Text("手機上已有這趟旅程,會更新成這份").appFont(size: 13).foregroundStyle(Palette.primary)
                    }
                }
            }
            if summary.trips.count > 6 { Text("…共 \(summary.trips.count) 個旅程").appFont(size: 13) }
            Text("\(stamp(summary.exportedAt)) 製作" + (summary.photoCount > 0 ? " · 含 \(summary.photoCount) 張照片" : " · 不含照片") + "\n" +
                (shared ? "匯入後只能看、不能改。對方再分享一次,打開新檔案就會更新。" : "手機上已有的同一趟旅程會被備份內容取代,其他旅程保留不動。"))
                .appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
            if !newerHere.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.error)
                    Text("手機上的「\(newerHere.joined(separator: "」「"))」比這份備份新,還原會蓋掉備份之後記的內容。")
                        .appFont(size: 15).foregroundStyle(Palette.onErrorContainer)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.errorContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

/// The organizer looks through a companion's additions and ticks what goes into the book.
private struct ReviewAdditionsSheet: View {
    let additions: TripArchive.Additions
    let busy: Bool
    let onCancel: () -> Void
    let onAccept: (Set<String>) -> Void
    @State private var chosen: Set<String>

    init(additions: TripArchive.Additions, busy: Bool, onCancel: @escaping () -> Void, onAccept: @escaping (Set<String>) -> Void) {
        self.additions = additions; self.busy = busy; self.onCancel = onCancel; self.onAccept = onAccept
        _chosen = State(initialValue: Set(additions.items.map(\.uuid)))
    }

    var body: some View {
        DialogSheet(symbol: "text.badge.plus", title: "\(additions.from) 的補充", busy: busy, cancelText: "略過全部",
                    confirmText: "加入 \(chosen.count) 項", confirmEnabled: !chosen.isEmpty, onCancel: onCancel, onConfirm: { onAccept(chosen) }) {
            Text("要加入「\(additions.tripName)」的項目打勾。加入後記得再分享一次給大家。")
                .appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
            ForEach(additions.items) { item in
                let on = chosen.contains(item.uuid)
                Button {
                    if on { chosen.remove(item.uuid) } else { chosen.insert(item.uuid) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 22))
                            .foregroundStyle(on ? Palette.primary : Palette.onSurfaceVariant)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).appFont(size: 16)
                            Text(item.detail).appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }
}

private struct PlansPreviewSheet: View {
    let preview: TripArchive.PlansPreview
    let busy: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let refused = preview.refused != nil
        DialogSheet(symbol: "desktopcomputer", title: refused ? "無法併入" : "電腦排的行程", busy: busy,
                    cancelText: refused ? "知道了" : "取消", confirmText: refused ? nil : "併入", onCancel: onCancel, onConfirm: onConfirm) {
            Text(preview.tripName).appFont(size: 17, weight: .semibold)
            Text(preview.refused ?? message).appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
        }
    }

    private var message: String {
        var s = ""
        if preview.newTrip { s += "手機上還沒有這趟旅程,會新建一趟。\n" }
        s += "新增 \(preview.added) 個、更新 \(preview.updated) 個"
        if preview.deleted > 0 { s += "、刪除 \(preview.deleted) 個" }
        s += "行程。\n帳目不會被改動;同一個行程以電腦上的內容為準。"
        return s
    }
}
