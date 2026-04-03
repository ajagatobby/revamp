import AVFoundation
import CoreHaptics

// MARK: - Synthesized UI Sound Engine

final class SoundEngine {
    static let shared = SoundEngine()

    private var audioEngine: AVAudioEngine?
    private var hapticEngine: CHHapticEngine?
    private let hapticSupported: Bool
    private var isAudioReady = false
    private var mixerFormat: AVAudioFormat?

    private init() {
        hapticSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        setupAudio()
        setupHaptics()
    }

    // MARK: - Setup

    private func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)

            let engine = AVAudioEngine()
            // Get the mixer format — this is what we must match
            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0 && format.channelCount > 0 else { return }

            mixerFormat = format
            audioEngine = engine
            try engine.start()
            isAudioReady = true
        } catch {
            isAudioReady = false
        }
    }

    private func setupHaptics() {
        guard hapticSupported else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            try engine.start()
            hapticEngine = engine
        } catch {}
    }

    // MARK: - Sounds

    func playWhoosh() {
        playSynth(freq: 800, endFreq: 200, dur: 0.18, amp: 0.12, noise: true)
        playHaptic(intensity: 0.4, sharpness: 0.3)
    }

    func playPop() {
        playSynth(freq: 1200, endFreq: 900, dur: 0.08, amp: 0.15, noise: false)
        playHaptic(intensity: 0.5, sharpness: 0.8)
    }

    func playDing() {
        playSynth(freq: 880, endFreq: 880, dur: 0.2, amp: 0.12, noise: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.playSynth(freq: 1320, endFreq: 1320, dur: 0.15, amp: 0.08, noise: false)
        }
        playHaptic(intensity: 0.6, sharpness: 0.5)
    }

    func playSwoosh() {
        playSynth(freq: 300, endFreq: 900, dur: 0.25, amp: 0.1, noise: false)
        playHaptic(intensity: 0.3, sharpness: 0.2)
    }

    func playImpact() {
        playSynth(freq: 120, endFreq: 60, dur: 0.12, amp: 0.2, noise: false)
        playSynth(freq: 2000, endFreq: 1500, dur: 0.04, amp: 0.08, noise: false)
        playHaptic(intensity: 0.8, sharpness: 0.6)
    }

    func playReveal() {
        playSynth(freq: 440, endFreq: 520, dur: 0.4, amp: 0.06, noise: false)
        playSynth(freq: 660, endFreq: 780, dur: 0.35, amp: 0.04, noise: false)
        playHaptic(intensity: 0.3, sharpness: 0.1)
    }

    // MARK: - Ambient Background

    private var ambientNode: AVAudioSourceNode?
    private var ambientVolume: Float = 0

    func startAmbient() {
        guard isAudioReady, let engine = audioEngine, let format = mixerFormat,
              ambientNode == nil else { return }

        let sr = Float(format.sampleRate)
        guard sr > 0 else { return }

        let freqs: [Float] = [130.81, 164.81, 196.00, 261.63]
        var phases = [Float](repeating: 0, count: freqs.count)
        var lfoPhase: Float = 0
        var fadeIn: Float = 0

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let vol = self?.ambientVolume ?? 0
            let chCount = Int(format.channelCount)

            for frame in 0..<Int(frameCount) {
                fadeIn = min(fadeIn + 0.00001, 1.0)
                lfoPhase += 0.05 / sr
                if lfoPhase > 1 { lfoPhase -= 1 }
                let lfo = sin(lfoPhase * 2 * .pi)

                var sample: Float = 0
                for i in 0..<freqs.count {
                    let f = freqs[i] * (1.0 + lfo * 0.002 * Float(i))
                    phases[i] += f / sr
                    if phases[i] > 1 { phases[i] -= 1 }
                    sample += sin(phases[i] * 2 * .pi)
                }
                sample = sample / Float(freqs.count) * vol * fadeIn

                for ch in 0..<chCount {
                    if let buf = buffers[ch].mData?.assumingMemoryBound(to: Float.self) {
                        buf[frame] = sample
                    }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }

        ambientNode = node
        ambientVolume = 0.035
    }

    func stopAmbient() {
        ambientVolume = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let node = self.ambientNode else { return }
            self.audioEngine?.detach(node)
            self.ambientNode = nil
        }
    }

    // MARK: - Synth Core

    private func playSynth(freq: Float, endFreq: Float, dur: Double, amp: Float, noise: Bool) {
        guard isAudioReady, let engine = audioEngine, let format = mixerFormat else { return }

        let sr = Float(format.sampleRate)
        guard sr > 0 else { return }

        let totalSamples = Int(Double(sr) * dur)
        var phase: Float = 0
        var currentSample = 0
        let chCount = Int(format.channelCount)

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                let sample: Float
                if currentSample < totalSamples {
                    let progress = Float(currentSample) / Float(totalSamples)
                    let f = freq + (endFreq - freq) * progress
                    let envelope = amp * (1.0 - progress) * (1.0 - progress)

                    if noise {
                        let n = Float.random(in: -1...1)
                        sample = (n * 0.3 + sin(phase * 2 * .pi) * 0.7) * envelope
                    } else {
                        sample = sin(phase * 2 * .pi) * envelope
                    }

                    phase += f / sr
                    if phase > 1 { phase -= 1 }
                    currentSample += 1
                } else {
                    sample = 0
                }

                for ch in 0..<chCount {
                    if let buf = buffers[ch].mData?.assumingMemoryBound(to: Float.self) {
                        buf[frame] = sample
                    }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.1) { [weak engine] in
            engine?.detach(node)
        }
    }

    // MARK: - Haptics

    private func playHaptic(intensity: Float, sharpness: Float) {
        guard hapticSupported, let engine = hapticEngine else { return }

        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0
            )
            let player = try engine.makePlayer(with: try CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }
}
