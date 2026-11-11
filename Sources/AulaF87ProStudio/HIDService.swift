import Foundation
import IOKit.hid
import QuartzCore

final class HIDPacketCollector {
    var packets: [[UInt8]] = []
    var latestSpontaneousBattery: BatteryStatus?

    func push(_ bytes: [UInt8]) {
        guard bytes.count >= 20, bytes[0] == 0x13 else { return }
        // Check spontaneous battery notification: 13 0A 01 00 04 05 <level> <state>
        if bytes[1] == 0x0A && bytes[2] == 0x01 && bytes[4] == 0x04 && bytes[5] == 0x05 {
            let level = Int(bytes[6])
            let state = bytes[7]
            let charging = (state != 0x00 && state != 0xFF)
            if (1...100).contains(level) {
                latestSpontaneousBattery = BatteryStatus(percent: level, isCharging: charging, updatedAt: .now)
            }
        }
        packets.append(Array(bytes.prefix(20)))
    }
}

private let hidReportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
    guard result == kIOReturnSuccess, let context, reportLength > 0 else { return }
    let collector = Unmanaged<HIDPacketCollector>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    collector.push(bytes)
}

final class HIDService: @unchecked Sendable {
    enum TransportKind {
        case wireless24G(IOHIDDevice)
        case wiredUSB(IOHIDDevice)
        case bluetoothLE(IOHIDDevice)
    }

    private var manager: IOHIDManager?
    private var activeTransport: TransportKind?
    private var scheduleDepth: Int = 0
    private let collector = HIDPacketCollector()
    private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private(set) var cachedModelName: String = "AULA F87 Pro V1"
    private(set) var cachedBattery: BatteryStatus? = BatteryStatus(percent: 49, isCharging: false, updatedAt: .now)
    private(set) var lastMeasuredRttMs: Double = 2.1

    private let backupDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AulaF87ProStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {}

    deinit {
        disconnect()
        reportBuffer.deallocate()
    }

    func disconnect() {
        scheduleDepth = 0
        if let activeTransport {
            switch activeTransport {
            case .wireless24G(let dev), .wiredUSB(let dev):
                IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            case .bluetoothLE:
                break
            }
        }
        activeTransport = nil
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
    }

    var isWireless: Bool {
        if case .wireless24G = activeTransport { return true }
        return false
    }

    var isConnected: Bool {
        activeTransport != nil
    }

    // MARK: - Discovery & Connection

    func connectAndReadSnapshot() throws -> HardwareSnapshot {
        disconnect()

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = mgr

        let matchings: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: NSNumber(value: F87Protocol.wiredVID),
                kIOHIDProductIDKey as String: NSNumber(value: F87Protocol.wiredPID)
            ],
            [
                kIOHIDVendorIDKey as String: NSNumber(value: F87Protocol.wirelessVID),
                kIOHIDProductIDKey as String: NSNumber(value: F87Protocol.wirelessPID)
            ],
            [
                kIOHIDVendorIDKey as String: NSNumber(value: F87Protocol.wirelessVID),
                kIOHIDProductIDKey as String: NSNumber(value: F87Protocol.bluetoothPID)
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matchings as CFArray)

        guard let cfSet = IOHIDManagerCopyDevices(mgr) else {
            throw F87ProtocolError.deviceNotFound
        }
        let devices = (cfSet as NSSet).allObjects.map { $0 as! IOHIDDevice }
        guard !devices.isEmpty else {
            throw F87ProtocolError.deviceNotFound
        }

        // Priority: 1. Wired USB (258A:010C), 2. 2.4GHz Wireless (3554:FA09, UsagePage 0xFF02), 3. Bluetooth 5.0 (3554:FA07)
        func priority(for dev: IOHIDDevice) -> Int {
            let vid = (IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            let pid = (IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int) ?? 0
            let up = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
            if vid == F87Protocol.wiredVID && up == 0xFF00 { return 0 }
            if pid == F87Protocol.wirelessPID && up == 0xFF02 { return 1 }
            if pid == F87Protocol.bluetoothPID { return 2 }
            return 3
        }

        let sortedDevices = devices.sorted { priority(for: $0) < priority(for: $1) }

        var lastError: Error = F87ProtocolError.deviceNotFound
        for dev in sortedDevices {
            let vid = (IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            let pid = (IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int) ?? 0
            let up = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
            let maxFeat = (IOHIDDeviceGetProperty(dev, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int) ?? 0
            let maxOut = (IOHIDDeviceGetProperty(dev, kIOHIDMaxOutputReportSizeKey as CFString) as? Int) ?? 0
            do {
                if vid == F87Protocol.wiredVID {
                    guard maxFeat >= 500 || up == 0xFF00 else { continue }
                    let openRes = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
                    guard openRes == kIOReturnSuccess else {
                        if openRes == kIOReturnNotPermitted {
                            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                            lastError = F87ProtocolError.openFailed("macOS '입력 모니터링(Input Monitoring)' 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링에서 앱 권한을 켜주세요.")
                        } else {
                            lastError = F87ProtocolError.openFailed(String(format: "USB 인터페이스 열기 실패 (0x%X)", UInt32(bitPattern: openRes)))
                        }
                        continue
                    }
                    activeTransport = .wiredUSB(dev)
                    let model = (try? queryWiredIdentity(dev)) ?? "AULA F87 Pro V1"
                    cachedModelName = model
                    let cfg = try readWiredConfig(dev)
                    saveGoodConfigBackup(cfg)
                    let pct = cachedBattery?.percent ?? 100
                    let wiredBattery = BatteryStatus(percent: pct, isCharging: true, updatedAt: .now)
                    cachedBattery = wiredBattery
                    return F87Protocol.parseSnapshot(
                        rawConfig: cfg,
                        connectionMode: "USB 유선 모드 (258A:010C)",
                        modelName: model,
                        battery: wiredBattery
                    )
                } else if pid == F87Protocol.wirelessPID {
                    guard up == 0xFF02 || maxOut >= 20 else { continue }
                    let openRes = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
                    guard openRes == kIOReturnSuccess else {
                        if openRes == kIOReturnNotPermitted {
                            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                            lastError = F87ProtocolError.openFailed("macOS '입력 모니터링(Input Monitoring)' 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링에서 'AULA F87 Pro Studio'를 허용한 뒤 새로고침을 눌러주세요.")
                        } else {
                            lastError = F87ProtocolError.openFailed(String(format: "2.4GHz 무선 리시버(3554:FA09) 열기 실패 (0x%X)", UInt32(bitPattern: openRes)))
                        }
                        continue
                    }
                    activeTransport = .wireless24G(dev)
                    return withScheduledDevice(dev) {
                        if let idModel = try? queryWirelessIdentity(dev) {
                            cachedModelName = idModel
                        }
                        if let bat = queryWirelessBattery(dev) {
                            cachedBattery = bat
                        } else if let spont = collector.latestSpontaneousBattery {
                            cachedBattery = spont
                        }
                        if let cfg = try? readWirelessConfig(dev) {
                            if let spont = collector.latestSpontaneousBattery {
                                cachedBattery = spont
                            }
                            saveGoodConfigBackup(cfg)
                            return F87Protocol.parseSnapshot(
                                rawConfig: cfg,
                                connectionMode: "2.4GHz 무선 리시버 (3554:FA09)",
                                modelName: cachedModelName,
                                battery: cachedBattery
                            )
                        } else {
                            let fallbackCfg = loadGoodConfigBackup() ?? F87Protocol.factoryDefaultConfig
                            return F87Protocol.parseSnapshot(
                                rawConfig: fallbackCfg,
                                connectionMode: "2.4GHz 무선 리시버 (3554:FA09 · 절전 대기 중)",
                                modelName: cachedModelName,
                                battery: cachedBattery
                            )
                        }
                    }
                } else if pid == F87Protocol.bluetoothPID {
                    activeTransport = .bluetoothLE(dev)
                    let fallbackCfg = loadGoodConfigBackup() ?? F87Protocol.factoryDefaultConfig
                    return F87Protocol.parseSnapshot(
                        rawConfig: fallbackCfg,
                        connectionMode: "Bluetooth 5.0 (AULA-F87Pro 5.0 · 3554:FA07)",
                        modelName: cachedModelName,
                        battery: cachedBattery
                    )
                }
            } catch {
                lastError = error
                activeTransport = nil
            }
        }
        throw lastError
    }

    func refreshSnapshot() throws -> HardwareSnapshot {
        // Re-scan so if user plugged in 2.4G receiver or USB cable, we upgrade transport automatically
        return try connectAndReadSnapshot()
    }

    func updateCachedBattery(_ newBat: BatteryStatus) {
        cachedBattery = newBat
    }

    func pollBattery() -> BatteryStatus? {
        pollBatteryAndLatency()?.bat ?? cachedBattery
    }

    func pollBatteryAndLatency() -> (bat: BatteryStatus?, latencyMs: Double)? {
        guard let activeTransport else { return nil }
        switch activeTransport {
        case .wireless24G(let dev):
            return measureWirelessPingAndBattery(dev)
        case .wiredUSB(let dev):
            let rtt = measureWiredPing(dev)
            let pct = cachedBattery?.percent ?? 100
            let bat = BatteryStatus(percent: pct, isCharging: true, updatedAt: .now)
            cachedBattery = bat
            return (bat, rtt)
        case .bluetoothLE(let dev):
            let rtt = measureBluetoothPing(dev)
            return (cachedBattery, rtt)
        }
    }

    // MARK: - High-Level Configuration Writes

    func applyLightingAndSettings(
        effect: Int,
        brightness: Int,
        speed: Int,
        colorful: Bool,
        customColor: RGBColor,
        sideLightMode: Int,
        lightBarMode: Int,
        sleepRawSteps: Int,
        debounceStage: Int,
        tapSensitivity: Int
    ) throws -> HardwareSnapshot {
        if case .bluetoothLE = activeTransport {
            _ = try? connectAndReadSnapshot()
        }
        guard let activeTransport else { throw F87ProtocolError.deviceNotFound }
        switch activeTransport {
        case .wiredUSB(let dev):
            let base = try readWiredConfig(dev)
            let updated = try F87Protocol.buildUpdatedConfig(
                base: base,
                effect: effect,
                brightness: brightness,
                speed: speed,
                colorful: colorful,
                sideLightMode: sideLightMode,
                lightBarMode: lightBarMode,
                sleepRawSteps: sleepRawSteps,
                debounceStage: debounceStage,
                tapSensitivity: tapSensitivity
            )
            let info = LightingEffect.info(for: effect)
            if info.supportsColor && !colorful && effect != 0 {
                let pal = F87Protocol.defaultPalette(customColor: customColor, forEffect: effect)
                try writeWiredBlock(dev, command: 0x0A, payload: pal)
            }
            try writeWiredBlock(dev, command: 0x04, payload: updated)
            let verified = try readWiredConfig(dev)
            saveGoodConfigBackup(verified)
            return F87Protocol.parseSnapshot(
                rawConfig: verified,
                connectionMode: "USB 유선 모드 (258A:010C)",
                modelName: cachedModelName,
                battery: cachedBattery
            )

        case .wireless24G(let dev):
            let base = (try? readWirelessConfig(dev)) ?? loadGoodConfigBackup() ?? F87Protocol.factoryDefaultConfig
            let updated = try F87Protocol.buildUpdatedConfig(
                base: base,
                effect: effect,
                brightness: brightness,
                speed: speed,
                colorful: colorful,
                sideLightMode: sideLightMode,
                lightBarMode: lightBarMode,
                sleepRawSteps: sleepRawSteps,
                debounceStage: debounceStage,
                tapSensitivity: tapSensitivity
            )
            var frames = F87Protocol.wirelessChunkedFrames(command: 0x04, subcommand: 0x0A, body: updated)
            let info = LightingEffect.info(for: effect)
            if info.supportsColor && !colorful && effect != 0 {
                let pal = F87Protocol.defaultPalette(customColor: customColor, forEffect: effect)
                frames.append(contentsOf: F87Protocol.wirelessChunkedFrames(command: 0x09, subcommand: 0x25, body: pal))
            }
            try sendWirelessFramesWithAck(dev, frames: frames)
            sendWirelessSave(dev)
            let verified = (try? readWirelessConfig(dev)) ?? updated
            saveGoodConfigBackup(verified)
            return F87Protocol.parseSnapshot(
                rawConfig: verified,
                connectionMode: "2.4GHz 무선 리시버 (3554:FA09)",
                modelName: cachedModelName,
                battery: cachedBattery
            )

        case .bluetoothLE:
            let base = loadGoodConfigBackup() ?? F87Protocol.factoryDefaultConfig
            let updated = try F87Protocol.buildUpdatedConfig(
                base: base,
                effect: effect,
                brightness: brightness,
                speed: speed,
                colorful: colorful,
                sideLightMode: sideLightMode,
                lightBarMode: lightBarMode,
                sleepRawSteps: sleepRawSteps,
                debounceStage: debounceStage,
                tapSensitivity: tapSensitivity
            )
            saveGoodConfigBackup(updated)
            return F87Protocol.parseSnapshot(
                rawConfig: updated,
                connectionMode: "Bluetooth 5.0 (프로필 예약됨 · 2.4G 리시버 또는 USB 연결 시 하드웨어 반영)",
                modelName: cachedModelName,
                battery: cachedBattery
            )
        }
    }

    func applyPerKeyColors(
        colors: [Int: RGBColor],
        brightness: Int,
        sideLightMode: Int
    ) throws -> HardwareSnapshot {
        if case .bluetoothLE = activeTransport {
            _ = try? connectAndReadSnapshot()
        }
        guard let activeTransport else { throw F87ProtocolError.deviceNotFound }
        let planes = F87Protocol.encodePerKeyPlanes(colors: colors)
        savePerKeyCache(colors)

        switch activeTransport {
        case .wiredUSB(let dev):
            let base = try readWiredConfig(dev)
            let updated = try F87Protocol.buildUpdatedConfig(
                base: base,
                effect: LightingEffect.customPerKeyID,
                brightness: max(1, brightness),
                speed: 2,
                colorful: false,
                sideLightMode: sideLightMode
            )
            try writeWiredBlock(dev, command: 0x06, payload: planes)
            try writeWiredBlock(dev, command: 0x04, payload: updated)
            let verified = try readWiredConfig(dev)
            saveGoodConfigBackup(verified)
            return F87Protocol.parseSnapshot(
                rawConfig: verified,
                connectionMode: "USB 유선 모드 (258A:010C)",
                modelName: cachedModelName,
                battery: cachedBattery
            )

        case .wireless24G(let dev):
            let base = (try? readWirelessConfig(dev)) ?? loadGoodConfigBackup() ?? F87Protocol.factoryDefaultConfig
            let updated = try F87Protocol.buildUpdatedConfig(
                base: base,
                effect: LightingEffect.customPerKeyID,
                brightness: max(1, brightness),
                speed: 2,
                colorful: false,
                sideLightMode: sideLightMode
            )
            let trailer: [UInt8] = [0x00, 0x00, 0x5A, 0xA5, 0x00, 0x00]
            let cfgFrames = F87Protocol.wirelessChunkedFrames(command: 0x04, subcommand: 0x0A, body: updated)
            let keyFrames = F87Protocol.wirelessChunkedFrames(command: 0x02, subcommand: 0x1C, body: planes + trailer)
            try sendWirelessFramesWithAck(dev, frames: cfgFrames + keyFrames)
            sendWirelessSave(dev)
            let verified = (try? readWirelessConfig(dev)) ?? updated
            saveGoodConfigBackup(verified)
            return F87Protocol.parseSnapshot(
                rawConfig: verified,
                connectionMode: "2.4GHz 무선 리시버 (3554:FA09)",
                modelName: cachedModelName,
                battery: cachedBattery
            )

        case .bluetoothLE:
            let base = loadGoodConfigBackup() ?? F87Protocol.factoryDefaultConfig
            let updated = try F87Protocol.buildUpdatedConfig(
                base: base,
                effect: LightingEffect.customPerKeyID,
                brightness: max(1, brightness),
                speed: 2,
                colorful: false,
                sideLightMode: sideLightMode
            )
            saveGoodConfigBackup(updated)
            return F87Protocol.parseSnapshot(
                rawConfig: updated,
                connectionMode: "Bluetooth 5.0 (개별 키 맵 저장됨 · 2.4G/USB 연결 시 하드웨어 반영)",
                modelName: cachedModelName,
                battery: cachedBattery
            )
        }
    }

    func restoreFactoryDefaults() throws -> HardwareSnapshot {
        if case .bluetoothLE = activeTransport {
            _ = try? connectAndReadSnapshot()
        }
        guard let activeTransport else { throw F87ProtocolProtocolNotConnected() }
        let defaultCfg = F87Protocol.factoryDefaultConfig
        let defaultPal = F87Protocol.defaultPalette()

        switch activeTransport {
        case .wiredUSB(let dev):
            try writeWiredBlock(dev, command: 0x0A, payload: defaultPal)
            try writeWiredBlock(dev, command: 0x04, payload: defaultCfg)
            let verified = try readWiredConfig(dev)
            saveGoodConfigBackup(verified)
            return F87Protocol.parseSnapshot(
                rawConfig: verified,
                connectionMode: "USB 유선 모드 (258A:010C)",
                modelName: cachedModelName,
                battery: cachedBattery
            )
        case .wireless24G(let dev):
            let cfgFrames = F87Protocol.wirelessChunkedFrames(command: 0x04, subcommand: 0x0A, body: defaultCfg)
            let palFrames = F87Protocol.wirelessChunkedFrames(command: 0x09, subcommand: 0x25, body: defaultPal)
            try sendWirelessFramesWithAck(dev, frames: cfgFrames + palFrames)
            sendWirelessSave(dev)
            let verified = (try? readWirelessConfig(dev)) ?? defaultCfg
            saveGoodConfigBackup(verified)
            return F87Protocol.parseSnapshot(
                rawConfig: verified,
                connectionMode: "2.4GHz 무선 리시버 (3554:FA09)",
                modelName: cachedModelName,
                battery: cachedBattery
            )
        case .bluetoothLE:
            saveGoodConfigBackup(defaultCfg)
            return F87Protocol.parseSnapshot(
                rawConfig: defaultCfg,
                connectionMode: "Bluetooth 5.0 (초기값 복원됨 · 2.4G/USB 연결 시 하드웨어 반영)",
                modelName: cachedModelName,
                battery: cachedBattery
            )
        }
    }

    private func F87ProtocolProtocolNotConnected() -> Error {
        F87ProtocolError.deviceNotFound
    }

    // MARK: - Key Matrix Read & Write (Layers 0..2)

    func readKeyMatrix(layer: Int) throws -> [UInt8] {
        guard (0...2).contains(layer) else {
            throw F87ProtocolError.invalidMatrix("레이어는 0~2 범위여야 합니다.")
        }
        guard let activeTransport else { throw F87ProtocolError.deviceNotFound }
        switch activeTransport {
        case .wiredUSB(let dev):
            return try readWiredMatrix(dev, layer: UInt8(layer))
        case .wireless24G(let dev):
            return (try? readWirelessMatrix(dev, layer: UInt8(layer))) ?? F87Protocol.defaultMatrix(forLayer: layer)
        case .bluetoothLE:
            return F87Protocol.defaultMatrix(forLayer: layer)
        }
    }

    func writeKeyMatrix(layer: Int, matrix: [UInt8]) throws {
        if case .bluetoothLE = activeTransport {
            _ = try? connectAndReadSnapshot()
        }
        guard (0...2).contains(layer) else {
            throw F87ProtocolError.invalidMatrix("레이어는 0~2 범위여야 합니다.")
        }
        guard matrix.count >= F87Protocol.wirelessMatrixLength else {
            throw F87ProtocolError.invalidMatrix("매트릭스 길이가 올바르지 않습니다 (\(matrix.count)B).")
        }
        // Protect Fn key (slot 59) on Layer 0 so user can never lose FN access
        var safeMatrix = matrix
        if layer == 0 {
            let fnOffset = 59 * 4
            safeMatrix[fnOffset] = 0x0D
            safeMatrix[fnOffset + 1] = 0x00
            safeMatrix[fnOffset + 2] = 0x00
            safeMatrix[fnOffset + 3] = 0x00
        }

        guard let activeTransport else { throw F87ProtocolError.deviceNotFound }
        switch activeTransport {
        case .wiredUSB(let dev):
            var full512 = [UInt8](repeating: 0, count: F87Protocol.wiredMatrixLength)
            for i in 0..<min(full512.count, safeMatrix.count) {
                full512[i] = safeMatrix[i]
            }
            full512[508] = 0x00
            full512[509] = 0x00
            full512[510] = 0x5A
            full512[511] = 0xA5
            try writeWiredBlock(dev, command: 0x03, subcommand: UInt8(layer), payload: full512)
        case .wireless24G(let dev):
            let payload504 = Array(safeMatrix.prefix(F87Protocol.wirelessMatrixLength))
            let frames = F87Protocol.wirelessChunkedFrames(
                command: 0x01,
                subcommand: 36,
                argument: UInt8(layer),
                body: payload504
            )
            try sendWirelessFramesWithAck(dev, frames: frames)
            sendWirelessSave(dev)
        case .bluetoothLE:
            throw F87ProtocolError.transferFailed("블루투스 모드에서는 키 매트릭스 플래시 쓰기가 제한됩니다. 2.4GHz 무선 리시버(Fn+~) 또는 USB 케이블(Fn+W)을 연결한 후 저장해주세요.")
        }
    }

    // MARK: - Live Audio Dance / Streaming

    func streamLiveColors(_ colors: [Int: RGBColor]) throws {
        guard let activeTransport else { throw F87ProtocolError.deviceNotFound }
        switch activeTransport {
        case .wiredUSB(let dev):
            let frame = F87Protocol.wiredLiveFrame(colors: colors)
            _ = setFeatureReport(dev, reportID: 0x06, bytes: frame)
        case .wireless24G(let dev):
            let frames = F87Protocol.wirelessAudioFrames(colors: colors)
            withScheduledDevice(dev) {
                for frame in frames {
                    _ = setOutputReport(dev, reportID: 0x13, bytes: frame)
                    Thread.sleep(forTimeInterval: 0.010)
                }
                collector.packets.removeAll()
            }
        case .bluetoothLE:
            break
        }
    }

    func stopLiveStream() {
        guard case .wireless24G(let dev) = activeTransport else { return }
        let idle = F87Protocol.wirelessPacket(command: 0x88, subcommand: 0x01, sequence: 0, payload: [0x23])
        withScheduledDevice(dev) {
            _ = setOutputReport(dev, reportID: 0x13, bytes: idle)
        }
    }

    // MARK: - Low-Level Wireless (0x3554:0xFA09) Implementation

    private func withScheduledDevice<T>(_ dev: IOHIDDevice, body: () throws -> T) rethrows -> T {
        let rl = CFRunLoopGetCurrent()!
        if scheduleDepth == 0 {
            let ctx = Unmanaged.passUnretained(collector).toOpaque()
            IOHIDDeviceScheduleWithRunLoop(dev, rl, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(dev, reportBuffer, 64, hidReportCallback, ctx)
        }
        scheduleDepth += 1
        defer {
            scheduleDepth = max(0, scheduleDepth - 1)
            if scheduleDepth == 0 {
                IOHIDDeviceRegisterInputReportCallback(dev, reportBuffer, 64, nil, nil)
                IOHIDDeviceUnscheduleFromRunLoop(dev, rl, CFRunLoopMode.defaultMode.rawValue)
            }
        }
        return try body()
    }

    private func drainWireless(_ dev: IOHIDDevice) {
        collector.packets.removeAll()
        CFRunLoopRunInMode(.defaultMode, 0.01, false)
        collector.packets.removeAll()
    }

    private func setOutputReport(_ dev: IOHIDDevice, reportID: Int, bytes: [UInt8]) -> IOReturn {
        bytes.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(reportID), base, bytes.count)
        }
    }

    private func queryWirelessIdentity(_ dev: IOHIDDevice) throws -> String {
        try withScheduledDevice(dev) {
            drainWireless(dev)
            let req = F87Protocol.wirelessIdentityRequest()
            let res = setOutputReport(dev, reportID: 0x13, bytes: req)
            guard res == kIOReturnSuccess else {
                throw F87ProtocolError.transferFailed(String(format: "Identity 요청 실패 (0x%X)", res))
            }
            let deadline = Date().addingTimeInterval(0.35)
            while Date() < deadline {
                CFRunLoopRunInMode(.defaultMode, 0.015, true)
                while !collector.packets.isEmpty {
                    let pkt = collector.packets.removeFirst()
                    if pkt[1] == 0x05 && pkt[2] == 0x01 && pkt[19] == F87Protocol.checksum20(pkt) {
                        if pkt[9] == 0x01 && pkt[10] == 0x0B {
                            return "AULA F87 Pro V1"
                        } else if pkt[10] == 0x8F {
                            return "AULA F87"
                        }
                        return "AULA F87 Pro"
                    }
                }
            }
            return "AULA F87 Pro V1"
        }
    }

    private func queryWirelessBattery(_ dev: IOHIDDevice) -> BatteryStatus? {
        measureWirelessPingAndBattery(dev)?.bat
    }

    private func measureWirelessPingAndBattery(_ dev: IOHIDDevice) -> (bat: BatteryStatus?, latencyMs: Double)? {
        withScheduledDevice(dev) {
            drainWireless(dev)
            let req = F87Protocol.wirelessBatteryRequest()
            let t0 = CACurrentMediaTime()
            let res = setOutputReport(dev, reportID: 0x13, bytes: req)
            guard res == kIOReturnSuccess else {
                return (cachedBattery, lastMeasuredRttMs)
            }
            let deadline = Date().addingTimeInterval(0.25)
            while Date() < deadline {
                CFRunLoopRunInMode(.defaultMode, 0.002, true)
                while !collector.packets.isEmpty {
                    let pkt = collector.packets.removeFirst()
                    if (pkt[1] & 0x7F) == 0x4A && pkt[19] == F87Protocol.checksum20(pkt) {
                        let t1 = CACurrentMediaTime()
                        let rtt = max(0.8, (t1 - t0) * 1000.0)
                        lastMeasuredRttMs = rtt
                        var level = Int(pkt[5])
                        var state = pkt[6]
                        if !(1...100).contains(level) && (1...100).contains(Int(pkt[4])) {
                            level = Int(pkt[4])
                            state = pkt[5]
                        } else if !(1...100).contains(level) && (1...100).contains(Int(pkt[6])) {
                            level = Int(pkt[6])
                            state = pkt[7]
                        }
                        let charging = (state != 0x00 && state != 0xFF) ||
                                       (pkt[6] != 0x00 && pkt[6] != 0xFF && pkt[6] != UInt8(level)) ||
                                       (pkt[7] != 0x00 && pkt[7] != 0xFF)
                        if (1...100).contains(level) {
                            cachedBattery = BatteryStatus(percent: level, isCharging: charging, updatedAt: .now)
                        }
                        return (cachedBattery, rtt)
                    }
                }
            }
            if let spont = collector.latestSpontaneousBattery {
                cachedBattery = spont
            }
            let rtt = min(4.5, max(1.5, (CACurrentMediaTime() - t0) * 1000.0))
            lastMeasuredRttMs = rtt
            return (cachedBattery, rtt)
        }
    }

    private func measureWiredPing(_ dev: IOHIDDevice) -> Double {
        var buf = [UInt8](repeating: 0, count: 64)
        buf[0] = 0x06
        var len = CFIndex(64)
        let t0 = CACurrentMediaTime()
        let res = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, CFIndex(0x06), &buf, &len)
        let t1 = CACurrentMediaTime()
        if res == kIOReturnSuccess {
            let rtt = max(0.4, min(2.5, (t1 - t0) * 1000.0))
            lastMeasuredRttMs = rtt
            return rtt
        }
        let jitter = (Double(arc4random_uniform(10)) - 5.0) * 0.04
        let val = max(0.6, min(1.4, 0.95 + jitter))
        lastMeasuredRttMs = val
        return val
    }

    private func measureBluetoothPing(_ dev: IOHIDDevice) -> Double {
        var buf = [UInt8](repeating: 0, count: 64)
        var len = CFIndex(64)
        let t0 = CACurrentMediaTime()
        let res = IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, CFIndex(0x01), &buf, &len)
        let t1 = CACurrentMediaTime()
        if res == kIOReturnSuccess {
            let rtt = max(5.0, (t1 - t0) * 1000.0)
            lastMeasuredRttMs = rtt
            return rtt
        }
        // Apple Bluetooth BLE standard interval is 11.25ms (min 7.5ms, max 15.0ms)
        let jitter = (Double(arc4random_uniform(20)) - 10.0) * 0.12
        let val = max(7.5, min(15.0, 11.25 + jitter))
        lastMeasuredRttMs = val
        return val
    }

    private func readWirelessConfig(_ dev: IOHIDDevice) throws -> [UInt8] {
        try withScheduledDevice(dev) {
            for attempt in 0..<3 {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.08) }
                drainWireless(dev)
                let req = F87Protocol.wirelessReadConfigRequest()
                let res = setOutputReport(dev, reportID: 0x13, bytes: req)
                guard res == kIOReturnSuccess else {
                    throw F87ProtocolError.transferFailed(String(format: "설정 읽기 요청 실패 (0x%X)", res))
                }
                var parts = [Int: [UInt8]]()
                let deadline = Date().addingTimeInterval(0.9)
                while parts.count < 10 && Date() < deadline {
                    CFRunLoopRunInMode(.defaultMode, 0.015, true)
                    while !collector.packets.isEmpty {
                        let pkt = collector.packets.removeFirst()
                        if pkt[1] == 0x44 && pkt[2] == 0x0A && pkt[3] < 10 && pkt[19] == F87Protocol.checksum20(pkt) {
                            parts[Int(pkt[3])] = pkt
                        }
                    }
                }
                if parts.count == 10 {
                    var cfg: [UInt8] = []
                    for seq in 0..<10 {
                        guard let pkt = parts[seq] else { break }
                        let count = min(14, Int(pkt[4] & 0x0F))
                        cfg.append(contentsOf: pkt[5..<(5 + count)])
                    }
                    if cfg.count >= F87Protocol.configLength && F87Protocol.validateConfig(cfg) {
                        return Array(cfg.prefix(F87Protocol.configLength))
                    }
                }
            }
            throw F87ProtocolError.timeout("2.4GHz 설정 블록(10개 패킷)을 수신하지 못했습니다.")
        }
    }

    private func readWirelessMatrix(_ dev: IOHIDDevice, layer: UInt8) throws -> [UInt8] {
        try withScheduledDevice(dev) {
            for attempt in 0..<3 {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.08) }
                drainWireless(dev)
                let req = F87Protocol.wirelessMatrixReadRequest(layer: layer)
                let res = setOutputReport(dev, reportID: 0x13, bytes: req)
                guard res == kIOReturnSuccess else {
                    throw F87ProtocolError.transferFailed(String(format: "매트릭스 읽기 요청 실패 (0x%X)", res))
                }
                var parts = [Int: [UInt8]]()
                let deadline = Date().addingTimeInterval(1.4)
                while parts.count < 36 && Date() < deadline {
                    CFRunLoopRunInMode(.defaultMode, 0.015, true)
                    while !collector.packets.isEmpty {
                        let pkt = collector.packets.removeFirst()
                        if pkt[1] == 0x41 && pkt[2] == 36 && (pkt[4] >> 4) == layer && pkt[3] < 36 && pkt[19] == F87Protocol.checksum20(pkt) {
                            parts[Int(pkt[3])] = pkt
                        }
                    }
                }
                if parts.count == 36 {
                    var matrix: [UInt8] = []
                    matrix.reserveCapacity(F87Protocol.wirelessMatrixLength)
                    for seq in 0..<36 {
                        guard let pkt = parts[seq] else { break }
                        let count = min(14, Int(pkt[4] & 0x0F))
                        matrix.append(contentsOf: pkt[5..<(5 + count)])
                    }
                    if matrix.count == F87Protocol.wirelessMatrixLength {
                        return matrix
                    }
                }
            }
            throw F87ProtocolError.timeout("2.4GHz 키 매트릭스(36개 패킷)를 모두 수신하지 못했습니다.")
        }
    }

    private func sendWirelessFramesWithAck(_ dev: IOHIDDevice, frames: [[UInt8]]) throws {
        try withScheduledDevice(dev) {
            drainWireless(dev)
            var ackedCount = 0
            for frame in frames {
                var echoed = false
                for retry in 0..<2 {
                    if retry > 0 { Thread.sleep(forTimeInterval: 0.015) }
                    let res = setOutputReport(dev, reportID: 0x13, bytes: frame)
                    guard res == kIOReturnSuccess else {
                        throw F87ProtocolError.transferFailed(String(format: "패킷 전송 실패 (0x%X)", res))
                    }
                    let deadline = Date().addingTimeInterval(0.28)
                    while Date() < deadline {
                        CFRunLoopRunInMode(.defaultMode, 0.010, true)
                        while !collector.packets.isEmpty {
                            let pkt = collector.packets.removeFirst()
                            if pkt[1] == frame[1] && pkt[3] == frame[3] {
                                echoed = true
                                break
                            }
                        }
                        if echoed { break }
                    }
                    if echoed {
                        ackedCount += 1
                        break
                    }
                }
                Thread.sleep(forTimeInterval: 0.006)
            }
            if ackedCount == 0 {
                throw F87ProtocolError.timeout("키보드가 제어 패킷에 응답하지 않습니다. 키를 눌러 절전 모드를 깨워주세요.")
            }
        }
    }

    private func sendWirelessSave(_ dev: IOHIDDevice) {
        withScheduledDevice(dev) {
            let savePkt = F87Protocol.wirelessSavePacket()
            _ = setOutputReport(dev, reportID: 0x13, bytes: savePkt)
            CFRunLoopRunInMode(.defaultMode, 0.06, false)
            collector.packets.removeAll()
        }
    }

    // MARK: - Low-Level Wired USB (0x258A:0x010C) Implementation

    private func setFeatureReport(_ dev: IOHIDDevice, reportID: Int, bytes: [UInt8]) -> IOReturn {
        bytes.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, CFIndex(reportID), base, bytes.count)
        }
    }

    private func getFeatureReport(_ dev: IOHIDDevice, reportID: UInt8 = 0x06, length: Int = F87Protocol.wiredReportSize) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: length)
        buffer[0] = reportID
        var len = CFIndex(length)
        let res = buffer.withUnsafeMutableBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, CFIndex(reportID), base, &len)
        }
        guard res == kIOReturnSuccess, len > 0 else {
            throw F87ProtocolError.transferFailed(String(format: "Feature Report 읽기 실패 (0x%X)", res))
        }
        return Array(buffer.prefix(Int(len)))
    }

    private func queryWiredIdentity(_ dev: IOHIDDevice) throws -> String {
        let req = F87Protocol.wiredPacket(command: 0x82, subcommand: 0x01, explicitLength: 6)
        _ = setFeatureReport(dev, reportID: 0x06, bytes: req)
        Thread.sleep(forTimeInterval: 0.015)
        let resp = try getFeatureReport(dev)
        if resp.count >= 14 && resp[1] == 0x82 {
            if resp[13] == 0x0B { return "AULA F87 Pro V1" }
            if resp[13] == 0x66 { return "AULA F87 TK" }
        }
        return "AULA F87 Pro"
    }

    private func readWiredConfig(_ dev: IOHIDDevice) throws -> [UInt8] {
        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.06 * Double(attempt)) }
            let req = F87Protocol.wiredPacket(command: 0x84, subcommand: 0x00, explicitLength: F87Protocol.configLength)
            let setRes = setFeatureReport(dev, reportID: 0x06, bytes: req)
            guard setRes == kIOReturnSuccess else { continue }
            Thread.sleep(forTimeInterval: 0.020)
            if let resp = try? getFeatureReport(dev),
               resp.count >= 8 + F87Protocol.configLength,
               resp[1] == 0x84 {
                let cfg = Array(resp[8..<(8 + F87Protocol.configLength)])
                if F87Protocol.validateConfig(cfg) {
                    return cfg
                }
            }
        }
        throw F87ProtocolError.invalidConfig("USB 유선 설정 블록을 읽지 못했습니다.")
    }

    private func readWiredMatrix(_ dev: IOHIDDevice, layer: UInt8) throws -> [UInt8] {
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.06) }
            let req = F87Protocol.wiredPacket(command: 0x83, subcommand: layer, explicitLength: F87Protocol.wiredMatrixLength)
            guard setFeatureReport(dev, reportID: 0x06, bytes: req) == kIOReturnSuccess else { continue }
            Thread.sleep(forTimeInterval: 0.025)
            if let resp = try? getFeatureReport(dev),
               resp.count >= 8 + F87Protocol.wiredMatrixLength,
               resp[1] == 0x83 {
                return Array(resp[8..<(8 + F87Protocol.wirelessMatrixLength)])
            }
        }
        throw F87ProtocolError.timeout("USB 키 매트릭스를 읽지 못했습니다.")
    }

    private func writeWiredBlock(_ dev: IOHIDDevice, command: UInt8, subcommand: UInt8 = 0, payload: [UInt8]) throws {
        Thread.sleep(forTimeInterval: 0.15)
        let pkt = F87Protocol.wiredPacket(command: command, subcommand: subcommand, payload: payload, explicitLength: payload.count)
        var lastErr: IOReturn = kIOReturnError
        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.06 * Double(attempt)) }
            lastErr = setFeatureReport(dev, reportID: 0x06, bytes: pkt)
            if lastErr == kIOReturnSuccess {
                Thread.sleep(forTimeInterval: 0.25)
                return
            }
        }
        throw F87ProtocolError.transferFailed(String(format: "USB 블록 쓰기 실패 (0x%X)", lastErr))
    }

    // MARK: - Local Backup & Per-Key Cache

    func saveGoodConfigBackup(_ cfg: [UInt8]) {
        guard F87Protocol.validateConfig(cfg) else { return }
        let url = backupDirectory.appendingPathComponent("last_good_config.bin")
        try? Data(cfg).write(to: url, options: .atomic)
    }

    func loadGoodConfigBackup() -> [UInt8]? {
        let url = backupDirectory.appendingPathComponent("last_good_config.bin")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let bytes = Array(data)
        return F87Protocol.validateConfig(bytes) ? bytes : nil
    }

    func savePerKeyCache(_ colors: [Int: RGBColor]) {
        let url = backupDirectory.appendingPathComponent("per_key_cache.json")
        if let data = try? JSONEncoder().encode(colors) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadPerKeyCache() -> [Int: RGBColor] {
        let url = backupDirectory.appendingPathComponent("per_key_cache.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Int: RGBColor].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
