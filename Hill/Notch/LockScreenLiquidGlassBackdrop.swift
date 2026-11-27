import AppKit
import SwiftUI

struct LockScreenLiquidGlassBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat
    var style: Int = 0

    func makeNSView(context: Context) -> NSView {
        let container = LockScreenLiquidGlassHost()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        guard let glassType = NSClassFromString("NSGlassEffectView")
            as? NSView.Type else {
            return fallbackView()
        }

        let glass = glassType.init(frame: .zero)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.setValue(cornerRadius, forKey: "cornerRadius")
        setStyle(style, on: glass)

        let content = NSHostingView(
            rootView: Color.white.opacity(0.03)
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.setValue(content, forKey: "contentView")

        container.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(
                equalTo: container.leadingAnchor
            ),
            glass.trailingAnchor.constraint(
                equalTo: container.trailingAnchor
            ),
            glass.topAnchor.constraint(equalTo: container.topAnchor),
            glass.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.glassView = glass
        container.scheduleBackdropSetup()
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? LockScreenLiquidGlassHost,
              let glass = container.glassView else {
            return
        }

        glass.setValue(cornerRadius, forKey: "cornerRadius")
        setStyle(style, on: glass)
        container.scheduleBackdropSetup()
    }

    private func fallbackView() -> NSView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    private func setStyle(_ value: Int, on glass: NSView) {
        guard glass.responds(to: NSSelectorFromString("setStyle:")) else {
            return
        }
        glass.setValue(value, forKey: "style")
    }
}

private final class LockScreenLiquidGlassHost: NSView {
    weak var glassView: NSView?

    private var setupGeneration = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleBackdropSetup()
    }

    override func layout() {
        super.layout()
        scheduleBackdropSetup()
    }

    func scheduleBackdropSetup() {
        setupGeneration += 1
        let generation = setupGeneration

        for delay in [0.05, 0.30] {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay
            ) { [weak self] in
                guard let self,
                      self.setupGeneration == generation else {
                    return
                }
                self.applyBackdropSettings()
            }
        }
    }

    private func applyBackdropSettings() {
        guard let rootLayer = glassView?.layer else { return }
        configureBackdropLayers(in: rootLayer)
    }

    private func configureBackdropLayers(in layer: CALayer) {
        if NSStringFromClass(type(of: layer))
            .contains("CABackdropLayer") {
            if layer.responds(
                to: NSSelectorFromString("setWindowServerAware:")
            ) {
                layer.setValue(true, forKey: "windowServerAware")
            }
            if layer.responds(to: NSSelectorFromString("setScale:")) {
                layer.setValue(1.0, forKey: "scale")
            }
        }

        layer.sublayers?.forEach(configureBackdropLayers)
    }
}
