import Foundation

enum F87ProtocolError: LocalizedError {
    case deviceNotFound
    case openFailed(String)
    case transferFailed(String)
    case timeout(String)
    case invalidConfig(String)
    case invalidMatrix(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "연결된 AULA F87 Pro 키보드를 찾을 수 없습니다. 2.4GHz 무선 리시버(3554:FA09) 또는 USB 케이블(258A:010C) 연결 상태를 확인하고 키를 한 번 눌러 절전 모드를 깨워주세요."
        case .openFailed(let detail):
            return "키보드 제어 인터페이스를 열 수 없습니다: \(detail)"
        case .transferFailed(let detail):
            return "키보드 통신 오류: \(detail)"
        case .timeout(let detail):
            return "키보드 응답 시간 초과: \(detail) (키보드가 절전 모드일 수 있으니 아무 키나 눌러 깨워주세요)"
        case .invalidConfig(let detail):
            return "키보드 설정 데이터 검증 실패: \(detail) (안전 보호를 위해 쓰기가 중단되었습니다)"
        case .invalidMatrix(let detail):
            return "키 매트릭스 데이터 검증 실패: \(detail)"
        }
    }
}

enum F87Protocol {
    static let wiredVID = 0x258A
    static let wiredPID = 0x010C
    static let wirelessVID = 0x3554
    static let wirelessPID = 0xFA09
    static let bluetoothPID = 0xFA07

    static let configLength = 128
    static let paletteLength = 512
    static let perKeyPlaneLength = 126
    static let perKeyLength = 378 // 3 * 126
    static let wirelessMatrixLength = 504 // 126 slots * 4 bytes
    static let wiredMatrixLength = 512    // 128 slots * 4 bytes

    // Config offsets (within 128-byte config block)
    static let offsetDebounce = 3         // 0..4 -> Stage 1..5
    static let offsetCustomPerKey = 9     // 1 when effect == 18 (Custom Per-Key), 0 otherwise
    static let offsetEffect = 10          // 0 = Off, 1..18
    static let offsetColorMode = 12       // 1 = palette/rainbow, 3 = factory default
    static let offsetSideLight = 18       // 0..4
    static let offsetTapSensitivity = 22  // 0 = off, 10..127
    static let offsetSleepSteps = 24      // 30-second steps (0 = never, 2 = 60s, 10 = 5m)
    static let offsetLightBar = 28        // 0..4
    static let offsetLightBarColor = 29   // 0..7
    static let colorfulSlot: UInt8 = 7

    // Healthy factory default 128-byte config captured from AULA F87 Pro V1
    static let factoryDefaultConfig: [UInt8] = [
        0x00, 0x03, 0x03, 0x02, 0x00, 0x00, 0x04, 0x04, 0x07, 0x00, 0x0B, 0x20, 0x01, 0x00, 0x01, 0x00,
        0x00, 0x00, 0x01, 0x00, 0x02, 0x01, 0x00, 0xFF, 0x0A, 0x00, 0x00, 0x00, 0x01, 0x00, 0x04, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37,
        0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37,
        0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37, 0x04, 0x37,
        0x04, 0x37, 0x07, 0x47, 0x07, 0x47, 0x07, 0x44, 0x07, 0x44, 0x07, 0x44, 0x07, 0x44, 0x07, 0x44,
        0x07, 0x44, 0x07, 0x44, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x5A, 0xA5
    ]

    static let standardSevenColors: [UInt8] = [
        0xFF, 0x00, 0x00, // Red
        0x00, 0xFF, 0x00, // Green
        0x00, 0x00, 0xFF, // Blue
        0xFF, 0xFF, 0x00, // Yellow
        0xFF, 0x00, 0xFF, // Magenta
        0x00, 0xFF, 0xFF, // Cyan
        0xFF, 0xFF, 0xFF  // White
    ]

    static func defaultPalette(customColor: RGBColor? = nil, forEffect targetEffect: Int? = nil) -> [UInt8] {
        var pal = [UInt8](repeating: 0, count: paletteLength)
        for effect in 1...17 {
            let base = 21 * effect
            for i in 0..<21 {
                pal[base + i] = standardSevenColors[i]
            }
            if let customColor, targetEffect == nil || targetEffect == effect {
                pal[base + 0] = customColor.red
                pal[base + 1] = customColor.green
                pal[base + 2] = customColor.blue
            }
        }
        pal[506] = 0x5A
        pal[507] = 0xA5
        return pal
    }

    static func effectParamOffset(_ effect: Int) -> Int {
        56 + 2 * effect
    }

    static func validateConfig(_ cfg: [UInt8]) -> Bool {
        guard cfg.count >= configLength else { return false }
        let fixedChecks: [(Int, UInt8)] = [
            (1, 0x03), (2, 0x03),
            (6, 0x04), (7, 0x04), (8, 0x07),
            (11, 0x20),
            (56, 0xFF), (57, 0xFF),
            (126, 0x5A), (127, 0xA5)
        ]
        for (offset, expected) in fixedChecks {
            if cfg[offset] != expected { return false }
        }
        for effect in 1...18 {
            let p = effectParamOffset(effect)
            let b = cfg[p]
            let s = cfg[p + 1] >> 4
            let c = cfg[p + 1] & 0x0F
            if b > 4 || s > 4 || c > 7 { return false }
        }
        return true
    }

    static func parseSnapshot(
        rawConfig: [UInt8],
        connectionMode: String,
        modelName: String,
        battery: BatteryStatus?
    ) -> HardwareSnapshot {
        let customFlag = rawConfig[offsetCustomPerKey] == 1
        let rawEffect = Int(rawConfig[offsetEffect])
        let effect = (customFlag && rawEffect == 18) ? 18 : rawEffect

        let paramIdx = (1...18).contains(rawEffect) ? effectParamOffset(rawEffect) : effectParamOffset(1)
        let brightness = Int(min(4, rawConfig[paramIdx]))
        let speedByte = rawConfig[paramIdx + 1]
        let speed = Int(min(4, speedByte >> 4))
        let colorSlot = Int(speedByte & 0x0F)
        let colorful = colorSlot >= Int(colorfulSlot)

        let sideLight = Int(min(4, rawConfig[offsetSideLight]))
        let lightBar = Int(min(4, rawConfig[offsetLightBar]))
        let sleepSteps = Int(rawConfig[offsetSleepSteps])
        let debounceStage = Int(min(4, rawConfig[offsetDebounce])) + 1
        let tap = Int(rawConfig[offsetTapSensitivity])

        return HardwareSnapshot(
            connectionMode: connectionMode,
            modelName: modelName,
            rawConfig: Array(rawConfig.prefix(configLength)),
            effect: effect,
            brightness: brightness,
            speed: speed,
            colorful: colorful,
            colorSlot: colorSlot,
            sideLightMode: sideLight,
            lightBarMode: lightBar,
            sleepRawSteps: sleepSteps,
            debounceStage: debounceStage,
            tapSensitivity: tap,
            battery: battery
        )
    }

    static func buildUpdatedConfig(
        base: [UInt8],
        effect: Int,
        brightness: Int,
        speed: Int,
        colorful: Bool,
        sideLightMode: Int,
        lightBarMode: Int? = nil,
        sleepRawSteps: Int? = nil,
        debounceStage: Int? = nil,
        tapSensitivity: Int? = nil
    ) throws -> [UInt8] {
        guard validateConfig(base) else {
            throw F87ProtocolError.invalidConfig("원본 설정 데이터가 유효하지 않습니다.")
        }
        var cfg = Array(base.prefix(configLength))

        let isCustomPerKey = (effect == LightingEffect.customPerKeyID)
        cfg[offsetCustomPerKey] = isCustomPerKey ? 1 : 0
        cfg[offsetEffect] = UInt8(max(0, min(18, effect)))
        cfg[offsetColorMode] = 1
        cfg[offsetSideLight] = UInt8(max(0, min(4, sideLightMode)))
        if sideLightMode > 0 && cfg[20] == 0 {
            cfg[20] = 2
        }

        if let lightBarMode {
            cfg[offsetLightBar] = UInt8(max(0, min(4, lightBarMode)))
            if lightBarMode > 0 && cfg[30] == 0 {
                cfg[30] = 4
            }
        }
        if let sleepRawSteps {
            cfg[offsetSleepSteps] = UInt8(max(0, min(240, sleepRawSteps)))
        }
        if let debounceStage {
            cfg[offsetDebounce] = UInt8(max(1, min(5, debounceStage)) - 1)
        }
        if let tapSensitivity {
            cfg[offsetTapSensitivity] = UInt8(max(0, min(127, tapSensitivity)))
        }

        if (1...18).contains(effect) {
            let p = effectParamOffset(effect)
            cfg[p] = UInt8(max(0, min(4, brightness)))
            let info = LightingEffect.info(for: effect)
            let spd = info.supportsSpeed ? UInt8(max(0, min(4, speed))) : (cfg[p + 1] >> 4)
            let slot: UInt8
            if isCustomPerKey {
                slot = cfg[p + 1] & 0x0F
            } else if info.supportsColor {
                slot = colorful ? colorfulSlot : 0
            } else {
                slot = colorfulSlot
            }
            cfg[p + 1] = (spd << 4) | slot
        }

        guard validateConfig(cfg) else {
            throw F87ProtocolError.invalidConfig("생성된 설정 블록이 하드웨어 검증 규칙을 통과하지 못했습니다.")
        }
        return cfg
    }

    static func encodePerKeyPlanes(colors: [Int: RGBColor]) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: perKeyLength)
        for (led, color) in colors where (0..<perKeyPlaneLength).contains(led) {
            data[led] = color.red
            data[perKeyPlaneLength + led] = color.green
            data[2 * perKeyPlaneLength + led] = color.blue
        }
        return data
    }

    static func defaultMatrix(forLayer layer: Int) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: wirelessMatrixLength)
        func set(_ slot: Int, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) {
            guard (0..<126).contains(slot) else { return }
            m[slot * 4] = b0
            m[slot * 4 + 1] = b1
            m[slot * 4 + 2] = b2
            m[slot * 4 + 3] = b3
        }
        if layer == 0 {
            let hidSlots: [(Int, UInt8)] = [
                (0, 0x29), (12, 0x3A), (18, 0x3B), (24, 0x3C), (30, 0x3D), (36, 0x3E), (42, 0x3F),
                (48, 0x40), (54, 0x41), (60, 0x42), (66, 0x43), (72, 0x44), (78, 0x45),
                (84, 0x46), (90, 0x47), (96, 0x48),
                (1, 0x35), (7, 0x1E), (13, 0x1F), (19, 0x20), (25, 0x21), (31, 0x22), (37, 0x23),
                (43, 0x24), (49, 0x25), (55, 0x26), (61, 0x27), (67, 0x2D), (73, 0x2E), (79, 0x2A),
                (85, 0x49), (91, 0x4A), (97, 0x4B),
                (2, 0x2B), (8, 0x14), (14, 0x1A), (20, 0x08), (26, 0x15), (32, 0x17), (38, 0x1C),
                (44, 0x18), (50, 0x0C), (56, 0x12), (62, 0x13), (68, 0x2F), (74, 0x30), (80, 0x31),
                (86, 0x4C), (92, 0x4D), (98, 0x4E),
                (3, 0x39), (9, 0x04), (15, 0x16), (21, 0x07), (27, 0x09), (33, 0x0A), (39, 0x0B),
                (45, 0x0D), (51, 0x0E), (57, 0x0F), (63, 0x33), (69, 0x34), (81, 0x28),
                (10, 0x1D), (16, 0x1B), (22, 0x06), (28, 0x19), (34, 0x05), (40, 0x11), (46, 0x10),
                (52, 0x36), (58, 0x37), (64, 0x38), (94, 0x52),
                (35, 0x2C), (65, 0x65), (89, 0x50), (95, 0x51), (101, 0x4F)
            ]
            for (slot, code) in hidSlots { set(slot, 0x00, 0x00, 0x00, code) }
            set(4, 0x00, 0x02, 0x00, 0x00)  // LShift
            set(82, 0x00, 0x20, 0x00, 0x00) // RShift
            set(5, 0x00, 0x01, 0x00, 0x00)  // LCtrl
            set(83, 0x00, 0x10, 0x00, 0x00) // RCtrl
            set(11, 0x00, 0x08, 0x00, 0x00) // LWin
            set(17, 0x00, 0x04, 0x00, 0x00) // LAlt
            set(53, 0x00, 0x40, 0x00, 0x00) // RAlt
            set(59, 0x0D, 0x00, 0x00, 0x00) // Fn
        } else if layer == 1 {
            set(0, 0x07, 0x00, 0x00, 0x04)  // Fn+Esc: Reset
            set(1, 0x07, 0x00, 0x00, 0x08)  // Fn+`: 2.4G
            set(7, 0x07, 0x00, 0x00, 0x05)  // Fn+1: BT1
            set(13, 0x07, 0x00, 0x00, 0x06) // Fn+2: BT2
            set(19, 0x07, 0x00, 0x00, 0x07) // Fn+3: BT3
            set(8, 0x07, 0x00, 0x00, 0x19)  // Fn+Q: Android
            set(14, 0x07, 0x00, 0x00, 0x18) // Fn+W: Windows
            set(20, 0x07, 0x00, 0x00, 0x1A) // Fn+E: Mac
            set(26, 0x07, 0x00, 0x00, 0x1B) // Fn+R: iOS
            set(34, 0x07, 0x00, 0x00, 0x0C) // Fn+B: Battery
            set(11, 0x07, 0x00, 0x00, 0x01) // Fn+Win: Win Lock
            set(85, 0x08, 0x00, 0x00, 0x00) // Fn+Ins: Effect cycle
            set(86, 0x08, 0x02, 0x00, 0x00) // Fn+Del: Color cycle
            set(94, 0x08, 0x03, 0x01, 0x00) // Fn+Up: Brightness +
            set(95, 0x08, 0x03, 0x02, 0x00) // Fn+Down: Brightness -
            set(89, 0x08, 0x04, 0x02, 0x00) // Fn+Left: Speed -
            set(101, 0x08, 0x04, 0x01, 0x00)// Fn+Right: Speed +
            set(82, 0x08, 0x00, 0x00, 0x01) // Fn+RShift: Side light
            set(4, 0x08, 0x00, 0x00, 0x02)  // Fn+LShift: Light bar
            set(12, 0x02, 0x00, 0x00, 0x70) // Fn+F1: Screen Brightness -
            set(18, 0x02, 0x00, 0x00, 0x6F) // Fn+F2: Screen Brightness +
            set(48, 0x02, 0x00, 0x00, 0xB6) // Fn+F7: Prev
            set(54, 0x02, 0x00, 0x00, 0xCD) // Fn+F8: Play/Pause
            set(60, 0x02, 0x00, 0x00, 0xB5) // Fn+F9: Next
            set(66, 0x02, 0x00, 0x00, 0xE2) // Fn+F10: Mute
            set(72, 0x02, 0x00, 0x00, 0xEA) // Fn+F11: Vol -
            set(78, 0x02, 0x00, 0x00, 0xE9) // Fn+F12: Vol +
            set(59, 0x0D, 0x00, 0x00, 0x00) // Fn
        }
        return m
    }

    // MARK: - 2.4GHz Wireless 20-byte Packet Framing (Report ID 0x13)

    static func checksum20(_ packet: [UInt8]) -> UInt8 {
        UInt8(packet.prefix(19).reduce(0) { ($0 + Int($1)) & 0xFF })
    }

    static func wirelessPacket(
        command: UInt8,
        subcommand: UInt8,
        sequence: UInt8,
        argument: UInt8 = 0,
        payload: [UInt8] = []
    ) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 20)
        packet[0] = 0x13
        packet[1] = command
        packet[2] = subcommand
        packet[3] = sequence
        for (idx, byte) in payload.prefix(15).enumerated() {
            packet[4 + idx] = byte
        }
        packet[19] = checksum20(packet)
        return packet
    }

    static func wirelessChunkedFrames(
        command: UInt8,
        subcommand: UInt8,
        argument: UInt8 = 0,
        body: [UInt8]
    ) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        let chunks = stride(from: 0, to: body.count, by: 14).map {
            Array(body[$0..<min($0 + 14, body.count)])
        }
        for (seq, chunk) in chunks.enumerated() {
            let lenByte = (argument << 4) | UInt8(chunk.count)
            frames.append(
                wirelessPacket(
                    command: command,
                    subcommand: subcommand,
                    sequence: UInt8(seq),
                    payload: [lenByte] + chunk
                )
            )
        }
        return frames
    }

    static func wirelessReadConfigRequest() -> [UInt8] {
        wirelessPacket(command: 0x44, subcommand: 0x01, sequence: 0)
    }

    static func wirelessBatteryRequest() -> [UInt8] {
        wirelessPacket(command: 0x4A, subcommand: 0x00, sequence: 0)
    }

    static func wirelessIdentityRequest() -> [UInt8] {
        wirelessPacket(command: 0x05, subcommand: 0x01, sequence: 0)
    }

    static func wirelessMatrixReadRequest(layer: UInt8) -> [UInt8] {
        wirelessPacket(command: 0x41, subcommand: 0x01, sequence: 0, payload: [layer << 4])
    }

    static func wirelessSavePacket() -> [UInt8] {
        wirelessPacket(command: 0x0A, subcommand: 0x01, sequence: 0, payload: [0x04, 0x07])
    }

    static func wirelessAudioFrames(colors: [Int: RGBColor], quantizeStep: Int = 32) -> [[UInt8]] {
        guard !colors.isEmpty else {
            return [wirelessPacket(command: 0x88, subcommand: 0x01, sequence: 0, payload: [0x23])]
        }
        var step = max(1, quantizeStep)
        var encoded: [UInt8] = []
        while true {
            var groups: [RGBColor: [UInt8]] = [:]
            for (led, c) in colors where (0..<perKeyPlaneLength).contains(led) && (c.red > 0 || c.green > 0 || c.blue > 0) {
                func q(_ v: UInt8) -> UInt8 {
                    UInt8(min(255, ((Int(v) + step / 2) / step) * step))
                }
                let qc = RGBColor(red: q(c.red), green: q(c.green), blue: q(c.blue))
                groups[qc, default: []].append(UInt8(led))
            }
            encoded.removeAll(keepingCapacity: true)
            for (rgb, leds) in groups.sorted(by: { $0.value.count > $1.value.count }) {
                let groupBytes = [rgb.red, rgb.green, rgb.blue, UInt8(leds.count)] + leds
                if encoded.count + groupBytes.count <= 196 {
                    encoded.append(contentsOf: groupBytes)
                }
            }
            if encoded.count <= 196 || step >= 128 { break }
            step *= 2
        }
        guard !encoded.isEmpty else {
            return [wirelessPacket(command: 0x88, subcommand: 0x01, sequence: 0, payload: [0x23])]
        }
        let chunks = stride(from: 0, to: encoded.count, by: 14).map {
            Array(encoded[$0..<min($0 + 14, encoded.count)])
        }.prefix(14)
        let total = UInt8(chunks.count)
        return chunks.enumerated().map { seq, chunk in
            wirelessPacket(
                command: 0x88,
                subcommand: total,
                sequence: UInt8(seq),
                payload: [UInt8(0x10 + chunk.count)] + chunk
            )
        }
    }

    // MARK: - USB Wired 520-byte Feature Report Framing (Report ID 0x06)

    static let wiredReportSize = 520

    static func wiredPacket(command: UInt8, subcommand: UInt8 = 0, payload: [UInt8] = [], explicitLength: Int? = nil) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: wiredReportSize)
        let length = explicitLength ?? payload.count
        buf[0] = 0x06
        buf[1] = command
        buf[2] = subcommand
        buf[3] = 0x00
        buf[4] = 0x01
        buf[5] = 0x00
        buf[6] = UInt8(length & 0xFF)
        buf[7] = UInt8((length >> 8) & 0xFF)
        for (i, b) in payload.prefix(512).enumerated() {
            buf[8 + i] = b
        }
        return buf
    }

    static func wiredLiveFrame(colors: [Int: RGBColor]) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: perKeyLength)
        for (led, c) in colors where (0..<122).contains(led) {
            payload[3 * led] = c.red
            payload[3 * led + 1] = c.green
            payload[3 * led + 2] = c.blue
        }
        return wiredPacket(command: 0x08, subcommand: 0x00, payload: payload, explicitLength: perKeyLength)
    }
}
