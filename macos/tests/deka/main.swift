import Foundation
import AVFoundation
@main struct Test {
    static func main() throws {
        let pipe=Pipe()
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let relay=DekaPCMRelay(handle:pipe.fileHandleForWriting,source:format){fatalError("relay failure")}
        precondition(relay != nil)
        for b in 0..<4 {
            let input=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024)!
            input.frameLength=1024
            for i in 0..<1024 {input.floatChannelData![0][i]=Float(sin(Double(b*1024+i)*2*Double.pi*440/48000))*0.3}
            relay!.append(input)
        }
        relay!.close()
        let data=pipe.fileHandleForReading.readDataToEndOfFile()
        precondition(data.count>2400 && data.count<2900 && data.count%2==0)
        precondition(data.contains{$0 != 0})
        relay!.close()
        print("PASS: 48kHz floating point audio converted to 16kHz PCM; \(data.count) bytes, idempotent close. No microphone.")
    }
}
