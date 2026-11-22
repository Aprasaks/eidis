import Foundation
import CoreGraphics
@main struct Smoke {
    @MainActor static func main() async {
        for (w,h): (CGFloat,CGFloat) in [(800,600),(1512,982),(1920,1080),(2560,1080),(3840,2160)] {
            let r=JarvisOverviewGeometry.coreFrame(width:w,height:h)
            precondition(abs(r.midX - w/2) < 0.01)
            let gap: CGFloat = w < 1120 ? 10 : 16
            let laneHeight = max(0, h - 116 - 12 - 52 - 66 - 2 * gap)
            let expectedY = 12 + 52 + 66 + 2 * gap + laneHeight/2
            precondition(abs(r.midY - expectedY) < 0.01)
            precondition(r.minX >= 0 && r.maxX <= w && r.minY >= 0 && r.maxY <= h)
            precondition(r.width > 0 && r.width == r.height)
            print("CORE",w,h,r)
        }
        let sampler=JarvisMacSampler()
        sampler.sample()
        precondition(sampler.current?.cpuPercent == nil)
        try? await Task.sleep(for: .seconds(1))
        sampler.sample()
        guard let s=sampler.current else { fatalError("sample") }
        precondition(s.cpuPercent.map { (0...100).contains($0) } == true)
        precondition(s.memoryBytes.map { $0 <= s.totalMemory } == true)
        precondition(s.diskAvailable != nil && s.diskTotal != nil)
        print("MAC CPU",s.cpuPercent ?? -1,"MEMORY BYTES",s.memoryBytes ?? 0,"RAM",s.totalMemory,"DISK FREE",s.diskAvailable ?? 0,"BATTERY",s.batteryPercent as Any,"POWER",s.powerSource)
        print("PASS")
    }
}
