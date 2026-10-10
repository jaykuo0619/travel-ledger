import AppIntents
import LedgerCore
import SwiftUI

// Siri and the Shortcuts app: 「用卡溜趴記一筆」. The expense goes into the trip that is on (or starts within
// 30 days), with the same defaults as the 記一筆 screen.

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "記一筆"
    static let description = IntentDescription("在目前的旅程記一筆支出,不用打開 App。")

    @Parameter(title: "金額", requestValueDialog: "多少錢?")
    var amount: Double

    @Parameter(title: "名稱", description: "店家或項目名稱,可以不填")
    var name: String?

    @Parameter(title: "幣別", description: "3 碼代碼,例如 KRW、JPY;不填就用這趟旅程上一筆的幣別")
    var currency: String?

    static var parameterSummary: some ParameterSummary {
        Summary("記一筆 \(\.$amount)") {
            \.$name
            \.$currency
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        do {
            let reference = model.settings.autoRates ? model.referenceRates : nil
            let saved = try model.db.write {
                try Q.quickExpense($0, amount: amount, title: name, currency: currency, reference: reference, minuteOfDay: minute)
            }
            model.changed()
            let e = saved.expense
            let home = e.currency == homeCurrency ? "" : "(約 \(fmtMoney(e.homeAmount)))"
            return .result(dialog: "已在「\(saved.trip.name)」記下 \(fmtAmount(e.amount, e.currency))\(home)")
        } catch QuickExpenseError.noTrip {
            return .result(dialog: "目前沒有進行中或即將出發的旅程,請先在卡溜趴建立旅程。")
        } catch QuickExpenseError.badAmount {
            return .result(dialog: "金額要大於 0。")
        } catch QuickExpenseError.noRate(let code) {
            return .result(dialog: "還不知道 \(code) 的匯率,請先在卡溜趴的旅程裡設定。")
        } catch {
            return .result(dialog: "記帳失敗,請打開卡溜趴再試一次。")
        }
    }
}

/// Opens the app on the 記一筆 screen of the current trip.
struct OpenAddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "打開記一筆"
    static let description = IntentDescription("打開卡溜趴的記一筆畫面。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = AppModel.shared
        if let id = model.tripToOpenAtLaunch() {
            model.openTrip(id)
            // After the launch animation and any sheet that is closing.
            try? await Task.sleep(for: .milliseconds(600))
            if !model.sheetOpen { model.expenseEditing = ExpenseEditTarget(tripId: id) }
        }
        return .result()
    }
}

struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["用\(.applicationName)記一筆", "\(.applicationName)記一筆", "\(.applicationName)記帳"],
                    shortTitle: "記一筆", systemImageName: "plus.circle.fill")
        AppShortcut(intent: OpenAddExpenseIntent(),
                    phrases: ["打開\(.applicationName)記一筆"],
                    shortTitle: "打開記一筆", systemImageName: "square.and.pencil")
    }
}
