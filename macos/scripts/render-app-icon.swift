import AppKit
let sourcePath=CommandLine.arguments[1]
let outputPath=CommandLine.arguments[2]
let dimension=1024
guard let source=NSImage(contentsOfFile:sourcePath),
      let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:dimension,pixelsHigh:dimension,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
      let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else {
    fputs("Unable to load icon source or create bitmap\n",stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=graphics
graphics.imageInterpolation = .high
let rect=NSRect(x:0,y:0,width:dimension,height:dimension)
NSColor.clear.set()
rect.fill()
NSBezierPath(roundedRect:rect.insetBy(dx:5,dy:5),xRadius:162,yRadius:162).addClip()
source.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1)
graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
// The original artwork has a white presentation canvas outside its dark
// rounded-square body. Remove only near-white fringe pixels near the exterior,
// leaving the bright golden core and all inner details intact.
if let bytes=bitmap.bitmapData {
    let row=bitmap.bytesPerRow
    let pixelSize=bitmap.bitsPerPixel/8
    guard pixelSize==4 else { fputs("Unexpected pixel size\n",stderr); exit(3) }
    for y in 0..<dimension {
        for x in 0..<dimension {
            if min(x,y,dimension-1-x,dimension-1-y) >= 160 { continue }
            let offset=y*row+x*pixelSize
            let r=bytes[offset], g=bytes[offset+1], b=bytes[offset+2]
            // Clear neutral white/gray presentation fringe, not amber light.
            if r>120 && g>120 && b>120 &&
               abs(Int(r)-Int(g)) < 17 && abs(Int(r)-Int(b)) < 17 {
                bytes[offset]=0;bytes[offset+1]=0;bytes[offset+2]=0;bytes[offset+3]=0
            }
        }
    }
}
guard let png=bitmap.representation(using:.png,properties:[:]) else {
    fputs("Failed to encode PNG\n",stderr)
    exit(2)
}
try png.write(to:URL(fileURLWithPath:outputPath))
print("ICON_MASTER_BYTES=\(png.count)")
