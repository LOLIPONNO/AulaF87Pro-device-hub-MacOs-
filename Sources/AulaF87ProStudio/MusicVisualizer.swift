import AVFoundation
import Foundation

final class MusicVisualizer: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var callback: (([Double]) -> Void)?
    private var smoothed = [Double](repeating: 0, count: 11)
    private var lastEmission = Date.distantPast
    private let lock = NSLock()
    private var hasTap = false
    private var demoTimer: Timer?
    private var demoPhase: Double = 0

    static func currentPermissionStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startMicrophone(callback: @escaping ([Double]) -> Void) throws {
        stop()
        self.callback = callback

        let newEngine = AVAudioEngine()
        self.engine = newEngine
        let input = newEngine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)
        let format = (hwFormat.channelCount > 0 && hwFormat.sampleRate > 0)
            ? hwFormat
            : input.outputFormat(forBus: 0)

        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw F87ProtocolError.transferFailed("사용 가능한 마이크 입력 장치를 찾을 수 없습니다.")
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer, sampleRate: format.sampleRate)
        }
        hasTap = true
        newEngine.prepare()
        try newEngine.start()
    }

    func startDemoWave(callback: @escaping ([Double]) -> Void) {
        stop()
        self.callback = callback
        demoPhase = 0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 14.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.demoPhase += 0.24
            var levels = [Double](repeating: 0, count: 11)
            for i in 0..<11 {
                let w1 = sin(self.demoPhase * 1.4 + Double(i) * 0.55) * 0.5 + 0.5
                let w2 = cos(self.demoPhase * 2.3 - Double(i) * 0.35) * 0.5 + 0.5
                levels[i] = max(0.08, min(1.0, (w1 * 0.65 + w2 * 0.35)))
            }
            self.callback?(levels)
        }
    }

    func stop() {
        demoTimer?.invalidate()
        demoTimer = nil
        if let engine {
            if hasTap {
                engine.inputNode.removeTap(onBus: 0)
                hasTap = false
            }
            if engine.isRunning {
                engine.stop()
            }
        }
        engine = nil
        callback = nil
        lock.lock()
        smoothed = [Double](repeating: 0, count: 11)
        lock.unlock()
    }

    private func process(buffer: AVAudioPCMBuffer, sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard Date().timeIntervalSince(lastEmission) >= 1.0 / 15.0,
              let channel = buffer.floatChannelData?[0] else { return }
        lastEmission = .now
        let count = min(Int(buffer.frameLength), 512)
        guard count > 64 else { return }

        // Compute overall RMS to gate background silence accurately
        var sumSq = 0.0
        for i in 0..<count {
            let s = Double(channel[i])
            sumSq += s * s
        }
        let rms = sqrt(sumSq / Double(count))
        if rms < 0.0008 {
            // Silence gate: decay existing bars smoothly to zero
            var quietLevels = [Double](repeating: 0, count: 11)
            for band in 0..<11 {
                smoothed[band] = smoothed[band] * 0.55
                if smoothed[band] < 0.02 { smoothed[band] = 0 }
                quietLevels[band] = smoothed[band]
            }
            callback?(quietLevels)
            return
        }

        // 11 logarithmic frequency bands from 65 Hz to 9500 Hz (3 sub-frequencies averaged per band)
        let bandCenters: [Double] = [75, 130, 220, 360, 600, 1000, 1650, 2700, 4300, 6800, 9500]
        let subOffsets: [Double] = [0.88, 1.0, 1.13]
        var levels = [Double](repeating: 0, count: 11)

        for band in 0..<11 {
            let center = min(bandCenters[band], sampleRate * 0.44)
            var bandPower = 0.0
            for mult in subOffsets {
                let freq = min(center * mult, sampleRate * 0.45)
                let omega = 2.0 * Double.pi * freq / sampleRate
                let coeff = 2.0 * cos(omega)
                var q1 = 0.0
                var q2 = 0.0
                for idx in 0..<count {
                    // Hann window to reduce spectral leakage
                    let w = 0.5 * (1.0 - cos(2.0 * Double.pi * Double(idx) / Double(count - 1)))
                    let sample = Double(channel[idx]) * w
                    let q0 = sample + coeff * q1 - q2
                    q2 = q1
                    q1 = q0
                }
                let magSq = max(1e-14, q1 * q1 + q2 * q2 - coeff * q1 * q2)
                bandPower += sqrt(magSq) / Double(count)
            }
            bandPower /= Double(subOffsets.count)
            // High-frequency compensation (voice/music naturally rolls off at higher frequencies)
            let tilt = 1.0 + Double(band) * 0.32
            let db = 20.0 * log10(max(1e-9, bandPower * tilt))
            // Map [-68 dB ... -18 dB] to [0.0 ... 1.0]
            let normalized = max(0.0, min(1.0, (db + 68.0) / 50.0))
            smoothed[band] = max(normalized, smoothed[band] * 0.65)
            levels[band] = smoothed[band]
        }
        callback?(levels)
    }
}
