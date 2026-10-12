import LedgerCore
import SwiftUI
import UIKit

/// What is being sent out (ui/ShareBackup.kt): a trip for companions, a trip for the desktop planner,
/// my additions for the organizer, or a backup of everything.
enum ShareTarget: Identifiable, Hashable {
    case trip(Int64), desktop(Int64), additions(Int64), backup

    var id: String {
        switch self {
        case .trip(let id): return "trip-\(id)"
        case .desktop(let id): return "desktop-\(id)"
        case .additions(let id): return "additions-\(id)"
        case .backup: return "backup"
        }
    }
}

/// A file ready to hand to the system share sheet or the Files app.
private struct Outgoing: Identifiable {
    let id = UUID()
    let url: URL
    let subject: String
    let text: String
    let toFiles: Bool
}

struct ShareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: ShareTarget
    @State private var name = ""
    @State private var includePhotos = false
    @State private var busy = false
    @State private var outgoing: Outgoing?
    @State private var loaded = false

    var body: some View {
        let trip = tripId.flatMap { id in model.read { try Q.trip($0, id) } ?? nil }
        let tripName = trip?.name ?? ""
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(explanation(trip)).appFont(size: 16).foregroundStyle(Palette.onBackground)
                    if needsName {
                        FieldBox(target == .backup ? "" : "你的名字(同伴會看到)") {
                            TextField("", text: $name, prompt: Text("例如:小明").foregroundStyle(Palette.textMuted))
                                .appFont(size: 16)
                                .onChange(of: name) { _, v in if v.count > 20 { name = String(v.prefix(20)) } }
                        }
                    }
                    if hasPhotoChoice {
                        Toggle(isOn: $includePhotos) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("包含照片").appFont(size: 16)
                                Text(photoNote).appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                            }
                        }
                        .tint(Palette.primary)
                        .ledgerCard(padding: 14)
                    }
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    PillButton(sendText, symbol: "square.and.arrow.up", enabled: canSend && !busy) { make(tripName, toFiles: false) }
                    if target == .backup {
                        PillButton("存到手機", symbol: "folder", enabled: !busy) { make(tripName, toFiles: true) }
                    }
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle(title(trip))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } }
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .presentationDetents([.medium, .large])
        .tint(Palette.primary)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = model.settings.myName
            includePhotos = target == .backup // a backup keeps receipts, memories and covers by default
        }
        .sheet(item: $outgoing, onDismiss: { dismiss() }) { out in
            if out.toFiles {
                ExportPicker(url: out.url) { saved in if saved { finished() } }.ignoresSafeArea()
            } else {
                ActivityView(items: [out.url, out.text], subject: out.subject) { done in if done { finished() } }.ignoresSafeArea()
            }
        }
    }

    // MARK: Texts

    private var tripId: Int64? {
        switch target {
        case .trip(let id), .desktop(let id), .additions(let id): return id
        case .backup: return nil
        }
    }

    private var needsName: Bool {
        switch target {
        case .trip, .additions: return true
        case .desktop, .backup: return false
        }
    }

    private var hasPhotoChoice: Bool { if case .desktop = target { return false } else { return true } }

    private var canSend: Bool { !needsName || !name.isBlank }

    private func title(_ trip: Trip?) -> String {
        switch target {
        case .trip: return "分享給同伴"
        case .desktop: return "傳到電腦排行程"
        case .additions: return "傳給記帳人"
        case .backup: return "備份全部資料"
        }
    }

    private func explanation(_ trip: Trip?) -> String {
        let x = trip?.name ?? ""
        switch target {
        case .trip:
            return "把「\(x)」的帳目和行程做成一個檔案,傳到 LINE 群組。同伴用卡溜趴打開就能看(只能看、不能改);你之後再分享一次,他們的會自動更新。"
        case .desktop:
            return "把「\(x)」的行程做成一個檔案,傳到電腦,用卡溜趴行程桌打開就能在大螢幕上排行程;排好再傳回手機打開,就會併入。"
        case .additions:
            let n = (model.read { try Q.pendingCount($0, trip?.id ?? 0) }) ?? 0
            let y = trip?.sharedBy ?? ""
            return "把你在「\(x)」補充的 \(n) 項做成一個檔案,傳給\(y)(例如 LINE)。\(y)確認加入後再分享一次,大家的就會統一。你在補充的行程上畫的手寫便條會一起傳。"
        case .backup:
            return "把所有旅程做成一個備份檔。換手機或手機遺失時,在新手機的 設定 →「從檔案還原或匯入」打開它就能還原。"
        }
    }

    private var photoNote: String {
        switch target {
        case .trip: return "檔案會變大,LINE 傳送比較慢"
        case .additions: return "收據照片也一起傳"
        default: return "收據、回憶照片與封面"
        }
    }

    private var sendText: String {
        switch target {
        case .trip: return "分享"
        case .backup: return "傳送到…"
        default: return "傳送"
        }
    }

    // MARK: Making the file

    private func make(_ tripName: String, toFiles: Bool) {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsName { model.settings.myName = String(who.prefix(20)) }
        let archive = model.archive
        let version = "ios-" + model.appVersion // which side made the file; nothing reads it
        let photos = includePhotos
        let target = target
        let organizer = tripId.flatMap { id in (model.read { try Q.trip($0, id) } ?? nil)?.sharedBy } ?? ""
        let allTrips = model.read { try Q.allTripIds($0) } ?? []
        let mine = model.settings.myName.isBlank ? "我" : model.settings.myName
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("outgoing", isDirectory: true)
        busy = true
        Task {
            let made: Outgoing? = await Task.detached(priority: .userInitiated) {
                try? FileManager.default.removeItem(at: dir)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let safe = safeFileName(tripName)
                do {
                    switch target {
                    case .trip(let id):
                        let url = dir.appendingPathComponent("卡溜趴-\(safe).zip")
                        try archive.export(to: url, kind: TripArchive.kindTrip, tripIds: [id], includePhotos: photos, sharedBy: who, appVersion: version)
                        return Outgoing(url: url, subject: "分享「\(tripName)」", text: "卡溜趴:\(tripName)(用卡溜趴 App 打開這個檔案)", toFiles: toFiles)
                    case .desktop(let id):
                        let url = dir.appendingPathComponent("卡溜趴行程-\(safe).zip")
                        try archive.export(to: url, kind: TripArchive.kindTrip, tripIds: [id], includePhotos: false, sharedBy: mine, appVersion: version)
                        return Outgoing(url: url, subject: "卡溜趴行程:\(tripName)", text: "卡溜趴行程:\(tripName)(在電腦的卡溜趴行程桌打開)", toFiles: toFiles)
                    case .additions(let id):
                        let url = dir.appendingPathComponent("卡溜趴補充-\(safe)-\(safeFileName(who)).zip")
                        try archive.exportAdditions(to: url, tripId: id, from: who, includePhotos: photos, appVersion: version)
                        return Outgoing(url: url, subject: "傳給\(organizer)", text: "\(who) 補充「\(tripName)」(請用卡溜趴打開)", toFiles: toFiles)
                    case .backup:
                        let url = dir.appendingPathComponent("卡溜趴備份-\(fmtISODate(todayEpochDay())).zip")
                        try archive.export(to: url, kind: TripArchive.kindBackup, tripIds: allTrips, includePhotos: photos, appVersion: version)
                        return Outgoing(url: url, subject: "卡溜趴備份", text: "卡溜趴備份檔", toFiles: toFiles)
                    }
                } catch {
                    return nil
                }
            }.value
            busy = false
            if let made {
                outgoing = made
            } else {
                switch target {
                case .trip: model.show("分享失敗")
                case .desktop: model.show("產生檔案失敗")
                case .additions: model.show("傳送失敗")
                case .backup: model.show("備份失敗")
                }
            }
        }
    }

    private func finished() {
        if target == .backup {
            model.settings.lastBackupDay = todayEpochDay()
            model.show("已備份")
        }
    }
}

/// The system share sheet (LINE, AirDrop, Mail, 儲存到檔案…).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let subject: String
    let onDone: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let c = UIActivityViewController(activityItems: items, applicationActivities: nil)
        c.setValue(subject, forKey: "subject")
        c.completionWithItemsHandler = { _, completed, _, _ in onDone(completed) }
        return c
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 「存到手機」: pick where in Files to keep a copy.
private struct ExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onDone: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let c = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDone: (Bool) -> Void
        init(_ onDone: @escaping (Bool) -> Void) { self.onDone = onDone }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onDone(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onDone(false) }
    }
}

/// 「X 結束了 — 備份一下」 on the trip list, for the most recently finished trip not yet backed up.
struct BackupReminderCard: View {
    @Environment(AppModel.self) private var model
    let trip: TripSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(symbol: "externaldrive.badge.checkmark", color: Palette.category(6), size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("「\(trip.name)」結束了").appFont(size: 16, weight: .semibold)
                    Text("備份一下,換手機或手機遺失都不怕").appFont(size: 13).foregroundStyle(Palette.onSurfaceVariant)
                }
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("稍後") { model.settings.reminderDismissedDay = todayEpochDay() }
                    .appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant).frame(minWidth: 60, minHeight: 44)
                Button { model.sharing = .backup } label: {
                    Text("備份").appFont(size: 15, weight: .semibold).foregroundStyle(Palette.onPrimary)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(Palette.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Palette.onBackground)
        .ledgerCard(padding: 14)
    }
}
