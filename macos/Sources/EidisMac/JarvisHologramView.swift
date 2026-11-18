import AppKit
import SceneKit
import SwiftUI

/// Native, continuously rotating 3D ornament. No microphone or network access.
/// Scene motion is suspended when the window is inactive or Reduce Motion is on.
struct JarvisHologramView: NSViewRepresentable {
    let animated: Bool

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = Self.makeScene()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling4X
        view.isPlaying = animated
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.isPlaying = animated
    }

    private static func material(_ color: NSColor, alpha: CGFloat = 1) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = color.withAlphaComponent(alpha)
        result.emission.contents = color.withAlphaComponent(alpha)
        result.lightingModel = .constant
        result.blendMode = .add
        result.isDoubleSided = true
        result.writesToDepthBuffer = false
        return result
    }

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let gold = NSColor(calibratedRed: 1.0, green: 0.59, blue: 0.18, alpha: 1)
        let pale = NSColor(calibratedRed: 1.0, green: 0.83, blue: 0.50, alpha: 1)
        let faint = NSColor(calibratedRed: 0.69, green: 0.32, blue: 0.08, alpha: 1)

        let root = SCNNode()
        scene.rootNode.addChildNode(root)
        let shell = SCNSphere(radius: 1.22)
        shell.segmentCount = 36
        let wires = material(gold, alpha: 0.12)
        wires.fillMode = .lines
        shell.materials = [wires]
        let sphere = SCNNode(geometry: shell)
        root.addChildNode(sphere)

        for i in 0..<8 {
            let radius: CGFloat = 0.48 + CGFloat(i) * 0.135
            let torus = SCNTorus(ringRadius: radius, pipeRadius: i.isMultiple(of: 3) ? 0.009 : 0.004)
            torus.ringSegmentCount = 100
            torus.pipeSegmentCount = 6
            torus.materials = [material(i.isMultiple(of: 3) ? pale : gold,
                                        alpha: i.isMultiple(of: 3) ? 0.92 : 0.56)]
            let pivot = SCNNode()
            let orbit = SCNNode(geometry: torus)
            pivot.addChildNode(orbit)
            pivot.eulerAngles = SCNVector3(Float(i) * 0.34, Float(i) * 0.51, Float(i) * 0.24)
            pivot.runAction(.repeatForever(.rotateBy(x: CGFloat(i.isMultiple(of: 2) ? 2 * Double.pi : -2 * Double.pi),
                                                     y: CGFloat((i + 1).isMultiple(of: 2) ? 2 * Double.pi : -2 * Double.pi),
                                                     z: 0, duration: 19 + Double(i) * 3)))
            root.addChildNode(pivot)
        }

        // Orbiting dotted details give the core depth without image/video assets.
        for i in 0..<96 {
            let angle = Double(i) * 2 * Double.pi / 96
            let latitude = asin(2 * (Double((i * 37) % 97) / 97) - 1)
            let radius = 1.38 + Double(i % 6) * 0.025
            let dot = SCNSphere(radius: i.isMultiple(of: 11) ? 0.012 : 0.004)
            dot.segmentCount = 5
            dot.materials = [material(i.isMultiple(of: 11) ? pale : faint, alpha: 0.74)]
            let node = SCNNode(geometry: dot)
            node.position = SCNVector3(radius * cos(latitude) * cos(angle),
                                       radius * sin(latitude),
                                       radius * cos(latitude) * sin(angle))
            root.addChildNode(node)
        }

        let center = SCNSphere(radius: 0.16)
        center.segmentCount = 32
        center.materials = [material(pale)]
        root.addChildNode(SCNNode(geometry: center))
        root.runAction(.repeatForever(.rotateBy(x: 0.24, y: CGFloat(Double.pi * 2), z: 0.18, duration: 38)))

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 44
        camera.camera?.zNear = 0.1
        camera.position = SCNVector3(0, 0.0, 5.5)
        scene.rootNode.addChildNode(camera)
        scene.physicsWorld.speed = 0
        return scene
    }
}
