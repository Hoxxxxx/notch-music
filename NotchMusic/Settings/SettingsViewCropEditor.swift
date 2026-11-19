import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WatchFaceCropEditorState: Identifiable {
    let id = UUID()
    let image: NSImage
    let initialCrop: CGRect
    let existingPath: String?
}

struct WatchFaceCropEditor: View {
    let image: NSImage
    let onCancel: () -> Void
    let onConfirm: (CGRect) -> Void

    @State private var cropRect: CGRect
    @State private var sizeFraction: Double
    @State private var moveStartRect: CGRect?

    init(
        image: NSImage,
        initialCrop: CGRect,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (CGRect) -> Void
    ) {
        self.image = image
        self.onCancel = onCancel
        self.onConfirm = onConfirm

        let fallback = WatchFaceImageSettings.centeredCrop(for: image)
        let displayWidth = initialCrop.width * image.size.width
        let displayHeight = initialCrop.height * image.size.height
        let isUsable = initialCrop.width > 0
            && initialCrop.height > 0
            && displayHeight > 0
            && abs(displayWidth / displayHeight - 1) < 0.02
        let resolvedCrop = isUsable ? initialCrop : fallback
        let maximumSquare = max(
            min(image.size.width, image.size.height),
            1
        )
        let selectedSquare = min(displayWidth, displayHeight)
        let initialFraction = resolvedCrop == fallback
            ? 0.78
            : Double(selectedSquare / maximumSquare)

        _cropRect = State(initialValue: resolvedCrop)
        _sizeFraction = State(
            initialValue: min(max(initialFraction, 0.2), 1)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择表盘区域")
                        .font(.system(size: 17, weight: .semibold))

                    Text("拖动圆角选区调整位置，使用滑块调整显示范围。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(
                    Color.primary.opacity(0.06),
                    in: Circle()
                )
                .accessibilityLabel("关闭区域选择")
            }

            GeometryReader { geometry in
                let canvasHeight = max(geometry.size.height - 38, 1)
                let canvasSize = CGSize(
                    width: geometry.size.width,
                    height: canvasHeight
                )
                let imageRect = aspectFitRect(
                    imageSize: image.size,
                    in: CGRect(origin: .zero, size: canvasSize)
                        .insetBy(dx: 10, dy: 0)
                )

                VStack(spacing: 10) {
                    imageCanvas(
                        imageRect: imageRect,
                        canvasSize: canvasSize
                    )
                    .frame(height: canvasHeight)

                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.dashed")
                            .foregroundStyle(.secondary)

                        Slider(
                            value: sizeBinding(imageRect: imageRect),
                            in: 0.2...1
                        )

                        Text("\(Int((sizeFraction * 100).rounded()))%")
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(height: 28)
                }
            }
            .frame(height: 408)

            HStack(spacing: 10) {
                Text("选区之外的画面不会显示在表盘上。")
                    .settingsCaption()

                Spacer()

                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("使用此区域") {
                    onConfirm(cropRect)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 560, height: 560)
    }

    private func imageCanvas(
        imageRect: CGRect,
        canvasSize: CGSize
    ) -> some View {
        let selection = selectionRect(in: imageRect)
        let cornerRadius = selection.width
            * WatchFaceSurfaceMetrics.cornerRadiusRatio
        let selectionShape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.34))

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)

            Path { path in
                path.addRect(CGRect(origin: .zero, size: canvasSize))
                path.addPath(
                    Path(
                        roundedRect: selection,
                        cornerRadius: cornerRadius
                    )
                )
            }
            .fill(
                Color.black.opacity(0.58),
                style: FillStyle(eoFill: true)
            )

            selectionShape
                .stroke(Color.white.opacity(0.96), lineWidth: 2)
                .frame(width: selection.width, height: selection.height)
                .position(x: selection.midX, y: selection.midY)
                .shadow(color: .black.opacity(0.54), radius: 3)

            RoundedRectangle(
                cornerRadius: max(
                    cornerRadius - 2.5 * WatchFaceSurfaceMetrics.cornerRadiusRatio,
                    0
                ),
                style: .continuous
            )
                .stroke(Color.accentColor.opacity(0.88), lineWidth: 1)
                .frame(
                    width: max(selection.width - 5, 1),
                    height: max(selection.height - 5, 1)
                )
                .position(x: selection.midX, y: selection.midY)

            selectionShape
                .fill(Color.clear)
                .contentShape(selectionShape)
                .frame(width: selection.width, height: selection.height)
                .position(x: selection.midX, y: selection.midY)
                .gesture(moveGesture(imageRect: imageRect))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func moveGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard imageRect.width > 0, imageRect.height > 0 else {
                    return
                }
                if moveStartRect == nil {
                    moveStartRect = cropRect
                }
                guard let start = moveStartRect else { return }

                let deltaX = value.translation.width / imageRect.width
                let deltaY = value.translation.height / imageRect.height
                let x = min(
                    max(start.minX + deltaX, 0),
                    max(1 - start.width, 0)
                )
                let y = min(
                    max(start.minY + deltaY, 0),
                    max(1 - start.height, 0)
                )
                cropRect = CGRect(
                    x: x,
                    y: y,
                    width: start.width,
                    height: start.height
                )
            }
            .onEnded { _ in
                moveStartRect = nil
            }
    }

    private func sizeBinding(imageRect: CGRect) -> Binding<Double> {
        Binding(
            get: { sizeFraction },
            set: { newValue in
                guard imageRect.width > 0, imageRect.height > 0 else {
                    return
                }
                sizeFraction = min(max(newValue, 0.2), 1)
                let side = min(imageRect.width, imageRect.height)
                    * CGFloat(sizeFraction)
                let width = side / imageRect.width
                let height = side / imageRect.height
                let x = min(
                    max(cropRect.midX - width / 2, 0),
                    max(1 - width, 0)
                )
                let y = min(
                    max(cropRect.midY - height / 2, 0),
                    max(1 - height, 0)
                )
                cropRect = CGRect(
                    x: x,
                    y: y,
                    width: width,
                    height: height
                )
            }
        )
    }

    private func selectionRect(in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + cropRect.minX * imageRect.width,
            y: imageRect.minY + cropRect.minY * imageRect.height,
            width: cropRect.width * imageRect.width,
            height: cropRect.height * imageRect.height
        )
    }

    private func aspectFitRect(
        imageSize: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let scale = min(
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

