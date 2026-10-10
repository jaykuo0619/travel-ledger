import LedgerCore
import PencilKit
import SwiftUI
import UIKit

/// Drawing with Apple Pencil (or a finger) on a picture or on a blank page. The result is an ordinary JPEG, so it
/// travels in the same .zip files as any screenshot and the other platforms can show it.
struct DrawingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// The picture to draw on; nil = a blank page.
    let background: UIImage?
    /// The blank page's size in pixels (portrait 3:4 unless said otherwise).
    var pageSize = CGSize(width: 1200, height: 1600)
    var saveText = "儲存"
    let onSave: (Data) -> Void
    @State private var canvas = PKCanvasView()
    @State private var empty = true

    var body: some View {
        NavigationStack {
            AnnotateCanvas(canvas: canvas, background: background, pageSize: pageSize) { empty = canvas.drawing.strokes.isEmpty }
                .background(Palette.surfaceVariant)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { canvas.undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                            .accessibilityLabel("復原一筆")
                            .disabled(empty)
                        Button(saveText) {
                            if let data = AnnotateCanvas.render(canvas: canvas, background: background, pageSize: pageSize) { onSave(data) }
                            dismiss()
                        }
                        .disabled(empty)
                    }
                }
        }
        .tint(Palette.primary)
        .interactiveDismissDisabled(!empty)
    }
}

/// The picture (or white paper) with a transparent PencilKit canvas exactly over it, and the tool picker.
struct AnnotateCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    let background: UIImage?
    let pageSize: CGSize
    let onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange) }

    func makeUIView(context: Context) -> Holder {
        let holder = Holder(canvas: canvas, background: background, pageSize: pageSize)
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput // a finger draws too (iPhone, or no Pencil at hand)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light // ink keeps the colour it was picked in, on paper or on a photo
        canvas.isScrollEnabled = false
        let picker = context.coordinator.picker
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return holder
    }

    func updateUIView(_ view: Holder, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let picker = PKToolPicker()
        let onChange: () -> Void
        init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { onChange() }
    }

    final class Holder: UIView {
        let canvas: PKCanvasView
        let imageView = UIImageView()
        let aspect: CGFloat

        init(canvas: PKCanvasView, background: UIImage?, pageSize: CGSize) {
            self.canvas = canvas
            let size = background?.size ?? pageSize
            aspect = size.height > 0 ? size.width / size.height : 0.75
            super.init(frame: .zero)
            imageView.image = background
            imageView.backgroundColor = .white
            imageView.contentMode = .scaleToFill
            addSubview(imageView)
            addSubview(canvas)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        /// The picture as large as it fits (room is kept at the bottom for the floating tool picker on a phone).
        override func layoutSubviews() {
            super.layoutSubviews()
            let area = bounds.inset(by: UIEdgeInsets(top: 8, left: 8, bottom: traitCollection.horizontalSizeClass == .compact ? 96 : 8, right: 8))
            guard area.width > 0, area.height > 0 else { return }
            var w = area.width, h = w / aspect
            if h > area.height { h = area.height; w = h * aspect }
            let frame = CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
            imageView.frame = frame
            canvas.frame = frame
        }
    }

    /// The picture with the ink on it, as a JPEG at most 1600 px on its long edge.
    static func render(canvas: PKCanvasView, background: UIImage?, pageSize: CGSize) -> Data? {
        guard canvas.bounds.width > 0 else { return nil }
        var size = background.map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) } ?? pageSize
        let long = max(size.width, size.height)
        if long > 1600 { size = CGSize(width: (size.width * 1600 / long).rounded(), height: (size.height * 1600 / long).rounded()) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rect = CGRect(origin: .zero, size: size)
        let ink = canvas.drawing.image(from: canvas.bounds, scale: size.width / canvas.bounds.width)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(rect)
            background?.draw(in: rect)
            ink.draw(in: rect)
        }.jpegData(compressionQuality: 0.85)
    }
}

/// What a drawing sheet is open for: a blank note, or one stored picture (by its path).
struct DrawTarget: Identifiable, Hashable {
    /// nil = a blank page.
    var path: String?
    var id: String { path ?? "blank" }
}

extension AppModel {
    /// A stored picture at full size, to draw on.
    func storedImage(_ path: String) -> UIImage? { UIImage(contentsOfFile: files.url(path).path) }
}

// MARK: - Marking a receipt

/// A receipt with the text that was read from it, ready to be marked.
struct ReceiptToMark: Identifiable {
    let id = UUID()
    let image: UIImage
    let lines: [OcrLine]
    let currency: String
}

/// Circle an amount to use it, or circle / strike through several items to add them up: the lines the pen touches
/// are added together, and so are the remaining items, and either sum can go into 記一筆. Nothing is stored.
struct ReceiptMarkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let receipt: ReceiptToMark
    let onUse: (Double) -> Void
    @State private var canvas = PKCanvasView()
    @State private var picked = MarkedAmounts(marked: [], rest: [])

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AnnotateCanvas(canvas: canvas, background: receipt.image, pageSize: receipt.image.size) { recount() }
                    .background(Palette.surfaceVariant)
                VStack(alignment: .leading, spacing: 8) {
                    if picked.marked.isEmpty {
                        Text("圈出一個金額就用那個金額;圈起或劃過幾個品項,會把它們加起來。").appFont(size: 15).foregroundStyle(Palette.onSurfaceVariant)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { choices }
                            VStack(spacing: 10) { choices }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 96) // room for the tool picker
                // A fixed height: the picture must not move under the strokes when the buttons appear.
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
                .background(Palette.card)
            }
            .navigationTitle("在收據上圈選")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { canvas.undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .accessibilityLabel("復原一筆")
                        .disabled(canvas.drawing.strokes.isEmpty)
                }
            }
        }
        .tint(Palette.primary)
    }

    @ViewBuilder private var choices: some View {
        PillButton("用畫到的 \(fmtAmount(picked.markedTotal, receipt.currency))", height: 48) {
            onUse(picked.markedTotal)
            dismiss()
        }
        if picked.restTotal > 0 {
            Button {
                onUse(picked.restTotal)
                dismiss()
            } label: {
                Text("用其餘的 \(fmtAmount(picked.restTotal, receipt.currency))").appFont(size: 16, weight: .semibold).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.secondaryContainer, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Which printed lines the strokes cover, in the picture's own pixels.
    private func recount() {
        guard canvas.bounds.width > 0 else { return }
        let scale = Double(receipt.image.size.width * receipt.image.scale / canvas.bounds.width)
        let marks = canvas.drawing.strokes.map { s -> MarkBox in
            let b = s.renderBounds
            return MarkBox(left: Double(b.minX) * scale, top: Double(b.minY) * scale, right: Double(b.maxX) * scale, bottom: Double(b.maxY) * scale)
        }
        picked = markedAmounts(receipt.lines, marks: marks)
    }
}

/// A photo with a white frame, wider at the bottom, to write a date or a few words on — like an instant photo.
func instantPhotoFrame(_ image: UIImage) -> UIImage {
    let w = image.size.width * image.scale, h = image.size.height * image.scale
    let side = (w * 0.05).rounded(), bottom = (w * 0.22).rounded()
    let size = CGSize(width: w + side * 2, height: h + side + bottom)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        image.draw(in: CGRect(x: side, y: side, width: w, height: h))
    }
}
