import Foundation
import GRDB
import ZIPFoundation

/// The .zip file shared with the Android app and the desktop planner (docs/IOS_PORT.md §4).
/// A line-by-line port of Android's backup/TripArchive.kt: same rules, same messages.
///
/// Layout: manifest.json (what it is), data.json (trips and the category/payment names they use),
/// files/… (photos and covers). Rows refer to each other by position or uuid, never by database id.
public final class TripArchive: @unchecked Sendable {
    public static let format = "travelledger"
    public static let version = 1
    public static let kindTrip = "trip"
    public static let kindBackup = "backup"
    /// A companion's suggestions for a shared trip, sent back to its organizer.
    public static let kindAdditions = "additions"
    /// Plans made on the desktop planner (卡溜趴行程桌), merged into the phone's own trip.
    public static let kindPlans = "plans"

    public struct TripInfo: Equatable, Sendable {
        public let uuid: String
        public let name: String
        public let startDate: Int64
        public let endDate: Int64
        public let expenseCount: Int
        public let totalHome: Double
    }

    /// What the file holds, read before asking the user to confirm.
    public struct Summary: Equatable, Sendable {
        public let kind: String
        public let sharedBy: String?
        public let exportedAt: Int64
        public let trips: [TripInfo]
        public let photoCount: Int
    }

    public enum Result: Equatable, Sendable {
        /// [tripIds] are the local ids of the trips written, in file order.
        case imported(kind: String, tripIds: [Int64], updated: Int)
        case failed(String)
    }

    /// A problem with a message for the user.
    public struct BadArchive: Error, Equatable {
        public let message: String
        public init(_ message: String) { self.message = message }
    }

    let database: LedgerDatabase
    let files: FileStore

    public init(database: LedgerDatabase, files: FileStore) {
        self.database = database
        self.files = files
    }

    // MARK: - Export

    /// Writes [tripIds] to [url]. For a shared trip, [sharedBy] is the sender's name shown on the companion's
    /// copy; a trip that was itself shared with us keeps its original sender. Returns the number of trips written.
    @discardableResult
    public func export(
        to url: URL, kind: String, tripIds: [Int64], includePhotos: Bool, sharedBy: String? = nil,
        appVersion: String = "", now: Int64 = nowMillis()
    ) throws -> Int {
        var attached: [(String, String)] = []
        // Plan pictures (screenshots) always travel; expense photos and covers only when asked for.
        func attach(_ path: String?, _ folder: String, always: Bool = false) -> String? {
            guard includePhotos || always, let path, files.exists(path) else { return nil }
            let name = "files/\(folder)/\(attached.count)-\((path as NSString).lastPathComponent)"
            attached.append((name, path))
            return name
        }

        let (data, manifestTrips): (JSONObject, [JSON]) = try database.read { db in
            let categories = try Q.categories(db)
            let methods = try Q.paymentMethods(db)
            var trips: [JSON] = []
            for id in tripIds {
                guard let trip = try Q.trip(db, id) else { continue }
                let members = try Q.members(db, id)
                var memberIndex: [Int64: Int] = [:]
                for (i, m) in members.enumerated() { memberIndex[m.id!] = i }
                // A share carries only the organizer's book; a backup also keeps my own unsent additions.
                let plans = try Q.plans(db, id).filter { kind != Self.kindTrip || !$0.pending }
                var planIndex: [Int64: Int] = [:]
                for (i, p) in plans.enumerated() { planIndex[p.id!] = i }
                let expenses = try Q.expenses(db, id).filter { kind != Self.kindTrip || !$0.pending }

                var t = JSONObject()
                t["uuid"] = .string(trip.uuid.trimmingCharacters(in: .whitespaces).isEmpty ? newUUID() : trip.uuid)
                t["name"] = .string(trip.name)
                t["startDate"] = .int(trip.startDate)
                t["endDate"] = .int(trip.endDate)
                t["homeCurrency"] = .string(trip.homeCurrency)
                t["budget"] = trip.budget.map(JSON.double)
                t["splitEnabled"] = .bool(trip.splitEnabled)
                t["createdAt"] = .int(trip.createdAt)
                t["coverTheme"] = trip.coverTheme.map(JSON.string)
                t["navApp"] = trip.navApp.map(JSON.string)
                t["cover"] = attach(trip.coverPath, "covers").map(JSON.string)
                // A backup remembers which trips were someone else's; a share names the sender.
                if kind == Self.kindTrip {
                    t["sharedBy"] = (trip.sharedBy ?? sharedBy).map(JSON.string)
                    t["sharedAt"] = .int((trip.sharedBy != nil ? trip.sharedAt : nil) ?? now)
                } else {
                    t["sharedBy"] = trip.sharedBy.map(JSON.string)
                    t["sharedAt"] = trip.sharedAt.map(JSON.int)
                }
                t["members"] = .array(members.map { .string($0.name) })
                t["rates"] = .array(try Q.rates(db, id).map { r in
                    .object(JSONObject([("currency", .string(r.currency)), ("rate", .double(r.rate)),
                                        ("updatedAt", .int(r.updatedAt)), ("source", .string(r.source))]))
                })
                t["plans"] = .array(try plans.map { .object(try Self.planJSON(db, $0, categories, attach)) })
                t["dayNotes"] = .array(try Q.dayNotes(db, id).map { n in
                    .object(JSONObject([("day", .int(n.day)), ("text", .string(n.text)), ("updatedAt", .int(n.updatedAt))]))
                })
                t["expenses"] = .array(try expenses.map { e in
                    var o = try Self.expenseJSON(db, e, categories, methods, plans) { attach($0, $1) }
                    o["payer"] = e.payerId.flatMap { memberIndex[$0] }.map(JSON.int)
                    o["plan"] = e.planItemId.flatMap { planIndex[$0] }.map(JSON.int)
                    return .object(o)
                })
                trips.append(.object(t))
            }
            var data = JSONObject()
            data["categories"] = .array(categories.map(Self.categoryJSON))
            data["payments"] = .array(methods.map(Self.paymentJSON))
            data["trips"] = .array(trips)
            let manifestTrips: [JSON] = trips.compactMap(\.objectValue).map { t in
                let ex = t.objects("expenses") ?? []
                return .object(JSONObject([
                    ("uuid", t["uuid"]), ("name", t["name"]), ("startDate", t["startDate"]), ("endDate", t["endDate"]),
                    ("expenseCount", .int(ex.count)), ("totalHome", .double(ex.reduce(0) { $0 + $1.optDouble("homeAmount") })),
                ]))
            }
            return (data, manifestTrips)
        }

        let manifest = JSONObject([
            ("format", .string(Self.format)),
            ("version", .int(Self.version)),
            ("kind", .string(kind)),
            ("exportedAt", .int(now)),
            ("sharedBy", kind == Self.kindTrip ? sharedBy.map(JSON.string) : nil),
            ("appVersion", .string(appVersion)),
            ("photoCount", .int(attached.count)),
            ("trips", .array(manifestTrips)),
        ])
        try writeZip(to: url, manifest: manifest, data: data, attached: attached)
        return manifestTrips.count
    }

    /// A companion's additions to a shared trip, for its organizer: kind "additions". Returns how many items.
    @discardableResult
    public func exportAdditions(
        to url: URL, tripId: Int64, from: String, includePhotos: Bool, appVersion: String = "", now: Int64 = nowMillis()
    ) throws -> Int {
        var attached: [(String, String)] = []
        func attach(_ path: String?, _ folder: String, always: Bool = false) -> String? {
            guard includePhotos || always, let path, files.exists(path) else { return nil }
            let name = "files/\(folder)/\(attached.count)-\((path as NSString).lastPathComponent)"
            attached.append((name, path))
            return name
        }
        let result: (JSONObject, JSONObject, Int)? = try database.read { db in
            guard let trip = try Q.trip(db, tripId) else { return nil }
            let categories = try Q.categories(db)
            let methods = try Q.paymentMethods(db)
            let allPlans = try Q.plans(db, tripId)
            let plans = allPlans.filter(\.pending)
            let expenses = try Q.expenses(db, tripId).filter(\.pending)
            var data = JSONObject()
            data["tripUuid"] = .string(trip.uuid)
            data["categories"] = .array(categories.map(Self.categoryJSON))
            data["payments"] = .array(methods.map(Self.paymentJSON))
            data["plans"] = .array(try plans.map { p in
                var o = try Self.planJSON(db, p, categories, attach)
                o["addedBy"] = .string(from)
                o["pending"] = nil
                return .object(o)
            })
            data["expenses"] = .array(try expenses.map { e in
                var o = try Self.expenseJSON(db, e, categories, methods, allPlans) { attach($0, $1) }
                o["addedBy"] = .string(from)
                o["pending"] = nil
                return .object(o)
            })
            let manifest = JSONObject([
                ("format", .string(Self.format)),
                ("version", .int(Self.version)),
                ("kind", .string(Self.kindAdditions)),
                ("exportedAt", .int(now)),
                ("sharedBy", .string(from)),
                ("appVersion", .string(appVersion)),
                ("photoCount", .int(0)), // filled in below
                ("trips", .array([.object(JSONObject([
                    ("uuid", .string(trip.uuid)), ("name", .string(trip.name)),
                    ("startDate", .int(trip.startDate)), ("endDate", .int(trip.endDate)),
                    ("expenseCount", .int(expenses.count)), ("totalHome", .double(expenses.reduce(0) { $0 + $1.homeAmount })),
                ]))])),
            ])
            return (manifest, data, plans.count + expenses.count)
        }
        guard var (manifest, data, count) = result else { return 0 }
        manifest["photoCount"] = .int(attached.count)
        _ = data
        try writeZip(to: url, manifest: manifest, data: data, attached: attached)
        return count
    }

    private static func categoryJSON(_ c: Category) -> JSON {
        .object(JSONObject([("name", .string(c.name)), ("sortOrder", .int(c.sortOrder)), ("icon", .string(c.icon)), ("color", .int(c.color))]))
    }

    private static func paymentJSON(_ m: PaymentMethod) -> JSON {
        .object(JSONObject([("name", .string(m.name)), ("sortOrder", .int(m.sortOrder))]))
    }

    private static func planJSON(
        _ db: Database, _ p: PlanItem, _ categories: [Category], _ attach: (String?, String, Bool) -> String?
    ) throws -> JSONObject {
        var o = JSONObject()
        o["photos"] = .array(try Q.planPhotos(db, planId: p.id!).compactMap { ph in
            attach(ph.path, "plans", true).map { name in
                .object(JSONObject([("file", .string(name)), ("width", .int(ph.width)), ("height", .int(ph.height)), ("createdAt", .int(ph.createdAt))]))
            }
        })
        o["uuid"] = .string(p.uuid)
        o["title"] = .string(p.title)
        o["category"] = categories.first { $0.id == p.categoryId }.map { .string($0.name) }
        o["date"] = p.date.map(JSON.int)
        o["minuteOfDay"] = p.minuteOfDay.map(JSON.int)
        o["status"] = .string(p.status)
        o["reservation"] = .string(p.reservation)
        o["reservationNote"] = .string(p.reservationNote)
        o["location"] = .string(p.location)
        o["estCost"] = p.estCost.map(JSON.double)
        o["note"] = .string(p.note)
        o["createdAt"] = .int(p.createdAt)
        o["addedBy"] = p.addedBy.map(JSON.string)
        if p.pending { o["pending"] = .bool(true) }
        return o
    }

    private static func expenseJSON(
        _ db: Database, _ e: Expense, _ categories: [Category], _ methods: [PaymentMethod], _ plans: [PlanItem],
        _ attach: (String?, String) -> String?
    ) throws -> JSONObject {
        var o = JSONObject()
        o["uuid"] = .string(e.uuid)
        o["date"] = .int(e.date)
        o["minuteOfDay"] = e.minuteOfDay.map(JSON.int)
        o["title"] = .string(e.title)
        o["amount"] = .double(e.amount)
        o["currency"] = .string(e.currency)
        o["rate"] = .double(e.rate)
        o["homeAmount"] = .double(e.homeAmount)
        o["category"] = categories.first { $0.id == e.categoryId }.map { .string($0.name) }
        o["payment"] = methods.first { $0.id == e.paymentMethodId }.map { .string($0.name) }
        o["note"] = .string(e.note)
        o["ocrText"] = .string(e.ocrText)
        o["createdAt"] = .int(e.createdAt)
        o["planUuid"] = plans.first { $0.id == e.planItemId }.map { .string($0.uuid) }
        o["addedBy"] = e.addedBy.map(JSON.string)
        if e.pending { o["pending"] = .bool(true) }
        o["photos"] = .array(try Q.photos(db, expenseId: e.id!).compactMap { ph in
            attach(ph.path, ph.type == PhotoType.receipt ? "receipts" : "memories").map { name in
                .object(JSONObject([("file", .string(name)), ("type", .string(ph.type)), ("width", .int(ph.width)),
                                    ("height", .int(ph.height)), ("createdAt", .int(ph.createdAt))]))
            }
        })
        return o
    }

    private func writeZip(to url: URL, manifest: JSONObject, data: JSONObject, attached: [(String, String)]) throws {
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ name: String, _ bytes: Data) throws {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: .deflate) { position, size in
                bytes.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        try add("manifest.json", JSON.object(manifest).data(indent: 1))
        try add("data.json", JSON.object(data).data())
        for (name, path) in attached {
            try add(name, try Data(contentsOf: files.url(path)))
        }
    }

    // MARK: - Reading

    private struct Zip {
        let archive: Archive

        init(_ url: URL) throws {
            do { archive = try Archive(url: url, accessMode: .read) } catch { throw BadArchive("這不是卡溜趴的檔案") }
        }

        func data(_ name: String) throws -> Data? {
            guard let entry = archive[name], entry.type == .file else { return nil }
            var out = Data()
            _ = try archive.extract(entry, skipCRC32: false) { out.append($0) }
            return out
        }

        func json(_ name: String) throws -> JSONObject {
            guard let d = try data(name) else { throw BadArchive("這不是卡溜趴的檔案") }
            guard let o = try JSON.parse(d).objectValue else { throw BadArchive("這不是卡溜趴的檔案") }
            return o
        }

        func manifest() throws -> JSONObject {
            let m = try json("manifest.json")
            if m.optString("format") != TripArchive.format { throw BadArchive("這不是卡溜趴的檔案") }
            if m.optInt("version") > TripArchive.version { throw BadArchive("這個檔案來自較新版的卡溜趴,請先更新 App") }
            return m
        }
    }

    /// Copies one photo or cover out of the zip into the app's folder; nil if it is missing or suspicious.
    private func copyEntry(_ zip: Zip, _ name: String) throws -> String? {
        if name.contains("..") { return nil }
        guard let bytes = try zip.data(name) else { return nil }
        let folder: String
        if name.hasPrefix("files/covers/") { folder = "covers" }
        else if name.hasPrefix("files/receipts/") { folder = "photos/receipts" }
        else if name.hasPrefix("files/plans/") { folder = "photos/plans" }
        else { folder = "photos/memories" }
        return try files.write(bytes, folder: folder)
    }

    /// Reads only the manifest, for the confirmation dialog.
    public static func readSummary(_ url: URL) throws -> Summary {
        do {
            let m = try Zip(url).manifest()
            let trips = try (m.objects("trips") ?? []).map { t in
                TripInfo(uuid: try t.reqString("uuid"), name: try t.reqString("name"), startDate: try t.reqInt64("startDate"),
                         endDate: try t.reqInt64("endDate"), expenseCount: t.optInt("expenseCount"), totalHome: t.optDouble("totalHome"))
            }
            return Summary(kind: m.optString("kind", kindBackup), sharedBy: m.string("sharedBy"), exportedAt: m.optInt64("exportedAt"),
                           trips: trips, photoCount: m.optInt("photoCount"))
        } catch let e as BadArchive {
            throw e
        } catch {
            throw BadArchive("這不是卡溜趴的檔案")
        }
    }

    /// Uuids in [summary] that this phone already has.
    public func existing(_ summary: Summary) throws -> Set<String> {
        try database.read { db in Set(try summary.trips.compactMap { try Q.tripByUuid(db, $0.uuid)?.uuid }) }
    }

    // MARK: - Import (trip / backup)

    /// Imports a shared trip (becomes a read-only copy; sharing again replaces it, matched by uuid; our own trip
    /// coming back is refused) or a backup (each trip replaces the one with the same uuid, others are added).
    public func importFile(_ url: URL) -> Result {
        do {
            return try importZip(try Zip(url))
        } catch let e as BadArchive {
            return .failed(e.message)
        } catch {
            return .failed("檔案損壞,無法匯入")
        }
    }

    private func importZip(_ zip: Zip) throws -> Result {
        let manifest = try zip.manifest()
        let kind = manifest.optString("kind", Self.kindBackup)
        if kind == Self.kindAdditions { throw BadArchive("這是同伴的補充檔,請用審核畫面加入") }
        if kind == Self.kindPlans { throw BadArchive("這是電腦行程檔,請用併入行程畫面") }
        let data = try zip.json("data.json")
        let trips = try data.reqObjects("trips")

        if kind == Self.kindTrip {
            for t in trips {
                if let existing = try database.read({ try Q.tripByUuid($0, try t.reqString("uuid")) }), !existing.readOnly {
                    return .failed("「\(existing.name)」是你自己記的旅程,不需要匯入")
                }
            }
        }

        // Copy files first (outside the transaction); remember them so a failure leaves nothing behind.
        var copied: [String: String] = [:]
        func fileFor(_ name: String?) throws {
            guard let name, copied[name] == nil else { return }
            if let path = try copyEntry(zip, name) { copied[name] = path }
        }

        var oldFiles: [String] = []
        var ids: [Int64] = []
        var updated = 0
        do {
            for t in trips {
                try fileFor(t.string("cover"))
                for e in try t.reqObjects("expenses") {
                    for ph in e.objects("photos") ?? [] { try fileFor(try ph.reqString("file")) }
                }
                for p in try t.reqObjects("plans") {
                    for ph in p.objects("photos") ?? [] { try fileFor(try ph.reqString("file")) }
                }
            }

            try database.write { db in
                let categoryIds = try Self.mergeCategories(db, data.objects("categories"))
                let paymentIds = try Self.mergePayments(db, data.objects("payments"))
                let fallbackSharedBy = manifest.string("sharedBy").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "同伴"
                for t in trips {
                    let uuid = try t.reqString("uuid")
                    let existing = try Q.tripByUuid(db, uuid)
                    let sharedBy = kind == Self.kindTrip ? (t.string("sharedBy") ?? fallbackSharedBy) : t.string("sharedBy")
                    var trip = Trip(
                        id: existing?.id,
                        name: try t.reqString("name"),
                        startDate: try t.reqInt64("startDate"),
                        endDate: try t.reqInt64("endDate"),
                        homeCurrency: t.optString("homeCurrency", "TWD"),
                        budget: t.double("budget"),
                        splitEnabled: t.optBool("splitEnabled"),
                        createdAt: t.optInt64("createdAt", nowMillis()),
                        coverPath: t.string("cover").flatMap { copied[$0] },
                        coverTheme: t.string("coverTheme"),
                        uuid: uuid,
                        sharedBy: sharedBy,
                        sharedAt: sharedBy != nil ? (t.int64("sharedAt") ?? manifest.optInt64("exportedAt")) : nil,
                        navApp: t.string("navApp")
                    )
                    // My unsent additions on a shared copy survive an update: remember which plan each belongs to.
                    var myLinks: [Int64: String?] = [:]
                    let tripId: Int64
                    if let existing, let existingId = existing.id {
                        if let cover = existing.coverPath { oldFiles.append(cover) }
                        if kind == Self.kindTrip {
                            oldFiles += try Q.photoPaths(db, tripId: existingId, officialOnly: true)
                            oldFiles += try Q.planPhotoPaths(db, tripId: existingId, officialOnly: true)
                            var planUuids: [Int64: String] = [:]
                            for p in try Q.plans(db, existingId) { planUuids[p.id!] = p.uuid }
                            for e in try Q.expenses(db, existingId) where e.pending && e.planItemId != nil {
                                myLinks[e.id!] = planUuids[e.planItemId!]
                            }
                            try Q.clearContents(db, existingId)
                        } else {
                            oldFiles += try Q.photoPaths(db, tripId: existingId, officialOnly: false)
                            oldFiles += try Q.planPhotoPaths(db, tripId: existingId, officialOnly: false)
                            try Q.clearAll(db, existingId)
                        }
                        try trip.update(db)
                        updated += 1
                        tripId = existingId
                    } else {
                        try trip.insert(db)
                        tripId = trip.id!
                    }
                    ids.append(tripId)
                    try Self.writeContents(db, tripId: tripId, t, categoryIds, paymentIds, copied, keepPending: kind != Self.kindTrip)
                    if existing != nil && kind == Self.kindTrip {
                        oldFiles += try Self.settleMyAdditions(db, tripId: tripId, t, myLinks)
                    }
                }
            }
        } catch {
            files.delete(Array(copied.values))
            throw error
        }
        files.delete(oldFiles)
        return .imported(kind: kind, tripIds: ids, updated: updated)
    }

    private static func mergeCategories(_ db: Database, _ list: [JSONObject]?) throws -> [String: Int64] {
        var have: [String: Int64] = [:]
        var maxOrder = -1
        for c in try Q.categories(db) {
            if have[c.name] == nil { have[c.name] = c.id! }
            maxOrder = max(maxOrder, c.sortOrder)
        }
        var next = maxOrder + 1
        for c in list ?? [] {
            let name = try c.reqString("name")
            if have[name] == nil {
                var cat = Category(name: name, sortOrder: next, icon: c.optString("icon"), color: c.optInt("color", -1))
                next += 1
                try cat.insert(db)
                have[name] = cat.id!
            }
        }
        return have
    }

    private static func mergePayments(_ db: Database, _ list: [JSONObject]?) throws -> [String: Int64] {
        var have: [String: Int64] = [:]
        var maxOrder = -1
        for m in try Q.paymentMethods(db) {
            if have[m.name] == nil { have[m.name] = m.id! }
            maxOrder = max(maxOrder, m.sortOrder)
        }
        var next = maxOrder + 1
        for m in list ?? [] {
            let name = try m.reqString("name")
            if have[name] == nil {
                var pm = PaymentMethod(name: name, sortOrder: next)
                next += 1
                try pm.insert(db)
                have[name] = pm.id!
            }
        }
        return have
    }

    private static func writeContents(
        _ db: Database, tripId: Int64, _ t: JSONObject,
        _ categoryIds: [String: Int64], _ paymentIds: [String: Int64], _ copied: [String: String],
        keepPending: Bool,
        /// Adding to a trip that already has plan items: expenses may point at those too.
        existingPlans: Bool = false
    ) throws {
        var planByUuid: [String: Int64] = [:]
        if existingPlans { for p in try Q.plans(db, tripId) { planByUuid[p.uuid] = p.id! } }
        for n in t.objects("dayNotes") ?? [] {
            try Q.putDayNote(db, DayNote(tripId: tripId, day: try n.reqInt64("day"), text: try n.reqString("text"), updatedAt: n.optInt64("updatedAt")))
        }
        var memberIds: [Int64] = []
        for name in try t.reqArray("members") {
            guard let n = name.stringValue else { throw JSONError.missing("members") }
            var m = Member(tripId: tripId, name: n)
            try m.insert(db)
            memberIds.append(m.id!)
        }
        for r in try t.reqObjects("rates") {
            try Q.upsertRate(db, TripCurrencyRate(tripId: tripId, currency: try r.reqString("currency"), rate: try r.reqDouble("rate"),
                                                  updatedAt: r.optInt64("updatedAt"), source: r.optString("source", "manual")))
        }
        let plans = try t.reqObjects("plans")
        var planIds: [Int64] = []
        for p in plans {
            let uuid = p.optString("uuid")
            var item = PlanItem(
                tripId: tripId,
                title: try p.reqString("title"),
                categoryId: p.string("category").flatMap { categoryIds[$0] },
                date: p.int64("date"),
                minuteOfDay: p.int("minuteOfDay"),
                status: p.optString("status", PlanStatus.todo),
                reservation: p.optString("reservation", Reservation.none),
                reservationNote: p.optString("reservationNote"),
                location: p.optString("location"),
                estCost: p.double("estCost"),
                note: p.optString("note"),
                createdAt: p.optInt64("createdAt"),
                uuid: uuid.trimmingCharacters(in: .whitespaces).isEmpty ? newUUID() : uuid,
                addedBy: p.string("addedBy"),
                pending: keepPending && p.optBool("pending")
            )
            try item.insert(db)
            for ph in p.objects("photos") ?? [] {
                guard let path = copied[try ph.reqString("file")] else { continue }
                var photo = PlanPhoto(planItemId: item.id!, path: path, width: ph.optInt("width"), height: ph.optInt("height"), createdAt: ph.optInt64("createdAt"))
                try photo.insert(db)
            }
            planIds.append(item.id!)
        }
        for (i, p) in plans.enumerated() { planByUuid[p.optString("uuid")] = planIds[i] }
        for e in try t.reqObjects("expenses") {
            let uuid = e.optString("uuid")
            let payer = e.int64("payer").flatMap { i in i >= 0 && i < memberIds.count ? memberIds[Int(i)] : nil }
            let planIndex = e.int64("plan").flatMap { i in i >= 0 && i < planIds.count ? planIds[Int(i)] : nil }
            var expense = Expense(
                tripId: tripId,
                date: try e.reqInt64("date"),
                amount: try e.reqDouble("amount"),
                currency: try e.reqString("currency"),
                rate: try e.reqDouble("rate"),
                homeAmount: try e.reqDouble("homeAmount"),
                categoryId: e.string("category").flatMap { categoryIds[$0] },
                paymentMethodId: e.string("payment").flatMap { paymentIds[$0] },
                payerId: payer,
                note: e.optString("note"),
                createdAt: e.optInt64("createdAt"),
                title: e.optString("title"),
                minuteOfDay: e.int("minuteOfDay"),
                ocrText: e.optString("ocrText"),
                planItemId: e.string("planUuid").flatMap { planByUuid[$0] } ?? planIndex,
                uuid: uuid.trimmingCharacters(in: .whitespaces).isEmpty ? newUUID() : uuid,
                addedBy: e.string("addedBy"),
                pending: keepPending && e.optBool("pending")
            )
            try expense.insert(db)
            for ph in e.objects("photos") ?? [] {
                guard let path = copied[try ph.reqString("file")] else { continue }
                var photo = Photo(expenseId: expense.id!, type: ph.optString("type", PhotoType.memory), path: path,
                                  width: ph.optInt("width"), height: ph.optInt("height"), createdAt: ph.optInt64("createdAt"))
                try photo.insert(db)
            }
        }
    }

    /// After a shared copy is refilled: my additions the organizer has taken in now arrive as official rows, so my
    /// own copies go; the rest stay and are re-linked to their plan item by uuid. Returns photo files to delete.
    private static func settleMyAdditions(_ db: Database, tripId: Int64, _ t: JSONObject, _ myLinks: [Int64: String?]) throws -> [String] {
        let officialExpenses = Set(try t.reqObjects("expenses").map { $0.optString("uuid") })
        let officialPlans = Set(try t.reqObjects("plans").map { $0.optString("uuid") })
        var gone: [String] = []
        for e in try Q.expenses(db, tripId) where e.pending && officialExpenses.contains(e.uuid) {
            gone += try Q.photos(db, expenseId: e.id!).map(\.path)
            try db.execute(sql: "DELETE FROM expense WHERE id = ?", arguments: [e.id])
        }
        for p in try Q.plans(db, tripId) where p.pending && officialPlans.contains(p.uuid) {
            gone += try Q.planPhotos(db, planId: p.id!).map(\.path)
            try db.execute(sql: "DELETE FROM plan_item WHERE id = ?", arguments: [p.id])
        }
        var planIds: [String: Int64] = [:]
        for p in try Q.plans(db, tripId) where !p.pending || !officialPlans.contains(p.uuid) { planIds[p.uuid] = p.id! }
        for (expenseId, planUuid) in myLinks {
            if try Q.expense(db, expenseId) != nil {
                try db.execute(sql: "UPDATE expense SET planItemId = ? WHERE id = ?", arguments: [planUuid.flatMap { planIds[$0] }, expenseId])
            }
        }
        return gone
    }

    /// Names of trips in a backup whose copy here has records the backup lacks: something recorded after
    /// the backup was made, or more expenses than the backup holds.
    public func newerOnPhone(_ summary: Summary) throws -> [String] {
        try database.read { db in
            try summary.trips.compactMap { t in
                guard let local = try Q.tripByUuid(db, t.uuid), let id = local.id else { return nil }
                let expenses = try Q.expenses(db, id)
                let latest = (expenses.map(\.createdAt) + (try Q.plans(db, id)).map(\.createdAt)).max() ?? 0
                return latest > summary.exportedAt || expenses.count > t.expenseCount ? local.name : nil
            }
        }
    }

    // MARK: - Additions

    /// One suggested item, as shown to the organizer for review.
    public struct AdditionItem: Equatable, Identifiable, Sendable {
        public let uuid: String
        public let isExpense: Bool
        public let title: String
        public let detail: String
        public var id: String { uuid }
    }

    public struct Additions: Equatable, Sendable {
        public let tripUuid: String
        public let tripName: String
        public let from: String
        public let items: [AdditionItem]
    }

    /// How many of my additions on [tripId] are waiting to be sent.
    public func pendingCount(_ tripId: Int64) throws -> Int { try database.read { try Q.pendingCount($0, tripId) } }

    /// The items in an additions file, for the review list.
    public static func readAdditions(_ url: URL) throws -> Additions {
        do {
            let zip = try Zip(url)
            let m = try zip.manifest()
            if m.optString("kind") != kindAdditions { throw BadArchive("這不是補充檔") }
            let data = try zip.json("data.json")
            guard let trip = try m.reqObjects("trips").first else { throw JSONError.missing("trips") }
            let items = try Self.reviewItems(plans: try data.reqObjects("plans"), expenses: try data.reqObjects("expenses"))
            return Additions(tripUuid: try data.reqString("tripUuid"), tripName: try trip.reqString("name"),
                             from: m.optString("sharedBy", "同伴"), items: items)
        } catch let e as BadArchive {
            throw e
        } catch {
            throw BadArchive("檔案損壞,無法讀取")
        }
    }

    /// Rows for the review list: plans first, then expenses.
    private static func reviewItems(plans: [JSONObject], expenses: [JSONObject]) throws -> [AdditionItem] {
        var items: [AdditionItem] = []
        for p in plans {
            let day = p.int64("date").map(fmtMonthDay) ?? "待排"
            items.append(AdditionItem(uuid: try p.reqString("uuid"), isExpense: false, title: try p.reqString("title"),
                                      detail: "行程 · \(day)" + (p.string("category").map { " · \($0)" } ?? "")))
        }
        for e in expenses {
            let day = fmtMonthDay(try e.reqInt64("date"))
            let title = e.optString("title")
            items.append(AdditionItem(
                uuid: try e.reqString("uuid"), isExpense: true,
                title: title.trimmingCharacters(in: .whitespaces).isEmpty ? (e.string("category") ?? "支出") : title,
                detail: "\(day) · \(try e.reqString("currency")) \(fmtPlain(try e.reqDouble("amount")))" + (e.string("category").map { " · \($0)" } ?? "")
            ))
        }
        return items
    }

    // MARK: - A kind=trip file of my own trip, sent back by a companion

    /// The trip in a kind=trip file that is mine on this phone (exists here and is not a read-only copy), with what
    /// the sender has and I don't.
    private func mineInFile(_ zip: Zip) throws -> (trip: Trip, json: JSONObject, from: String, plans: [JSONObject], expenses: [JSONObject], data: JSONObject)? {
        let m = try zip.manifest()
        guard m.optString("kind", Self.kindBackup) == Self.kindTrip else { return nil }
        let data = try zip.json("data.json")
        for t in try data.reqObjects("trips") {
            guard let trip = try database.read({ try Q.tripByUuid($0, try t.reqString("uuid")) }), !trip.readOnly, let id = trip.id else { continue }
            let (haveExpenses, havePlans) = try database.read { db in
                (Set(try Q.expenses(db, id).map(\.uuid)), Set(try Q.plans(db, id).map(\.uuid)))
            }
            func blank(_ s: String?) -> String? { s.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
            let from = blank(t.string("sharedBy")) ?? blank(m.string("sharedBy")) ?? "同伴"
            let plans = try (t.objects("plans") ?? []).filter { !havePlans.contains(try $0.reqString("uuid")) }
            let expenses = try (t.objects("expenses") ?? []).filter { !haveExpenses.contains(try $0.reqString("uuid")) }
            return (trip, t, from, plans, expenses, data)
        }
        return nil
    }

    /// When [url] is a shared copy of a trip I organize: the plans and expenses in it that I don't have (by uuid).
    /// Nil when the file is anything else, so the ordinary import goes on. An empty list means nothing is new.
    public func readNewItems(_ url: URL) throws -> Additions? {
        guard let found = try mineInFile(try Zip(url)) else { return nil }
        return Additions(tripUuid: found.trip.uuid, tripName: found.trip.name, from: found.from,
                         items: try Self.reviewItems(plans: found.plans, expenses: found.expenses))
    }

    /// Adds the [accepted] new items of such a file to my trip. Nothing of mine is changed: items I already have
    /// are skipped, the payer, the plan index and the pending flag are dropped, expenses find their plan by uuid.
    public func importNewItems(_ url: URL, accepted: Set<String>) -> Result {
        do {
            let zip = try Zip(url)
            guard let found = try mineInFile(zip), let tripId = found.trip.id else { throw BadArchive("檔案損壞,無法匯入") }
            func prepared(_ list: [JSONObject]) throws -> [JSONObject] {
                try list.filter { accepted.contains(try $0.reqString("uuid")) }.map { o in
                    var o = o
                    o["addedBy"] = .string(o.string("addedBy") ?? found.from)
                    o["pending"] = nil
                    o["payer"] = nil
                    o["plan"] = nil
                    return o
                }
            }
            let plans = try prepared(found.plans)
            let expenses = try prepared(found.expenses)
            var copied: [String: String] = [:]
            do {
                for item in plans + expenses {
                    for ph in item.objects("photos") ?? [] {
                        let name = try ph.reqString("file")
                        if let path = try copyEntry(zip, name) { copied[name] = path }
                    }
                }
                try database.write { db in
                    let categoryIds = try Self.mergeCategories(db, found.data.objects("categories"))
                    let paymentIds = try Self.mergePayments(db, found.data.objects("payments"))
                    let t = JSONObject([("members", .array([])), ("rates", .array([])),
                                        ("plans", .array(plans.map(JSON.object))), ("expenses", .array(expenses.map(JSON.object)))])
                    try Self.writeContents(db, tripId: tripId, t, categoryIds, paymentIds, copied, keepPending: false, existingPlans: true)
                }
            } catch {
                files.delete(Array(copied.values))
                throw error
            }
            return .imported(kind: Self.kindAdditions, tripIds: [tripId], updated: plans.count + expenses.count)
        } catch let e as BadArchive {
            return .failed(e.message)
        } catch {
            return .failed("檔案損壞,無法匯入")
        }
    }

    /// The organizer takes in the [accepted] items (by uuid) from a companion's additions file.
    /// Items already in the trip (the same file opened twice) are skipped.
    public func importAdditions(_ url: URL, accepted: Set<String>) -> Result {
        do {
            let zip = try Zip(url)
            let m = try zip.manifest()
            if m.optString("kind") != Self.kindAdditions { throw BadArchive("這不是補充檔") }
            let data = try zip.json("data.json")
            let tripUuid = try data.reqString("tripUuid")
            guard let trip = try database.read({ try Q.tripByUuid($0, tripUuid) }), let tripId = trip.id else {
                throw BadArchive("手機上沒有「\(try m.reqObjects("trips").first?.reqString("name") ?? "")」這趟旅程")
            }
            if trip.readOnly { throw BadArchive("這是給記帳人(\(trip.sharedBy ?? ""))的補充,請轉傳給他") }
            let (haveExpenses, havePlans) = try database.read { db in
                (Set(try Q.expenses(db, tripId).map(\.uuid)), Set(try Q.plans(db, tripId).map(\.uuid)))
            }
            let from = m.optString("sharedBy", "同伴")
            func prepared(_ list: [JSONObject], have: Set<String>) throws -> [JSONObject] {
                try list.filter { o in
                    let uuid = try o.reqString("uuid")
                    return accepted.contains(uuid) && !have.contains(uuid)
                }.map { o in
                    var o = o
                    o["addedBy"] = .string(o.string("addedBy") ?? from)
                    o["pending"] = nil
                    return o
                }
            }
            let plans = try prepared(try data.reqObjects("plans"), have: havePlans)
            let expenses = try prepared(try data.reqObjects("expenses"), have: haveExpenses)

            var copied: [String: String] = [:]
            do {
                for item in plans + expenses {
                    for ph in item.objects("photos") ?? [] {
                        let name = try ph.reqString("file")
                        if let path = try copyEntry(zip, name) { copied[name] = path }
                    }
                }
                try database.write { db in
                    let categoryIds = try Self.mergeCategories(db, data.objects("categories"))
                    let paymentIds = try Self.mergePayments(db, data.objects("payments"))
                    let t = JSONObject([("members", .array([])), ("rates", .array([])),
                                        ("plans", .array(plans.map(JSON.object))), ("expenses", .array(expenses.map(JSON.object)))])
                    try Self.writeContents(db, tripId: tripId, t, categoryIds, paymentIds, copied, keepPending: false, existingPlans: true)
                }
            } catch {
                files.delete(Array(copied.values))
                throw error
            }
            return .imported(kind: Self.kindAdditions, tripIds: [tripId], updated: plans.count + expenses.count)
        } catch let e as BadArchive {
            return .failed(e.message)
        } catch {
            return .failed("檔案損壞,無法匯入")
        }
    }

    // MARK: - Plans from the desktop planner

    /// What merging a desktop plans file will do, for the confirmation dialog.
    public struct PlansPreview: Equatable, Sendable {
        public let tripName: String
        public let newTrip: Bool
        public let added: Int
        public let updated: Int
        public let deleted: Int
        /// Set when the file cannot go into this phone (someone else's shared trip).
        public let refused: String?
    }

    private static func deleted(_ data: JSONObject) -> [String] { data.array("deleted")?.compactMap(\.stringValue) ?? [] }

    public func previewPlans(_ url: URL) throws -> PlansPreview {
        let zip = try Zip(url)
        _ = try zip.manifest()
        let data = try zip.json("data.json")
        let t = try data.reqObject("trip")
        let trip = try database.read { try Q.tripByUuid($0, try t.reqString("uuid")) }
        if let trip, trip.readOnly {
            let by = trip.sharedBy ?? ""
            return PlansPreview(tripName: trip.name, newTrip: false, added: 0, updated: 0, deleted: 0,
                                refused: "「\(trip.name)」是\(by)記帳的旅程,請把這個檔案傳給\(by)")
        }
        let have: Set<String> = try trip.map { tr in try database.read { db in Set(try Q.plans(db, tr.id!).map(\.uuid)) } } ?? []
        let incoming = try data.reqObjects("plans").map { try $0.reqString("uuid") }
        let fileName = try t.reqString("name")
        return PlansPreview(
            tripName: trip?.name ?? fileName, newTrip: trip == nil,
            added: incoming.filter { !have.contains($0) }.count, updated: incoming.filter { have.contains($0) }.count,
            deleted: Self.deleted(data).filter { have.contains($0) }.count, refused: nil
        )
    }

    /// Merges a desktop plans file: the trip is matched by uuid (created if missing); each plan is updated or added
    /// by uuid, items deleted on the desktop are deleted here, the desktop's day notes replace these days' notes.
    /// Expenses are never touched.
    /// [organizer]: only when the trip is not on this phone yet — the name of whoever keeps its accounts, if that is
    /// someone else. The trip is then created as their read-only copy (my own additions go back to them).
    public func importPlans(_ url: URL, organizer: String? = nil) -> Result {
        do {
            let zip = try Zip(url)
            let m = try zip.manifest()
            if m.optString("kind") != Self.kindPlans { throw BadArchive("這不是電腦行程檔") }
            let data = try zip.json("data.json")
            let t = try data.reqObject("trip")
            let existing = try database.read { try Q.tripByUuid($0, try t.reqString("uuid")) }
            if let existing, existing.readOnly {
                let by = existing.sharedBy ?? ""
                throw BadArchive("「\(existing.name)」是\(by)記帳的旅程,請把這個檔案傳給\(by)")
            }
            let plans = try data.reqObjects("plans")
            var copied: [String: String] = [:]
            var oldFiles: [String] = []
            var changed = 0
            let tripId: Int64
            do {
                for p in plans {
                    for ph in p.objects("photos") ?? [] {
                        let name = try ph.reqString("file")
                        if let path = try copyEntry(zip, name) { copied[name] = path }
                    }
                }
                tripId = try database.write { db in
                    let categoryIds = try Self.mergeCategories(db, data.objects("categories"))
                    let id: Int64
                    if let existingId = existing?.id {
                        id = existingId
                    } else {
                        var trip = Trip(name: try t.reqString("name"), startDate: try t.reqInt64("startDate"), endDate: try t.reqInt64("endDate"),
                                        uuid: try t.reqString("uuid"), navApp: t.string("navApp"))
                        if let by = organizer?.trimmingCharacters(in: .whitespacesAndNewlines), !by.isEmpty {
                            trip.sharedBy = String(by.prefix(20))
                            trip.sharedAt = m.optInt64("exportedAt")
                        }
                        try trip.insert(db)
                        id = trip.id!
                    }
                    for p in plans {
                        let uuid = try p.reqString("uuid")
                        func fill(_ base: PlanItem) throws -> PlanItem {
                            var b = base
                            b.title = try p.reqString("title")
                            b.categoryId = p.string("category").flatMap { categoryIds[$0] }
                            b.date = p.int64("date")
                            b.minuteOfDay = p.int("minuteOfDay")
                            b.status = p.optString("status", PlanStatus.todo)
                            b.reservation = p.optString("reservation", Reservation.none)
                            b.reservationNote = p.optString("reservationNote")
                            b.location = p.optString("location")
                            b.note = p.optString("note")
                            return b
                        }
                        let planId: Int64
                        if let current = try Q.planByUuid(db, tripId: id, uuid: uuid) {
                            try fill(current).update(db)
                            for ph in try Q.planPhotos(db, planId: current.id!) {
                                oldFiles.append(ph.path)
                                try db.execute(sql: "DELETE FROM plan_photo WHERE id = ?", arguments: [ph.id])
                            }
                            planId = current.id!
                        } else {
                            var item = try fill(PlanItem(tripId: id, title: "", createdAt: p.optInt64("createdAt", nowMillis()), uuid: uuid))
                            try item.insert(db)
                            planId = item.id!
                        }
                        for ph in p.objects("photos") ?? [] {
                            guard let path = copied[try ph.reqString("file")] else { continue }
                            var photo = PlanPhoto(planItemId: planId, path: path, width: ph.optInt("width"), height: ph.optInt("height"))
                            try photo.insert(db)
                        }
                        changed += 1
                    }
                    for uuid in Self.deleted(data) {
                        guard let gone = try Q.planByUuid(db, tripId: id, uuid: uuid) else { continue }
                        oldFiles += try Q.planPhotos(db, planId: gone.id!).map(\.path)
                        try Q.deletePlan(db, gone.id!)
                        changed += 1
                    }
                    for n in data.objects("dayNotes") ?? [] {
                        try Q.setDayNote(db, tripId: id, day: try n.reqInt64("day"), text: n.optString("text"))
                    }
                    return id
                }
            } catch {
                files.delete(Array(copied.values))
                throw error
            }
            files.delete(oldFiles)
            return .imported(kind: Self.kindPlans, tripIds: [tripId], updated: changed)
        } catch let e as BadArchive {
            return .failed(e.message)
        } catch {
            return .failed("檔案損壞,無法匯入")
        }
    }
}
