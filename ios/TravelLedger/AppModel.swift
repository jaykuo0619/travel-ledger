import Foundation
import LedgerCore
import Observation
import SwiftUI

/// Which trip the editor sheet is open for (nil id = a new trip).
struct EditTarget: Identifiable, Hashable {
    let tripId: Int64?
    var id: String { tripId.map(String.init) ?? "new" }
}

/// App-wide state: the database, the photo folder, settings and navigation.
/// Screens read from the database whenever [revision] changes; every write goes through here and bumps it.
@MainActor
@Observable
final class AppModel {
    let db: LedgerDatabase
    let files: FileStore
    let archive: TripArchive

    /// Bumped after every change so screens reload.
    private(set) var revision = 0
    var settings: AppSettings { didSet { settings.save() } }
    var path = NavigationPath()
    /// True on an iPad at full width: trips sit in a sidebar and the open trip is [selectedTrip].
    var wide = false
    var selectedTrip: Int64?
    /// Settings as a sheet (wide layout only; on a phone it is pushed).
    var showSettings = false
    var editing: EditTarget?
    /// The plan item editor and the day note editor (sheets).
    var planEditing: PlanEditTarget?
    var dayNoteEditing: DayNoteTarget?
    /// 記一筆 / editing an expense (a sheet).
    var expenseEditing: ExpenseEditTarget?
    /// Sharing a trip, sending additions, or backing up (a sheet).
    var sharing: ShareTarget?
    /// Some sheet of ours is up: another one (an import, a shortcut) has to wait.
    var sheetOpen: Bool {
        editing != nil || showSettings || planEditing != nil || dayNoteEditing != nil || expenseEditing != nil || sharing != nil
            || pasting != nil || splitting != nil
    }
    /// A file waiting to be imported (opened from LINE / Files, or picked in 設定).
    var incoming: URL?
    /// The file the user picked in 設定 for that import; deleted after a successful import if they want that.
    private var pickedOriginal: URL?
    var toast: String?
    /// A button on the current toast (復原), and what it does.
    var toastAction: (label: String, run: () -> Void)?
    /// Pasting several places, and splitting a note into plan items (sheets).
    var pasting: PasteTarget?
    var splitting: SplitTarget?

    init(db: LedgerDatabase, files: FileStore, settings: AppSettings) {
        self.db = db
        self.files = files
        self.archive = TripArchive(database: db, files: files)
        self.settings = settings
    }

    /// The one model of the running app (the screens, and Siri / Shortcuts actions, all use it).
    static let shared = live()

    private static func live() -> AppModel {
        let files = FileStore.appDefault()
        let base = files.root.deletingLastPathComponent()
        do {
            let db = try LedgerDatabase(path: base.appendingPathComponent("ledger.sqlite").path)
            return AppModel(db: db, files: files, settings: .load())
        } catch {
            fatalError("無法開啟資料庫:\(error)")
        }
    }

    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    func changed() { revision += 1 }

    func show(_ message: String) {
        toastAction = nil
        withAnimation { toast = message }
    }

    /// A message with a button; it stays about ten seconds.
    func show(_ message: String, action: String, _ run: @escaping () -> Void) {
        toastAction = (action, run)
        withAnimation { toast = message }
    }

    /// Reads from the database; nil if something went wrong.
    func read<T>(_ block: (Database) throws -> T) -> T? {
        _ = revision // screens that read through here reload on change
        do { return try db.read(block) } catch {
            print("read failed: \(error)")
            return nil
        }
    }

    /// Writes to the database and refreshes the screens; false if it failed.
    @discardableResult
    func write(_ block: (Database) throws -> Void) -> Bool {
        do {
            try db.write(block)
            changed()
            return true
        } catch {
            print("write failed: \(error)")
            return false
        }
    }

    func tripToOpenAtLaunch() -> Int64? {
        guard let trips = read({ try Q.trips($0) }) else { return nil }
        return LedgerCore.tripToOpenAtLaunch(trips, today: todayEpochDay())
    }

    // MARK: Reference exchange rates

    /// The last rates fetched (kept between launches), for prefilling a rate; nil until the first fetch.
    private(set) var referenceRates: ReferenceRates? = {
        UserDefaults.standard.data(forKey: "reference_rates").flatMap { try? JSONDecoder().decode(ReferenceRates.self, from: $0) }
    }()
    private var fetchingRates = false

    /// A rate to prefill for [currency] (the user can always change it); nil when the setting is off or none is known.
    func suggestedRate(_ currency: String) -> String? {
        settings.autoRates ? referenceRates?.suggestion(currency) : nil
    }

    /// Fetches today's reference rates when the setting is on and the saved ones are more than a day old.
    /// The request names no trip, no amounts and nothing about the user; offline, the saved rates keep working.
    func refreshReferenceRates() {
        guard settings.autoRates, !fetchingRates, referenceRates?.isStale() ?? true,
              let url = URL(string: "https://open.er-api.com/v6/latest/TWD") else { return }
        fetchingRates = true
        Task {
            defer { fetchingRates = false }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.httpShouldHandleCookies = false
            guard let (data, _) = try? await URLSession.shared.data(for: request), let rates = ReferenceRates.parse(data) else { return }
            referenceRates = rates
            if let saved = try? JSONEncoder().encode(rates) { UserDefaults.standard.set(saved, forKey: "reference_rates") }
        }
    }

    // MARK: Navigation

    /// Opens a trip: beside the sidebar on an iPad, pushed on a phone.
    func openTrip(_ id: Int64) {
        selectedTrip = id
        path = NavigationPath()
        if !wide { path.append(Route.trip(id)) }
    }

    /// Back to all trips (the list on a phone, the overview on an iPad).
    func closeTrip() {
        selectedTrip = nil
        path = NavigationPath()
    }

    func openSettings() {
        if wide { showSettings = true } else { path.append(Route.settings) }
    }

    /// The window changed between phone-width and iPad-width: keep the same trip open.
    func layoutChanged(wide: Bool) {
        guard wide != self.wide else { return }
        self.wide = wide
        showSettings = false
        path = NavigationPath()
        if !wide, let id = selectedTrip { path.append(Route.trip(id)) }
    }

    // MARK: Trips

    func deleteTrip(_ id: Int64) {
        var paths: [String] = []
        if write({ paths = try Q.deleteTrip($0, id) }) { files.delete(paths) }
    }

    // MARK: Files coming in

    /// A file opened with the app: copy it somewhere we own, then the import screen takes over.
    /// [picked]: the user chose it in 設定 →「從檔案還原或匯入」 (the only files 匯入後刪除原檔 applies to).
    func receive(_ url: URL, picked: Bool = false) {
        pickedOriginal = nil
        // A file that arrives while another is waiting replaces it; each has its own copy, so an import that
        // is already running keeps the file it started with.
        let previous = incoming
        Task {
            // Off the main thread: a backup with photos can be large.
            let copy: URL? = await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("incoming", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let copy = dir.appendingPathComponent(UUID().uuidString + ".zip")
                    try FileManager.default.copyItem(at: url, to: copy)
                    // Files opened from other apps land in Documents/Inbox; we keep our own copy only.
                    if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
                    return copy
                } catch {
                    return nil
                }
            }.value
            guard let copy else {
                show("無法開啟這個檔案")
                return
            }
            if let previous { try? FileManager.default.removeItem(at: previous) }
            incoming = copy
            if picked { pickedOriginal = url }
        }
    }

    /// After an import: say what happened, and open the trip when exactly one was written.
    func finishImport(_ result: TripArchive.Result) {
        if let file = incoming { try? FileManager.default.removeItem(at: file) }
        incoming = nil
        let original = pickedOriginal
        pickedOriginal = nil
        switch result {
        case .failed(let message):
            show(message)
        case let .imported(kind, tripIds, updated):
            changed()
            // Only after the import went through; a cancelled or failed import leaves the file alone.
            // A backup is never deleted: it may be the only copy.
            if settings.deleteImportedFile, kind != TripArchive.kindBackup, let original { Self.deleteOriginal(original) }
            let message: String
            switch kind {
            case TripArchive.kindPlans: message = "已併入電腦排的行程"
            case TripArchive.kindAdditions: message = updated > 0 ? "已加入 \(updated) 項,記得再分享一次給大家" : "這些項目之前已經加入過了"
            case TripArchive.kindTrip: message = updated > 0 ? "已更新同伴分享的旅程" : "已匯入,這趟旅程只能看、不能改"
            default: message = "已還原 \(tripIds.count) 個旅程"
            }
            show(message)
            if tripIds.count == 1 { openTrip(tripIds[0]) } else { closeTrip() }
        }
    }

    func cancelImport() {
        if let file = incoming { try? FileManager.default.removeItem(at: file) }
        incoming = nil
        pickedOriginal = nil
    }

    /// Removes a file the user picked in Files (it may live in another app's storage or in iCloud Drive).
    private static func deleteOriginal(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var failure: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &failure) { target in
            do { try FileManager.default.removeItem(at: target) } catch { print("delete original failed: \(error)") }
        }
        if let failure { print("delete original failed: \(failure)") }
    }
}

// MARK: - Settings (ui/Theme.kt AppSettings)

enum ThemeMode: String, CaseIterable {
    case system, light, dark
    var label: String { self == .system ? "跟隨系統" : self == .light ? "淺色" : "深色" }
    var colorScheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
}

/// Text size on top of the system setting. Android multiplies by 1.12 / 1.25; iOS steps the Dynamic Type size up.
enum FontScale: String, CaseIterable {
    case standard, large, xlarge
    var label: String { self == .standard ? "標準" : self == .large ? "大" : "特大" }
    var sample: CGFloat { self == .standard ? 16 : self == .large ? 20 : 24 }
    /// Multiplied on top of the system text size (ui/Theme.kt FontSize.scale).
    var factor: CGFloat { self == .standard ? 1 : self == .large ? 1.12 : 1.25 }
}

struct AppSettings: Equatable {
    var theme = ThemeMode.system
    var fontSize = FontScale.standard
    /// Copy "memory" photos to the photo library automatically.
    var saveMemoriesToGallery = true
    /// Prefill exchange rates from the network (once a day); off = nothing is ever fetched.
    var autoRates = true
    /// Delete the .zip picked in 設定 →「從檔案還原或匯入」 once it has been imported.
    var deleteImportedFile = true
    /// Shown on trips shared with companions.
    var myName = ""
    /// Epoch day of the last backup (-1: never).
    var lastBackupDay: Int64 = -1
    /// Epoch day the backup reminder was last put off.
    var reminderDismissedDay: Int64 = -1
    /// Calculator key height (40…80).
    var keypadKeyHeight: Double = 52

    static func load(_ d: UserDefaults = .standard) -> AppSettings {
        var s = AppSettings()
        s.theme = d.string(forKey: "theme_mode").flatMap(ThemeMode.init(rawValue:)) ?? .system
        s.fontSize = d.string(forKey: "font_size").flatMap(FontScale.init(rawValue:)) ?? .standard
        s.saveMemoriesToGallery = d.object(forKey: "save_memories") as? Bool ?? true
        s.autoRates = d.object(forKey: "auto_rates") as? Bool ?? true
        s.deleteImportedFile = d.object(forKey: "delete_imported_file") as? Bool ?? true
        s.myName = d.string(forKey: "my_name") ?? ""
        s.lastBackupDay = (d.object(forKey: "last_backup_day") as? NSNumber)?.int64Value ?? -1
        s.reminderDismissedDay = (d.object(forKey: "reminder_dismissed_day") as? NSNumber)?.int64Value ?? -1
        s.keypadKeyHeight = min(max(d.object(forKey: "keypad_key_height") as? Double ?? 52, 40), 80)
        return s
    }

    func save(_ d: UserDefaults = .standard) {
        d.set(theme.rawValue, forKey: "theme_mode")
        d.set(fontSize.rawValue, forKey: "font_size")
        d.set(saveMemoriesToGallery, forKey: "save_memories")
        d.set(autoRates, forKey: "auto_rates")
        d.set(deleteImportedFile, forKey: "delete_imported_file")
        d.set(myName, forKey: "my_name")
        d.set(NSNumber(value: lastBackupDay), forKey: "last_backup_day")
        d.set(NSNumber(value: reminderDismissedDay), forKey: "reminder_dismissed_day")
        d.set(keypadKeyHeight, forKey: "keypad_key_height")
    }
}
