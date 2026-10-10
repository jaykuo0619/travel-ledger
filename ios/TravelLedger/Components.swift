import LedgerCore
import SwiftUI
import UIKit

// Shared building blocks (ui/Components.kt, ui/CategoryStyle.kt, ui/Images.kt).

// MARK: - Icons

enum Icons {
    /// SF Symbols for the category icon keys stored in the database.
    static func category(_ key: String) -> String {
        switch key {
        case "bus": return "bus.fill"
        case "train": return "tram.fill"
        case "flight": return "airplane"
        case "taxi": return "car.fill"
        case "hotel": return "bed.double.fill"
        case "food": return "fork.knife"
        case "ramen": return "takeoutbag.and.cup.and.straw.fill"
        case "cafe": return "cup.and.saucer.fill"
        case "bar": return "wineglass.fill"
        case "shopping": return "bag.fill"
        case "grocery": return "cart.fill"
        case "gift": return "gift.fill"
        case "camera": return "camera.fill"
        case "ticket": return "ticket.fill"
        case "spa": return "leaf.fill"
        case "beach": return "beach.umbrella.fill"
        case "medical": return "cross.case.fill"
        case "phone": return "simcard.fill"
        case "luggage": return "suitcase.rolling.fill"
        default: return "ellipsis"
        }
    }

    static func payment(_ name: String?) -> String {
        switch paymentIconKey(name) {
        case "cash": return "banknote.fill"
        case "card": return "creditcard.fill"
        case "mobile": return "iphone"
        default: return "wallet.pass.fill"
        }
    }
}

/// A category's icon and colour.
struct IconStyle {
    let symbol: String
    let color: Color

    static func category(name: String?, icon: String?, color: Int?) -> IconStyle {
        let s = CategoryStyle.resolve(name: name, icon: icon, color: color)
        return IconStyle(symbol: Icons.category(s.icon), color: Palette.category(s.color))
    }
}

extension Palette {
    static func category(_ index: Int) -> Color {
        let list = CategoryStyle.paletteHex
        return Color(hex: list[min(max(index, 0), list.count - 1)])
    }

    static func avatar(_ name: String) -> Color { category(CategoryStyle.avatarColor(name)) }
}

// MARK: - Cards and tiles

struct LedgerCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }
}

extension View {
    /// White rounded card with a hairline border (LedgerCard).
    func ledgerCard(padding: CGFloat = 16) -> some View { modifier(LedgerCardModifier(padding: padding)) }
}

/// Tinted rounded-square icon used for categories and payment methods.
struct IconTile: View {
    @Environment(\.colorScheme) private var scheme
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    var corner: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(color.opacity(scheme == .dark ? 0.22 : 0.13))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(color))
    }
}

/// Labeled box: small caption on top, content below.
struct FieldBox<Content: View, Trailing: View>: View {
    let label: String
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(_ label: String, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.label = label
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).appFont(size: 13, weight: .medium).foregroundStyle(Palette.onSurfaceVariant)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

struct SectionHeader<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(text).appFont(size: 16, weight: .semibold)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Full-width primary button with a 16pt corner.
struct PillButton: View {
    let text: String
    var symbol: String?
    var height: CGFloat = 52
    var enabled = true
    let action: () -> Void

    init(_ text: String, symbol: String? = nil, height: CGFloat = 52, enabled: Bool = true, action: @escaping () -> Void) {
        self.text = text; self.symbol = symbol; self.height = height; self.enabled = enabled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .semibold)) }
                Text(text).appFont(size: 16, weight: .semibold)
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(enabled ? Palette.onPrimary : Palette.onSurfaceVariant)
            .background(enabled ? Palette.primary : Palette.surfaceVariant, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Budget

func budgetColor(_ fraction: Double) -> Color {
    switch BudgetLevel(fraction) {
    case .danger: return Palette.danger
    case .warning: return Palette.warning
    case .normal: return Palette.success
    }
}

/// Budget usage bar: green, amber past 80 %, red past 100 %.
struct BudgetBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceVariant)
                Capsule().fill(budgetColor(fraction))
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - People

/// Initial-letter avatar for trip members.
struct Avatar: View {
    @Environment(\.colorScheme) private var scheme
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let c = Palette.avatar(name)
        Circle().fill(c.opacity(scheme == .dark ? 0.3 : 0.16))
            .frame(width: size, height: size)
            .overlay(
                // Sized from the circle, not the text setting, so the initial always fits inside it.
                Text(String(name.prefix(1))).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(c)
                    .lineLimit(1).fixedSize()
            )
            .dynamicTypeSize(.large)
    }
}

// MARK: - Images

/// Decoded local pictures, kept small and shared between screens.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 40 }

    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func put(_ key: String, _ image: UIImage) { cache.setObject(image, forKey: key as NSString) }
    func remove(_ key: String) { cache.removeObject(forKey: key as NSString) }

    /// Loads [url] scaled down to about [maxPixel] on its long edge.
    static func load(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixel))"
        if let hit = shared.get(key) { return hit }
        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image { shared.put(key, image) }
        return image
    }
}

/// A picture from the app's own folder, filled and cropped; [placeholder] until (or unless) it loads.
struct LocalImage<Placeholder: View>: View {
    @Environment(AppModel.self) private var model
    let path: String?
    var maxPixel: CGFloat = 1080
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: path) {
            guard let path, model.files.exists(path) else { image = nil; return }
            image = await ImageCache.load(model.files.url(path), maxPixel: maxPixel)
        }
    }
}

/// Trip cover: the photo if any, otherwise an illustration picked from the trip name.
struct TripCover: View {
    let path: String?
    let name: String
    var startDate: Int64?
    var theme: String?

    var body: some View {
        Color.clear
            .overlay(
                LocalImage(path: path) { CoverArtwork(name: name, startDate: startDate, theme: theme) }
            )
            .clipped()
    }
}

/// Small translucent badge placed on top of a cover.
struct CoverBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .appFont(size: 13, weight: .medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.38)))
    }
}

/// Muted inline meta item: small icon + text.
struct MetaItem: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 12))
            Text(text).appFont(size: 13).lineLimit(1)
        }
        .foregroundStyle(Palette.onSurfaceVariant)
    }
}

/// Selectable pill used for filters and option rows.
struct SelectPill<Leading: View>: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var leading: Leading

    init(_ text: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder leading: () -> Leading = { EmptyView() }) {
        self.text = text; self.selected = selected; self.action = action; self.leading = leading()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading
                Text(text).appFont(size: 15, weight: .semibold).lineLimit(1).fixedSize()
            }
            .foregroundStyle(selected ? Palette.onPrimaryContainer : Palette.onBackground)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? Palette.primaryContainer : Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Palette.primary : Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wraps its children onto more lines when they don't fit (Compose FlowRow).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = fitted(subviews[i], width: bounds.width)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    /// The item's own size, or what it needs when held to the row's width if it is wider than that.
    private func fitted(_ view: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > width, width > 0 else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, view) in subviews.enumerated() {
            let size = fitted(view, width: width)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Branding

/// The launcher artwork, so the app looks the same on the home screen and inside.
struct AppIconView: View {
    var size: CGFloat = 44

    var body: some View {
        Image("AppIconArt").resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// The author's signature.
struct AuthorSignature: View {
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat = 15

    var body: some View {
        Text("ArchieKUO")
            .font(.system(size: size, weight: .semibold, design: .serif).italic())
            .kerning(0.5)
            .foregroundStyle(scheme == .dark ? Color(hex: 0xE6C463) : Color(hex: 0xB8901F))
            .lineLimit(1)
    }
}

/// A centered empty-state message with an icon tile.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            IconTile(symbol: symbol, color: Palette.primary, size: 72, corner: 24)
            Text(title).appFont(size: 17, weight: .semibold).padding(.top, 16)
            Text(message).appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
                .multilineTextAlignment(.center).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}
