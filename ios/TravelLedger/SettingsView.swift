import LedgerCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings (ui/SettingsScreen.kt). Photo, category and backup settings arrive with their stages.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editName = false
    @State private var nameDraft = ""
    @State private var picking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("外觀")
                HStack(spacing: 10) {
                    ForEach(ThemeMode.allCases, id: \.self) { m in
                        OptionCard(label: m.label, selected: m == model.settings.theme,
                                   symbol: m == .system ? "circle.lefthalf.filled" : m == .light ? "sun.max" : "moon") {
                            model.settings.theme = m
                        }
                    }
                }

                SectionHeader("字體大小")
                HStack(spacing: 10) {
                    ForEach(FontScale.allCases, id: \.self) { f in
                        OptionCard(label: f.label, selected: f == model.settings.fontSize, sample: f.sample) {
                            model.settings.fontSize = f
                        }
                    }
                }

                SectionHeader("備份與分享")
                VStack(spacing: 0) {
                    SettingRow(symbol: "person.fill", color: Palette.category(4), title: "我的名字",
                               subtitle: model.settings.myName.isBlank ? "分享旅程給同伴時顯示" : model.settings.myName) {
                        nameDraft = model.settings.myName
                        editName = true
                    }
                    Divider().overlay(Palette.hairline).padding(.leading, 68)
                    SettingRow(symbol: "arrow.counterclockwise", color: Palette.category(5), title: "從檔案還原或匯入",
                               subtitle: "備份檔,或同伴分享的旅程") { picking = true }
                }
                .ledgerCard(padding: 0)

                SectionHeader("關於")
                VStack(spacing: 0) {
                    SettingRow(symbol: "dollarsign.arrow.circlepath", color: Palette.category(6), title: "結算幣別", subtitle: "新台幣(TWD)", action: nil)
                    Divider().overlay(Palette.hairline).padding(.leading, 68)
                    HStack(spacing: 14) {
                        AppIconView(size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("卡溜趴").font(.system(size: 16))
                            Text("版本 \(model.appVersion) · 資料只存在這支手機,記得定期備份")
                                .font(.system(size: 13)).foregroundStyle(Palette.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    Divider().overlay(Palette.hairline)
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text("作者 ").font(.system(size: 15)).foregroundStyle(Palette.onSurfaceVariant)
                        AuthorSignature(size: 22)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .ledgerCard(padding: 0)
            }
            .foregroundStyle(Palette.onBackground)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Palette.background)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .alert("我的名字", isPresented: $editName) {
            TextField("同伴會看到這個名字", text: $nameDraft)
            Button("取消", role: .cancel) {}
            Button("確定") { model.settings.myName = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20)) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url): model.receive(url)
            case .failure: model.show("無法開啟這個檔案")
            }
        }
    }
}

private struct OptionCard: View {
    let label: String
    let selected: Bool
    var symbol: String?
    var sample: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(selected ? Palette.primary : Palette.onSurfaceVariant) }
                if let sample {
                    Text("Aa").font(.system(size: sample, weight: .semibold)).foregroundStyle(selected ? Palette.primary : Palette.onSurfaceVariant)
                        .dynamicTypeSize(.large)
                }
                Text(label).font(.system(size: 15, weight: .semibold)).lineLimit(1).fixedSize()
                    .foregroundStyle(selected ? Palette.onPrimaryContainer : Palette.onBackground)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.vertical, 8)
            .background(selected ? Palette.primaryContainer : Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Palette.primary : Palette.hairline, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingRow: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let action: (() -> Void)?

    var body: some View {
        let row = HStack(spacing: 14) {
            IconTile(symbol: symbol, color: color, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 16))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.onSurfaceVariant)
            }
            Spacer(minLength: 0)
            if action != nil { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMuted) }
        }
        .foregroundStyle(Palette.onBackground)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}
