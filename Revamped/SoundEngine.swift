import AVFoundation
import CoreHaptics
import UIKit

// MARK: - Synthesized UI Sound Engine
// Generates satisfying sounds programmatically — no audio files needed.
// Combines sine/noise oscillators with CoreHaptics for premium feel.

final class SoundEngine {
    static let shared = SoundEngine()

    private var audioEngine: AVAudioEngine?
    private var hapticEngine: CHHapticEngine?
    private let hapticSupported: Bool

    private init() {
        hapticSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        setupAudio()
        setupHaptics()
    }

    // MARK: - Setup

    private func setupAudio() {
        let engine = AVAudioEngine()
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        audioEngine = engine
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

    // MARK: - Sound: Whoosh (for transitions)
    // Filtered noise sweep — 150ms, frequency drops from high to low

    func playWhoosh() {
        playSynth(frequency: 800, endFrequency: 200, duration: 0.18, amplitude: 0.12, waveform: .noise)
        playHaptic(intensity: 0.4, sharpness: 0.3, duration: 0.15)
    }

    // MARK: - Sound: Pop (for text appearing)
    // Short sine burst — 80ms, bright and snappy

    func playPop() {
        playSynth(frequency: 1200, endFrequency: 900, duration: 0.08, amplitude: 0.15, waveform: .sine)
        playHaptic(intensity: 0.5, sharpness: 0.8, duration: 0.05)
    }

    // MARK: - Sound: Soft Ding (for arrival/completion)
    // Two-tone sine — 200ms, harmonic and warm

    func playDing() {
        playSynth(frequency: 880, endFrequency: 880, duration: 0.2, amplitude: 0.12, waveform: .sine)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.playSynth(frequency: 1320, endFrequency: 1320, duration: 0.15, amplitude: 0.08, waveform: .sine)
        }
        playHaptic(intensity: 0.6, sharpness: 0.5, duration: 0.2)
    }

    // MARK: - Sound: Swoosh (for globe zoom)
    // Rising tone — 250ms, builds energy

    func playSwoosh() {
        playSynth(frequency: 300, endFrequency: 900, duration: 0.25, amplitude: 0.1, waveform: .sine)
        playHaptic(intensity: 0.3, sharpness: 0.2, duration: 0.2)
    }

    // MARK: - Sound: Impact (for map landing)
    // Low thud + bright click — 120ms

    func playImpact() {
        playSynth(frequency: 120, endFrequency: 60, duration: 0.12, amplitude: 0.2, waveform: .sine)
        playSynth(frequency: 2000, endFrequency: 1500, duration: 0.04, amplitude: 0.08, waveform: .sine)
        playHaptic(intensity: 0.8, sharpness: 0.6, duration: 0.1)
    }

    // MARK: - Sound: Gradient reveal
    // Soft pad — 400ms, warm and ambient

    func playReveal() {
        playSynth(frequency: 440, endFrequency: 520, duration: 0.4, amplitude: 0.06, waveform: .sine)
        playSynth(frequency: 660, endFrequency: 780, duration: 0.35, amplitude: 0.04, waveform: .sine)
        playHaptic(intensity: 0.3, sharpness: 0.1, duration: 0.3)
    }

    // MARK: - Ambient Background Pad

    private var ambientNode: AVAudioSourceNode?
    private var ambientVolume: Float = 0

    /// Start a continuous ambient drone — warm evolving pad
    func startAmbient() {
        guard let engine = audioEngine, ambientNode == nil else { return }

        let sampleRate = Float(engine.outputNode.outputFormat(forBus: 0).sampleRate)
        guard sampleRate > 0 else { return }

        // Chord: C3(130.81) + E3(164.81) + G3(196.00) + C4(261.63)
        let baseFreqs: [Float] = [130.81, 164.81, 196.00, 261.63]
        var phases = [Float](repeating: 0, count: baseFreqs.count)
        var lfoPhase: Float = 0
        let targetVolume: Float = 0.035 // Very quiet background
        var fadeIn: Float = 0

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buf = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            let vol = self?.ambientVolume ?? 0

            for frame in 0..<Int(frameCount) {
                // Slow fade in
                fadeIn = min(fadeIn + 0.00001, 1.0)

                // LFO for gentle movement (0.05 Hz = 20 second cycle)
                lfoPhase += 0.05 / sampleRate
                if lfoPhase > 1 { lfoPhase -= 1 }
                let lfo = sin(lfoPhase * 2 * .pi)

                // Sum chord tones with slight detuning from LFO
                var sample: Float = 0
                for i in 0..<baseFreqs.count {
                    let detune: Float = 1.0 + lfo * 0.002 * Float(i) // Slight chorus
                    let freq = baseFreqs[i] * detune
                    phases[i] += freq / sampleRate
                    if phases[i] > 1 { phases[i] -= 1 }
                    sample += sin(phases[i] * 2 * .pi)
                }

                // Normalize, apply volume + fade
                sample = sample / Float(baseFreqs.count) * vol * fadeIn

                buf[frame] = sample
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: engine.outputNode.outputFormat(forBus: 0))

        do {
            if !engine.isRunning { try engine.start() }
        } catch { return }

        ambientNode = node
        ambientVolume = targetVolume
    }

    /// Fade out and stop ambient
    func stopAmbient() {
        ambientVolume = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let node = self?.ambientNode {
                self?.audioEngine?.detach(node)
                self?.ambientNode = nil
            }
        }
    }

    // MARK: - Synth Engine

    private enum Waveform { case sine, noise }

    private func playSynth(frequency: Float, endFrequency: Float, duration: Double,
                            amplitude: Float, waveform: Waveform) {
        guard let engine = audioEngine else { return }

        let sampleRate = Float(engine.outputNode.outputFormat(forBus: 0).sampleRate)
        guard sampleRate > 0 else { return }

        var phase: Float = 0
        let totalSamples = Int(Double(sampleRate) * duration)
        var currentSample = 0

        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                guard currentSample < totalSamples else {
                    if let buf = buffers.first?.mData?.assumingMemoryBound(to: Float.self) {
                        buf[frame] = 0
                    }
                    continue
                }

                let progress = Float(currentSample) / Float(totalSamples)
                let freq = frequency + (endFrequency - frequency) * progress

                // Exponential amplitude envelope: sharp attack, smooth decay
                let envelope = amplitude * (1.0 - progress) * (1.0 - progress)

                let sample: Float
                switch waveform {
                case .sine:
                    sample = sin(phase * 2.0 * .pi) * envelope
                case .noise:
                    let noise = Float.random(in: -1...1)
                    let sine = sin(phase * 2.0 * .pi)
                    sample = (noise * 0.3 + sine * 0.7) * envelope
                }

                phase += freq / sampleRate
                if phase > 1.0 { phase -= 1.0 }

                if let buf = buffers.first?.mData?.assumingMemoryBound(to: Float.self) {
                    buf[frame] = sample
                }
                currentSample += 1
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode,
                       format: engine.outputNode.outputFormat(forBus: 0))

        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch { return }

        // Auto-detach after sound completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak engine] in
            engine?.detach(sourceNode)
        }
    }

    // MARK: - Haptics

    private func playHaptic(intensity: Float, sharpness: Float, duration: Double) {
        guard hapticSupported, let engine = hapticEngine else { return }

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0,
            duration: duration
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }
}
