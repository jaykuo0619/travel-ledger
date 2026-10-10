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
    var editing: EditTarget?
    /// A file waiting to be imported (opened from LINE / Files, or picked in 設定).
    var incoming: URL?
    var toast: String?

    init(db: LedgerDatabase, files: FileStore, settings: AppSettings) {
        self.db = db
        self.files = files
        self.archive = TripArchive(database: db, files: files)
        self.settings = settings
    }

    static func live() -> AppModel {
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

    func show(_ message: String) { withAnimation { toast = message } }

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

    // MARK: Trips

    func deleteTrip(_ id: Int64) {
        var paths: [String] = []
        if write({ paths = try Q.deleteTrip($0, id) }) { files.delete(paths) }
    }

    // MARK: Files coming in

    /// A file opened with the app: copy it somewhere we own, then the import screen takes over.
    func receive(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("incoming", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let copy = dir.appendingPathComponent("import.zip")
            try FileManager.default.copyItem(at: url, to: copy)
            // Files opened from other apps land in Documents/Inbox; we keep our own copy only.
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
            incoming = copy
        } catch {
            show("無法開啟這個檔案")
        }
    }

    /// After an import: say what happened, and open the trip when exactly one was written.
    func finishImport(_ result: TripArchive.Result) {
        if let file = incoming { try? FileManager.default.removeItem(at: file) }
        incoming = nil
        switch result {
        case .failed(let message):
            show(message)
        case let .imported(kind, tripIds, updated):
            changed()
            let message: String
            switch kind {
            case TripArchive.kindPlans: message = "已併入電腦排的行程"
            case TripArchive.kindAdditions: message = updated > 0 ? "已加入 \(updated) 項,記得再分享一次給大家" : "這些項目之前已經加入過了"
            case TripArchive.kindTrip: message = updated > 0 ? "已更新同伴分享的旅程" : "已匯入,這趟旅程只能看、不能改"
            default: message = "已還原 \(tripIds.count) 個旅程"
            }
            show(message)
            path = NavigationPath()
            if tripIds.count == 1 { path.append(Route.trip(tripIds[0])) }
        }
    }

    func cancelImport() {
        if let file = incoming { try? FileManager.default.removeItem(at: file) }
        incoming = nil
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
        d.set(myName, forKey: "my_name")
        d.set(NSNumber(value: lastBackupDay), forKey: "last_backup_day")
        d.set(NSNumber(value: reminderDismissedDay), forKey: "reminder_dismissed_day")
        d.set(keypadKeyHeight, forKey: "keypad_key_height")
    }
}
