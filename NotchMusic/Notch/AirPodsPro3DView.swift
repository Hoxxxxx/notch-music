import AppKit
import SceneKit
import SwiftUI

enum AirPodsModelKind: String, Equatable {
    case airPods
    case airPodsPro
    case airPodsMax

    var displayName: String {
        switch self {
        case .airPods:
            return "AirPods"
        case .airPodsPro:
            return "AirPods Pro"
        case .airPodsMax:
            return "AirPods Max"
        }
    }

    static func inferred(
        from name: String,
        productID: UInt16?
    ) -> AirPodsModelKind {
        if let productID {
            if airPodsMaxProductIDs.contains(productID) {
                return .airPodsMax
            }
            if airPodsProProductIDs.contains(productID) {
                return .airPodsPro
            }
            if airPodsProductIDs.contains(productID) {
                return .airPods
            }
        }

        if name.localizedCaseInsensitiveContains("Max") {
            return .airPodsMax
        }
        if name.localizedCaseInsensitiveContains("Pro") {
            return .airPodsPro
        }
        return .airPods
    }

    fileprivate var resourceName: String {
        switch self {
        case .airPods:
            return "AirPods"
        case .airPodsPro:
            return "AirPodsPro"
        case .airPodsMax:
            return "AirPodsMax"
        }
    }

    fileprivate var nodeName: String {
        switch self {
        case .airPods:
            return "wHBfZZynUdghYAn"
        case .airPodsPro:
            return "YamPaavUOjSVJHE"
        case .airPodsMax:
            return "BDKrgzXXuqVmwmB"
        }
    }

    fileprivate var targetExtent: Float {
        switch self {
        case .airPods:
            return 1.13
        case .airPodsPro:
            return 1.68
        case .airPodsMax:
            return 1.08
        }
    }

    private static let airPodsProductIDs: Set<UInt16> = [
        0x2002,
        0x200F,
        0x2013,
        0x2019,
        0x201B
    ]
    private static let airPodsProProductIDs: Set<UInt16> = [
        0x200E,
        0x2014,
        0x2024,
        0x2026,
        0x2027,
        0x2029
    ]
    private static let airPodsMaxProductIDs: Set<UInt16> = [
        0x200A,
        0x201F
    ]
}

enum AirPodsModelSelection: String, CaseIterable, Identifiable {
    static let storageKey = "NotchMusic.airPodsModelSelection"

    case automatic
    case airPods
    case airPodsPro
    case airPodsMax

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "自动识别"
        case .airPods:
            return "AirPods"
        case .airPodsPro:
            return "AirPods Pro"
        case .airPodsMax:
            return "AirPods Max"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic:
            return "arrow.triangle.2.circlepath"
        case .airPods:
            return "airpods"
        case .airPodsPro:
            return "airpodspro"
        case .airPodsMax:
            return "airpods.max"
        }
    }

    var model: AirPodsModelKind? {
        switch self {
        case .automatic:
            return nil
        case .airPods:
            return .airPods
        case .airPodsPro:
            return .airPodsPro
        case .airPodsMax:
            return .airPodsMax
        }
    }
}

struct AirPods3DView: NSViewRepresentable {
    let model: AirPodsModelKind

    func makeNSView(context: Context) -> SCNView {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let pair = AirPods3DModel.makeRotatingModel(model)
        scene.rootNode.addChildNode(pair)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 0.64
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 20
        camera.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(camera)

        let target = SCNNode()
        scene.rootNode.addChildNode(target)
        let lookAt = SCNLookAtConstraint(target: target)
        lookAt.isGimbalLockEnabled = true
        camera.constraints = [lookAt]

        addLighting(to: scene)

        let view = SCNView()
        view.scene = scene
        view.pointOfView = camera
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {}

    private func addLighting(to scene: SCNScene) {
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1200
        key.light?.castsShadow = false
        key.eulerAngles = SCNVector3(-0.55, -0.65, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 420
        rim.light?.color = NSColor(
            calibratedRed: 0.72,
            green: 0.82,
            blue: 1,
            alpha: 1
        )
        rim.position = SCNVector3(3, 1.5, -2)
        scene.rootNode.addChildNode(rim)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 260
        scene.rootNode.addChildNode(ambient)
    }
}

private enum AirPods3DModel {
    private static let airPodsSource = loadSource(for: .airPods)
    private static let airPodsProSource = loadSource(for: .airPodsPro)
    private static let airPodsMaxSource = loadSource(for: .airPodsMax)

    private static func loadSource(
        for model: AirPodsModelKind
    ) -> SCNNode? {
        guard let url = Bundle.main.url(
            forResource: model.resourceName,
            withExtension: "usdz"
        ),
        let scene = try? SCNScene(url: url, options: nil) else {
            return nil
        }
        return scene.rootNode.childNode(
            withName: model.nodeName,
            recursively: true
        )
    }

    private static func source(
        for model: AirPodsModelKind
    ) -> SCNNode? {
        switch model {
        case .airPods:
            return airPodsSource
        case .airPodsPro:
            return airPodsProSource
        case .airPodsMax:
            return airPodsMaxSource
        }
    }

    static func makeRotatingModel(
        _ model: AirPodsModelKind
    ) -> SCNNode {
        let pair = SCNNode()
        guard let source = source(for: model) else { return pair }

        let earbuds = source.clone()
        guard let bounds = bounds(of: earbuds) else { return pair }

        let center = (bounds.minimum + bounds.maximum) * 0.5
        let size = bounds.maximum - bounds.minimum
        earbuds.position = SCNVector3(
            -center.x,
            -center.y,
            -center.z
        )

        let content = SCNNode()
        content.addChildNode(earbuds)
        let modelScale = model.targetExtent / max(size.x, size.y)
        content.scale = SCNVector3(modelScale, modelScale, modelScale)
        pair.addChildNode(content)

        let rotation = SCNAction.rotateBy(
            x: 0,
            y: 2 * CGFloat.pi,
            z: 0,
            duration: 6
        )
        rotation.timingMode = .linear
        pair.runAction(.repeatForever(rotation))
        return pair
    }

    private static func bounds(
        of node: SCNNode
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>)? {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var foundGeometry = false

        func visit(_ current: SCNNode) {
            if let geometry = current.geometry {
                foundGeometry = true
                let box = geometry.boundingBox
                for x in [box.min.x, box.max.x] {
                    for y in [box.min.y, box.max.y] {
                        for z in [box.min.z, box.max.z] {
                            let point = current.simdConvertPosition(
                                SIMD3<Float>(
                                    Float(x),
                                    Float(y),
                                    Float(z)
                                ),
                                to: node
                            )
                            minimum = SIMD3<Float>(
                                Swift.min(minimum.x, point.x),
                                Swift.min(minimum.y, point.y),
                                Swift.min(minimum.z, point.z)
                            )
                            maximum = SIMD3<Float>(
                                Swift.max(maximum.x, point.x),
                                Swift.max(maximum.y, point.y),
                                Swift.max(maximum.z, point.z)
                            )
                        }
                    }
                }
            }

            for child in current.childNodes {
                visit(child)
            }
        }

        visit(node)
        return foundGeometry ? (minimum, maximum) : nil
    }
}
