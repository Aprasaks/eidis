import AppKit
import SceneKit
import SwiftUI

/// Layered kinetic hologram. This is a rendered 3D object, not an image or an active microphone.
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

    private static let amber = NSColor(calibratedRed: 1.0, green: 0.49, blue: 0.09, alpha: 1)
    private static let bright = NSColor(calibratedRed: 1.0, green: 0.77, blue: 0.37, alpha: 1)
    private static let copper = NSColor(calibratedRed: 0.66, green: 0.28, blue: 0.045, alpha: 1)

    private static func glow(_ color: NSColor, alpha: CGFloat = 1) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color.withAlphaComponent(alpha)
        material.emission.contents = color.withAlphaComponent(alpha)
        material.lightingModel = .constant
        material.blendMode = .add
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        return material
    }

    /// A genuine curved 3D strip, not the triangular wire mesh of the previous version.
    private static func arc(radius: Double, width: Double, start: Double,
                            sweep: Double, material: SCNMaterial) -> SCNNode {
        let steps = max(8, Int(abs(sweep) * 42))
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for i in 0...steps {
            let angle = start + sweep * Double(i) / Double(steps)
            let c = cos(angle)
            let s = sin(angle)
            vertices.append(SCNVector3((radius - width / 2) * c, (radius - width / 2) * s, 0))
            vertices.append(SCNVector3((radius + width / 2) * c, (radius + width / 2) * s, 0))
            if i < steps {
                let k = Int32(i * 2)
                indices += [k, k + 1, k + 2, k + 1, k + 3, k + 2]
            }
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private static func ring(radius: CGFloat, thickness: CGFloat, material: SCNMaterial) -> SCNNode {
        let geometry = SCNTorus(ringRadius: radius, pipeRadius: thickness)
        geometry.ringSegmentCount = 128
        geometry.pipeSegmentCount = 7
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private static func spin(_ node: SCNNode, duration: Double, reversed: Bool = false) {
        node.runAction(.repeatForever(.rotateBy(x: 0, y: 0,
            z: reversed ? -CGFloat.pi * 2 : CGFloat.pi * 2, duration: duration)))
    }

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let assembly = SCNNode()
        scene.rootNode.addChildNode(assembly)

        // Three independently revolving instruments, tilted in depth like a gyroscope.
        let tilts: [(Float, Float, Float, Double)] = [
            (0.12, 0.13, 0.0, 47), (0.49, -0.34, 0.36, 34), (-0.40, 0.46, -0.24, 59)
        ]
        for (layer, tilt) in tilts.enumerated() {
            let pivot = SCNNode()
            pivot.eulerAngles = SCNVector3(tilt.0, tilt.1, tilt.2)
            assembly.addChildNode(pivot)
            let base = 1.0 + Double(layer) * 0.10
            pivot.addChildNode(ring(radius: CGFloat(base), thickness: 0.004,
                                    material: glow(copper, alpha: 0.65)))
            for piece in 0..<10 {
                let start = Double(piece) * 2 * .pi / 10 + Double(layer) * 0.17
                let gap = piece.isMultiple(of: 3) ? 0.33 : 0.11
                let sweep = 2 * Double.pi / 10 - gap
                let width = piece.isMultiple(of: 4) ? 0.072 : (piece.isMultiple(of: 2) ? 0.035 : 0.012)
                let color = piece.isMultiple(of: 4) ? bright : amber
                pivot.addChildNode(arc(radius: base + (piece.isMultiple(of: 2) ? 0.025 : -0.02),
                                       width: width, start: start, sweep: sweep,
                                       material: glow(color, alpha: piece.isMultiple(of: 4) ? 0.84 : 0.53)))
            }
            spin(pivot, duration: tilt.3, reversed: layer == 1)
        }

        // Densely layered front-facing schematics. These retain their circular silhouette
        // throughout rotation instead of turning into a thin wireframe seen edge-on.
        let instrument = SCNNode()
        instrument.eulerAngles = SCNVector3(0.08, -0.10, 0)
        assembly.addChildNode(instrument)
        for band in 0..<15 {
            let layer = SCNNode()
            let radius = 0.28 + Double(band) * 0.067
            layer.position.z = Double(band % 5) * 0.028 - 0.055
            for piece in 0..<32 {
                let angle = Double(piece) * 2 * Double.pi / 32 + Double(band) * 0.13
                // Circuit-like calibration arcs at three different scales.
                let gap = piece.isMultiple(of: 5) ? 0.065 : 0.021
                let sweep = 2 * Double.pi / 32 - gap
                if piece % 6 != band % 6 {
                    let wide = (band + piece).isMultiple(of: 11)
                    layer.addChildNode(arc(radius: radius, width: wide ? 0.022 : 0.0045,
                        start: angle, sweep: sweep,
                        material: glow(wide ? bright : (band.isMultiple(of: 3) ? amber : copper),
                                       alpha: wide ? 0.76 : 0.45)))
                }
            }
            spin(layer, duration: 28 + Double(band) * 3.7, reversed: band.isMultiple(of: 2))
            instrument.addChildNode(layer)
        }
        for spoke in 0..<64 {
            let a = Double(spoke) * 2 * Double.pi / 64
            let tick = arc(radius: 1.27, width: spoke.isMultiple(of: 8) ? 0.070 : 0.028,
                           start: a, sweep: 0.012,
                           material: glow(spoke.isMultiple(of: 8) ? bright : amber,
                                          alpha: spoke.isMultiple(of: 8) ? 0.88 : 0.37))
            instrument.addChildNode(tick)
        }
        spin(instrument, duration: 98)

        // Nested inner mechanism: concentric discontinuous bearings and fine calibration traces.
        let inner = SCNNode()
        inner.eulerAngles = SCNVector3(0.18, 0.24, 0)
        assembly.addChildNode(inner)
        for level in 0..<8 {
            let radius = 0.24 + Double(level) * 0.073
            let section = SCNNode()
            for piece in 0..<12 {
                let start = Double(piece) * Double.pi / 6 + Double(level) * 0.20
                section.addChildNode(arc(radius: radius, width: level.isMultiple(of: 3) ? 0.025 : 0.007,
                                         start: start, sweep: piece.isMultiple(of: 4) ? 0.26 : 0.43,
                                         material: glow(level.isMultiple(of: 3) ? bright : amber,
                                                        alpha: level.isMultiple(of: 3) ? 0.92 : 0.55)))
            }
            spin(section, duration: 18 + Double(level) * 3.5, reversed: level.isMultiple(of: 2))
            inner.addChildNode(section)
        }

        // Sparse illuminated sensor markers: enough texture to suggest circuitry, not a wire ball.
        let markers = SCNNode()
        for index in 0..<84 {
            let angle = Double(index) * 2 * Double.pi / 84
            let radius = 1.17 + Double(index % 5) * 0.055
            let marker = SCNSphere(radius: index.isMultiple(of: 13) ? 0.010 : 0.003)
            marker.segmentCount = 6
            marker.materials = [glow(index.isMultiple(of: 13) ? bright : amber,
                                     alpha: index.isMultiple(of: 13) ? 0.88 : 0.42)]
            let point = SCNNode(geometry: marker)
            point.position = SCNVector3(radius * cos(angle), radius * sin(angle),
                                        Double((index * 17) % 19 - 9) * 0.025)
            markers.addChildNode(point)
        }
        markers.eulerAngles = SCNVector3(0.48, 0.66, 0.05)
        spin(markers, duration: 61, reversed: true)
        assembly.addChildNode(markers)

        // A small intricate luminous aperture, rather than a solid white sphere.
        let aperture = SCNNode()
        aperture.addChildNode(ring(radius: 0.16, thickness: 0.010, material: glow(bright)))
        aperture.addChildNode(ring(radius: 0.105, thickness: 0.004, material: glow(amber)))
        aperture.addChildNode(ring(radius: 0.044, thickness: 0.006, material: glow(bright)))
        let lens = SCNSphere(radius: 0.028)
        lens.segmentCount = 24
        lens.materials = [glow(amber, alpha: 0.76)]
        aperture.addChildNode(SCNNode(geometry: lens))
        aperture.position.z = 0.12
        assembly.addChildNode(aperture)
        // Keep the primary ring stack facing the viewer, while individual parts orbit in 3D.
        spin(assembly, duration: 118)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.camera?.zNear = 0.1
        camera.position = SCNVector3(0, 0.0, 5.2)
        scene.rootNode.addChildNode(camera)
        return scene
    }
}
