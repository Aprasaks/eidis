import Foundation
import AVFoundation
@main struct VoiceIdentitySmoke {
    static func main() {
        let f=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let c=JarvisVoiceIDCapture(source:f)!
        for b in 0..<4 {
            let input=AVAudioPCMBuffer(pcmFormat:f,frameCapacity:1024)!
            input.frameLength=1024
            for i in 0..<1024 {
                input.floatChannelData![0][i]=Float(sin(Double(b*1024+i)*2*Double.pi*440/48000))*0.3
            }
            c.append(input)
        }
        let data=c.take()!
        precondition(data.count>2400 && data.count<2900 && data.count%2==0)
        precondition(data.contains{$0 != 0})
        precondition(c.take()==nil)
        let canceled=JarvisVoiceIDCapture(source:f)!
        canceled.discard()
        precondition(canceled.take()==nil)
        print("PASS: bounded command PCM capture, take once, discard")
    }
}
