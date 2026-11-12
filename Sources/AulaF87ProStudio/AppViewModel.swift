import AppKit
import Foundation
import SwiftUI
import UserNotifications

enum NavigationTab: String, CaseIterable, Identifiable {
    case batteryMonitor = "배터리 & 소비 전력 모니터"
    case lighting = "키 백라이트 & 효과"
    case perKey = "개별 키 RGB 페인터"
    case sideLight = "측면 조명 & 라이트바"
    case keymap = "키 매핑 & FN 레이어"
    case music = "뮤직 싱크 (오디오 댄스)"
    case performance = "성능 · 전원 · 백업"
    case profiles = "프로필 보관함"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .batteryMonitor: return "bolt.batteryblock.fill"
        case .lighting: return "sparkles"
        case .perKey: return "paintbrush.pointed.fill"
        case .sideLight: return "light.strip.2"
        case .keymap: return "keyboard.fill"
        case .music: return "waveform.badge.mic"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .profiles: return "square.stack.3d.up.fill"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var currentTab: NavigationTab = .lighting
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var statusTitle = "키보드 검색 중…"
    @Published var statusDetail: String?
    @Published var connectionMode = "연결 대기 중"
    @Published var modelName = "AULA F87 Pro V1"
    @Published var battery: BatteryStatus?

    // Lighting & Effect state
    @Published var selectedEffect: Int = 11
    @Published var brightness: Int = 4
    @Published var speed: Int = 3
    @Published var colorful: Bool = true
    @Published var selectedColor: RGBColor = .cyan
    @Published var sideLightMode: Int = 1
    @Published var lightBarMode: Int = 1

    // Performance & Power state
    @Published var sleepRawSteps: Int = 10 // 5 min
    @Published var debounceStage: Int = 3 // 3ms
    @Published var tapSensitivity: Int = 0

    // Per-Key RGB state
    @Published var perKeyColors: [Int: RGBColor] = [:]
    @Published var perKeyTool: PerKeyTool = .paint
    @Published var selectedLEDs: Set<Int> = []
    @Published var gradientEndColor: RGBColor = .neonPurple
    @Published var gradientDirection: GradientDirection = .horizontal
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    // Key Matrix Remapping state
    @Published var selectedMatrixLayer: Int = 0
    @Published var matrixLayers: [Int: [UInt8]] = [:]
    @Published var selectedKeyForRemap: KeyboardKey = F87Layout.allKeys[0]
    @Published var selectedRemapCategory: String = "추천 / Mac & 한국어"
    @Published var customComboMods: UInt8 = 0
    @Published var customComboKey: UInt8 = 0x04

    // Music Reactive state
    @Published private(set) var isMusicSyncActive = false
    @Published var musicDemoMode = true
    @Published var musicSensitivity: Double = 1.35
    @Published var musicColorMode: Int = 0 // 0 = Rainbow Meter, 1 = Custom Color
    @Published private(set) var audioLevels: [Double] = Array(repeating: 0, count: 11)
    @Published var micPermissionGranted: Bool = (MusicVisualizer.currentPermissionStatus() == .authorized)
    @Published var micStatusText: String = {
        switch MusicVisualizer.currentPermissionStatus() {
        case .authorized: return "마이크 권한 승인됨"
        case .notDetermined: return "마이크 권한 요청 전"
        case .denied, .restricted: return "마이크 권한 거부됨 (시스템 설정에서 허용 필요)"
        @unknown default: return "마이크 상태 확인 필요"
        }
    }()

    // Profiles & Logs
    @Published var profiles: [StoredProfile] = []
    @Published var toastMessage: String?
    @Published var logs: [String] = []
    @Published var lastTelemetryUpdate: Date = .now

    // Real-time Hardware Latency & Polling Rate Tracking
    @Published var latencyStats: LatencyStats?
    private var latencyHistory: [Double] = []

    // User-configurable Telemetry Refresh Interval (0.5s ~ 5.0s)
    @Published var refreshInterval: Double = {
        let saved = UserDefaults.standard.double(forKey: "telemetryRefreshInterval")
        return (saved >= 0.5 && saved <= 10.0) ? saved : 1.0
    }() {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "telemetryRefreshInterval")
            restartBatteryPolling()
        }
    }

    // AlDente Battery Health Guard State
    @Published var isAlDenteEnabled: Bool = {
        UserDefaults.standard.object(forKey: "alDenteEnabled") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(isAlDenteEnabled, forKey: "alDenteEnabled")
            checkAlDenteNotification()
        }
    }

    @Published var alDenteLimitPercent: Int = {
        let saved = UserDefaults.standard.integer(forKey: "alDenteLimitPercent")
        return (saved >= 50 && saved <= 95) ? saved : 80
    }() {
        didSet {
            UserDefaults.standard.set(alDenteLimitPercent, forKey: "alDenteLimitPercent")
            checkAlDenteNotification()
        }
    }

    @Published var alDenteSoundAlert: Bool = {
        UserDefaults.standard.object(forKey: "alDenteSoundAlert") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(alDenteSoundAlert, forKey: "alDenteSoundAlert")
        }
    }

    @Published var isAlDenteTriggered: Bool = false
    private var lastAlDenteAlertTime: Date?

    // Low Battery (10% or below) Full-Screen Warning Banner State
    @Published var isLowBatteryBannerVisible: Bool = false
    @Published var isLowBatteryTestActive: Bool = false
    @Published var isLowBatteryWarningEnabled: Bool = {
        UserDefaults.standard.object(forKey: "lowBatteryWarningEnabled") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(isLowBatteryWarningEnabled, forKey: "lowBatteryWarningEnabled")
            checkLowBatteryWarning()
        }
    }
    @Published var lowBatteryDismissedUntil: Date? = nil
    private var lastLowBatteryAlertTime: Date?

    var isEffectiveCharging: Bool {
        (battery?.isCharging ?? false) || connectionMode.contains("USB")
    }

    var effectiveBattery: BatteryStatus {
        if let b = battery {
            return BatteryStatus(percent: b.percent, isCharging: isEffectiveCharging, updatedAt: b.updatedAt)
        }
        return BatteryStatus(percent: 81, isCharging: isEffectiveCharging, updatedAt: .now)
    }

    // Keystroke & Reactive Typing Tracking
    @Published var isTypingNow: Bool = false
    @Published var typingSpeedCPM: Int = 0
    @Published var activeKeyHits: [Int: Double] = [:] // LED index -> hit time in seconds
    @Published var lastKeystrokeAt: Date?
    private var keystrokeTimestamps: [Date] = []
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    private static let macKeyCodeToLed: [UInt16: Int] = [
        // Function Row
        53: 0, 122: 12, 120: 18, 99: 24, 118: 30, 96: 36, 97: 42, 98: 48, 100: 54, 101: 60, 109: 66, 103: 72, 111: 78,
        105: 84, 107: 90, 113: 96,
        // Number Row
        50: 1, 18: 7, 19: 13, 20: 19, 21: 25, 23: 31, 22: 37, 26: 43, 28: 49, 25: 55, 29: 61, 27: 67, 24: 73, 51: 79,
        114: 85, 115: 91, 116: 97,
        // QWERTY Row
        48: 2, 12: 8, 13: 14, 14: 20, 15: 26, 17: 32, 16: 38, 32: 44, 34: 50, 31: 56, 35: 62, 33: 68, 30: 74, 42: 80,
        117: 86, 119: 92, 121: 98,
        // Home Row (Enter is slot 81)
        57: 3, 0: 9, 1: 15, 2: 21, 3: 27, 5: 33, 4: 39, 38: 45, 40: 51, 37: 57, 41: 63, 39: 69, 36: 81,
        // Shift Row (RShift is slot 82)
        56: 4, 6: 10, 7: 16, 8: 22, 9: 28, 11: 34, 45: 40, 46: 46, 43: 52, 47: 58, 44: 64, 60: 82,
        126: 94,
        // Bottom Row
        59: 5, 55: 11, 58: 17, 49: 35, 61: 53, 63: 59, 110: 65, 62: 83,
        123: 89, 125: 95, 124: 101
    ]

    private var undoStack: [[Int: RGBColor]] = []
    private var redoStack: [[Int: RGBColor]] = []
    private let hidService = HIDService()
    private let hidQueue = DispatchQueue(label: "com.antigravity.aulaf87pro.hid", qos: .userInitiated)
    private let musicVisualizer = MusicVisualizer()
    private var audioStreamFrameInFlight = false
    private var batteryTimer: Timer?
    private var isPollingHID = false

    private let profilesURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AulaF87ProStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }()

    init() {
        perKeyColors = hidService.loadPerKeyCache()
        loadProfilesFromDisk()
        setupKeyMonitoring()
        setupDeviceStateMonitoring()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if !CommandLine.arguments.contains("--probe") {
            connectKeyboard()
            startBatteryPolling()
        }
    }

    var selectedEffectInfo: LightingEffect {
        LightingEffect.info(for: selectedEffect)
    }

    var powerTelemetry: PowerTelemetry {
        PowerTelemetry.calculate(
            battery: effectiveBattery,
            effect: selectedEffect,
            brightness: brightness,
            activePerKeyCount: perKeyColors.count,
            sideLightMode: sideLightMode,
            lightBarMode: lightBarMode,
            isWiredUSB: connectionMode.contains("USB"),
            isActivelyTyping: isTypingNow,
            typingSpeedCPM: typingSpeedCPM
        )
    }

    func applyEcoMode() {
        selectedEffect = 1 // Static
        brightness = 1
        speed = 2
        colorful = false
        sideLightMode = 0
        lightBarMode = 0
        sleepRawSteps = 2 // 1 min (60s)
        applyLightingAndSettingsToHardware()
        showToast("에코 절전 모드가 적용되었습니다 (소비 전력 ~66mW · 최대 약 60시간 지속)")
    }

    // MARK: - Connection & Sync

    func connectKeyboard() {
        guard !isBusy else { return }
        stopMusicSyncIfNeeded()
        isBusy = true
        statusTitle = "키보드 연결 중…"
        log("AULA F87 Pro 제어 인터페이스 검색 중…")

        let service = hidService
        hidQueue.async { [weak self] in
            do {
                let snap = try service.connectAndReadSnapshot()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.isConnected = true
                    self.applySnapshotToUI(snap)
                    self.statusTitle = "\(snap.modelName) 연결됨"
                    self.statusDetail = nil
                    self.log("연결 성공: \(snap.modelName) (\(snap.connectionMode))")
                    self.showToast("키보드 설정을 불러왔습니다")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.isConnected = false
                    self.statusTitle = "연결되지 않음"
                    self.statusDetail = error.localizedDescription
                    self.log("연결 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    func refreshFromHardware() {
        guard !isBusy else { return }
        stopMusicSyncIfNeeded()
        isBusy = true
        statusTitle = "키보드 상태 읽는 중…"

        let service = hidService
        hidQueue.async { [weak self] in
            do {
                let snap = try service.refreshSnapshot()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.isConnected = true
                    self.applySnapshotToUI(snap)
                    self.statusTitle = "\(snap.modelName) 연결됨"
                    self.statusDetail = nil
                    self.log("하드웨어 상태 새로고침 완료 (효과 #\(snap.effect), 밝기 \(snap.brightness), 속도 \(snap.speed))")
                    self.showToast("현재 키보드 설정을 동기화했습니다")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.isConnected = false
                    self.statusTitle = "통신 오류"
                    self.statusDetail = error.localizedDescription
                    self.log("새로고침 오류: \(error.localizedDescription)")
                }
            }
        }
    }

    deinit {
        batteryTimer?.invalidate()
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
    }

    private func setupKeyMonitoring() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.registerKeystroke(keyCode: event.keyCode)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            DispatchQueue.main.async {
                self?.registerKeystroke(keyCode: event.keyCode)
            }
        }
    }

    func registerKeystroke(keyCode: UInt16) {
        let now = Date()
        keystrokeTimestamps.append(now)
        let cutoff = now.addingTimeInterval(-5.0)
        keystrokeTimestamps.removeAll { $0 < cutoff }
        lastKeystrokeAt = now
        isTypingNow = true
        typingSpeedCPM = keystrokeTimestamps.count * 12
        if let led = Self.macKeyCodeToLed[keyCode] {
            activeKeyHits[led] = now.timeIntervalSinceReferenceDate
        }

        // 키 입력 감지: 키보드가 절전 모드이거나 분리 상태였을 때 즉시 무중단 재연결
        if !isConnected || connectionMode.contains("절전") {
            autoReconnectSilently()
        }
    }

    private var consecutivePollFailures: Int = 0
    private var hotplugDebounceWorkItem: DispatchWorkItem?

    private func setupDeviceStateMonitoring() {
        hidService.onDeviceStateChange = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.handleHotplugEvent()
            }
        }
    }

    private func handleHotplugEvent() {
        hotplugDebounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isBusy else { return }
            self.autoReconnectSilently()
        }
        hotplugDebounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    func autoReconnectSilently() {
        guard !isBusy else { return }
        let service = hidService
        hidQueue.async { [weak self] in
            guard let self else { return }
            if let snap = try? service.connectAndReadSnapshot() {
                DispatchQueue.main.async {
                    let changed = (self.connectionMode != snap.connectionMode) || !self.isConnected
                    self.isConnected = true
                    if changed {
                        self.applySnapshotToUI(snap)
                        self.statusTitle = "\(snap.modelName) 연결됨"
                        self.statusDetail = nil
                        self.log("하드웨어 연결 변경 감지: \(snap.modelName) (\(snap.connectionMode))")
                        self.showToast("연결 감지: \(snap.connectionMode)")
                    }
                    self.consecutivePollFailures = 0
                    self.checkAlDenteNotification()
                }
            } else if !service.isConnected {
                DispatchQueue.main.async {
                    if self.isConnected {
                        self.isConnected = false
                        self.statusTitle = "연결 대기 중"
                        self.statusDetail = "키보드가 분리되었거나 절전 상태입니다"
                        self.log("키보드 연결 해제됨 (신호 대기 중)")
                    }
                }
            }
        }
    }

    func setRefreshInterval(_ val: Double) {
        refreshInterval = max(0.5, min(10.0, val))
        showToast("갱신 주기가 \(String(format: "%.1f", refreshInterval))초로 설정되었습니다")
    }

    func restartBatteryPolling() {
        batteryTimer?.invalidate()
        startBatteryPolling()
    }

    func checkAlDenteNotification() {
        checkLowBatteryWarning()

        guard isAlDenteEnabled, let bat = battery else {
            isAlDenteTriggered = false
            return
        }

        let reached = isEffectiveCharging && bat.percent >= alDenteLimitPercent
        isAlDenteTriggered = reached

        if reached {
            let now = Date()
            if let last = lastAlDenteAlertTime, now.timeIntervalSince(last) < 120 {
                return
            }
            lastAlDenteAlertTime = now

            if alDenteSoundAlert {
                NSSound.beep()
            }
            sendAlDenteSystemNotification(percent: bat.percent, limit: alDenteLimitPercent)
            showToast("🛡️ [AlDente 배터리 보호] \(alDenteLimitPercent)% 충전 한계에 도달했습니다! 케이블을 분리해주세요.")
        }
    }

    func checkLowBatteryWarning() {
        guard isLowBatteryWarningEnabled, let bat = battery, isConnected else {
            if !isLowBatteryTestActive && isLowBatteryBannerVisible {
                isLowBatteryBannerVisible = false
                LowBatteryOverlayManager.shared.hide()
            }
            return
        }

        let isLow = bat.percent <= 10 && !isEffectiveCharging

        if isLow {
            let now = Date()
            if let snooze = lowBatteryDismissedUntil, now < snooze {
                if !isLowBatteryTestActive && isLowBatteryBannerVisible {
                    isLowBatteryBannerVisible = false
                    LowBatteryOverlayManager.shared.hide()
                }
                return
            }

            if !isLowBatteryBannerVisible {
                isLowBatteryBannerVisible = true
                isLowBatteryTestActive = false
                LowBatteryOverlayManager.shared.show(vm: self, isTest: false)
                if let last = lastLowBatteryAlertTime, now.timeIntervalSince(last) < 300 {
                    // Suppress repeated alert beep
                } else {
                    lastLowBatteryAlertTime = now
                    NSSound.beep()
                    sendLowBatterySystemNotification(percent: bat.percent)
                }
            }
        } else {
            // ONLY dismiss when NOT actively testing!
            if !isLowBatteryTestActive {
                if isLowBatteryBannerVisible {
                    isLowBatteryBannerVisible = false
                    LowBatteryOverlayManager.shared.hide()
                }
                lowBatteryDismissedUntil = nil
            }
        }
    }

    private func sendLowBatterySystemNotification(percent: Int) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ AULA F87 Pro 배터리 부족 (10% 이하)"
        content.subtitle = "현재 잔량 \(percent)% · 전원 차단 방지"
        content.body = "키보드 배터리가 10% 이하로 소진되었습니다. 무선 연결 차단을 방지하기 위해 즉시 USB 충전 케이블을 연결해주세요."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "low-bat-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func dismissLowBatteryBanner(snoozeMinutes: Double = 10) {
        let wasTesting = isLowBatteryTestActive
        isLowBatteryTestActive = false
        isLowBatteryBannerVisible = false
        LowBatteryOverlayManager.shared.hide()
        if snoozeMinutes > 0 && !wasTesting {
            lowBatteryDismissedUntil = Date().addingTimeInterval(snoozeMinutes * 60)
            showToast("배터리 부족 경고가 \(Int(snoozeMinutes))분 동안 일시 숨김 처리되었습니다.")
        } else {
            showToast("긴급 경고 화면이 닫혔습니다.")
        }
    }

    func showLowBatteryTestBanner() {
        lowBatteryDismissedUntil = nil
        isLowBatteryTestActive = true
        isLowBatteryBannerVisible = true
        LowBatteryOverlayManager.shared.show(vm: self, isTest: true)
        showToast("모니터 전체 화면 긴급 경고 테스트가 실행되었습니다. (ESC로 종료)")
    }

    func applyEmergencyEcoMode() {
        brightness = 0
        sideLightMode = 0
        lightBarMode = 0
        applyLightingAndSettingsToHardware()
        showToast("긴급 절전: 모든 백라이트 및 측면 조명이 즉시 꺼졌습니다.")
    }

    private func sendAlDenteSystemNotification(percent: Int, limit: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🛡️ AlDente 배터리 수명 보호"
        content.subtitle = "AULA F87 Pro V1 (\(percent)%)"
        content.body = "목표 충전 한계(\(limit)%)에 도달했습니다. 리튬이온 배터리 수명 보호를 위해 충전 케이블을 분리하거나 무선 모드로 전환해주세요."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "aldente-limit-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func startBatteryPolling() {
        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isBusy, !self.isMusicSyncActive, !self.isPollingHID else { return }
                self.lastTelemetryUpdate = .now

                // Real-time typing activity check
                let now = Date()
                let cutoff = now.addingTimeInterval(-5.0)
                self.keystrokeTimestamps.removeAll { $0 < cutoff }
                self.typingSpeedCPM = self.keystrokeTimestamps.count * 12
                if let last = self.lastKeystrokeAt, now.timeIntervalSince(last) > 1.8 {
                    self.isTypingNow = false
                } else if self.lastKeystrokeAt == nil {
                    self.isTypingNow = false
                }
                let refNow = now.timeIntervalSinceReferenceDate
                self.activeKeyHits = self.activeKeyHits.filter { refNow - $0.value < 1.5 }

                let service = self.hidService
                let shouldReconnect = !self.isConnected || self.connectionMode.contains("절전")
                self.isPollingHID = true
                self.hidQueue.async { [weak self] in
                    defer {
                        Task { @MainActor [weak self] in
                            self?.isPollingHID = false
                        }
                    }
                    if shouldReconnect {
                        if let snap = try? service.connectAndReadSnapshot() {
                            DispatchQueue.main.async {
                                guard let self else { return }
                                let changedMode = (self.connectionMode != snap.connectionMode) || !self.isConnected
                                self.isConnected = true
                                if changedMode {
                                    self.applySnapshotToUI(snap)
                                    self.statusTitle = "\(snap.modelName) 연결됨"
                                    self.statusDetail = nil
                                    self.log("자동 연결 감지: \(snap.modelName) (\(snap.connectionMode))")
                                    self.showToast("\(snap.connectionMode) 연결됨")
                                }
                                self.consecutivePollFailures = 0
                                self.checkAlDenteNotification()
                            }
                        }
                    } else if let outcome = service.pollBatteryAndLatency() {
                        DispatchQueue.main.async {
                            self?.consecutivePollFailures = 0
                            self?.recordLatencyMeasurements(samples: [outcome.latencyMs], bat: outcome.bat)
                        }
                    } else {
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.consecutivePollFailures += 1
                            if self.consecutivePollFailures >= 4 && self.isConnected {
                                if !self.connectionMode.contains("절전") {
                                    self.statusTitle = "\(self.modelName) (절전 대기 중)"
                                    self.statusDetail = "키를 누르면 즉시 깨어납니다"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func forcePollBatteryNow() {
        guard !isBusy, !isPollingHID else { return }
        isPollingHID = true
        hidQueue.async { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.isPollingHID = false
                }
            }
            if let outcome = self.hidService.pollBatteryAndLatency() {
                DispatchQueue.main.async {
                    let toast = "실시간 갱신 완료: \(String(format: "%.1f", outcome.latencyMs))ms 핑 · 배터리 \(outcome.bat?.percent ?? self.battery?.percent ?? 0)%"
                    self.recordLatencyMeasurements(samples: [outcome.latencyMs], bat: outcome.bat, toastMessage: toast)
                }
            }
        }
    }

    func runLatencyBenchmarkBurst() {
        guard !isBusy, !isPollingHID else { return }
        isPollingHID = true
        showToast("실시간 10회 레이턴시 벤치마크 측정 중…")
        hidQueue.async { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.isPollingHID = false
                }
            }
            var burstSamples: [Double] = []
            for _ in 0..<10 {
                if let res = self.hidService.pollBatteryAndLatency() {
                    burstSamples.append(res.latencyMs)
                }
                Thread.sleep(forTimeInterval: 0.015)
            }
            if !burstSamples.isEmpty {
                DispatchQueue.main.async {
                    let avg = burstSamples.reduce(0, +) / Double(burstSamples.count)
                    let minV = burstSamples.min() ?? 0
                    let toast = "벤치마크 완료: 평균 \(String(format: "%.2f", avg))ms (최저 \(String(format: "%.2f", minV))ms)"
                    self.recordLatencyMeasurements(samples: burstSamples, bat: nil, toastMessage: toast)
                }
            }
        }
    }

    @MainActor
    private func recordLatencyMeasurements(samples: [Double], bat: BatteryStatus?, toastMessage: String? = nil) {
        for s in samples {
            if s >= 0.5 && s <= 150.0 {
                latencyHistory.append(s)
            }
        }
        if latencyHistory.count > 30 {
            latencyHistory.removeFirst(latencyHistory.count - 30)
        }
        guard let rtt = samples.last ?? latencyHistory.last else { return }
        let currentPool = latencyHistory.isEmpty ? [rtt] : latencyHistory
        let minMs = currentPool.min() ?? rtt
        let maxMs = currentPool.max() ?? rtt
        let avgMs = currentPool.reduce(0, +) / Double(currentPool.count)
        let variance = currentPool.map { pow($0 - avgMs, 2) }.reduce(0, +) / Double(currentPool.count)
        let jitterMs = sqrt(variance)

        let isWired = connectionMode.contains("USB")
        let isBT = connectionMode.contains("Bluetooth")
        let pollingRate = isBT ? 133 : 1000
        let kindName = isWired ? "USB 유선 모드 (1,000Hz eSports)" : (isBT ? "Bluetooth 5.0 (133Hz 절전)" : "2.4GHz 무선 리시버 (1,000Hz 게이밍)")

        // Effective 1-Way keystroke input latency calculation (matrix scan + debounce + RF/USB packet to OS)
        let effectiveDelay: Double = {
            if isWired {
                return max(0.5, min(2.0, Double(debounceStage) * 0.25 + 0.5))
            } else if isBT {
                return max(7.5, min(14.0, rtt * 0.65))
            } else {
                return max(1.0, min(2.5, Double(debounceStage) * 0.3 + 0.8))
            }
        }()

        if let bat {
            let isWired = connectionMode.contains("USB")
            self.battery = BatteryStatus(percent: bat.percent, isCharging: bat.isCharging || isWired, updatedAt: .now)
        } else if connectionMode.contains("USB"), let current = self.battery {
            self.battery = BatteryStatus(percent: current.percent, isCharging: true, updatedAt: .now)
        }
        self.latencyStats = LatencyStats(
            currentRttMs: rtt,
            effectiveInputMs: effectiveDelay,
            minMs: minMs,
            avgMs: avgMs,
            maxMs: maxMs,
            jitterMs: jitterMs,
            pollingRateHz: pollingRate,
            connectionKind: kindName,
            sampleCount: latencyHistory.count,
            history: latencyHistory,
            updatedAt: .now
        )
        self.lastTelemetryUpdate = .now
        self.checkAlDenteNotification()
        if let toastMessage {
            self.showToast(toastMessage)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func applySnapshotToUI(_ snap: HardwareSnapshot) {
        connectionMode = snap.connectionMode
        modelName = snap.modelName
        if let bat = snap.battery {
            let isWired = snap.connectionMode.contains("USB")
            battery = BatteryStatus(percent: bat.percent, isCharging: bat.isCharging || isWired, updatedAt: .now)
        }
        selectedEffect = snap.effect
        brightness = snap.brightness
        speed = snap.speed
        colorful = snap.colorful
        sideLightMode = snap.sideLightMode
        lightBarMode = snap.lightBarMode
        sleepRawSteps = snap.sleepRawSteps
        debounceStage = snap.debounceStage
        tapSensitivity = snap.tapSensitivity
    }

    // MARK: - Lighting & Hardware Settings Apply

    func selectLightingEffect(_ id: Int) {
        selectedEffect = id
        let info = LightingEffect.info(for: id)
        if !info.supportsColor && id != 0 {
            colorful = true
        }
        applyLightingAndSettingsToHardware()
    }

    func selectSideLightMode(_ mode: Int) {
        sideLightMode = mode
        applyLightingAndSettingsToHardware()
    }

    func selectLightBarMode(_ mode: Int) {
        lightBarMode = mode
        applyLightingAndSettingsToHardware()
    }

    func applyLightingAndSettingsToHardware() {
        guard !isBusy else { return }
        stopMusicSyncIfNeeded()
        isBusy = true
        statusTitle = "키보드에 설정 저장 중…"

        let eff = selectedEffect
        let bri = brightness
        let spd = speed
        let colMode = colorful || !selectedEffectInfo.supportsColor
        let col = selectedColor
        let side = sideLightMode
        let bar = lightBarMode
        let slp = sleepRawSteps
        let deb = debounceStage
        let tap = tapSensitivity
        let service = hidService

        hidQueue.async { [weak self] in
            do {
                let snap = try service.applyLightingAndSettings(
                    effect: eff,
                    brightness: bri,
                    speed: spd,
                    colorful: colMode,
                    customColor: col,
                    sideLightMode: side,
                    lightBarMode: bar,
                    sleepRawSteps: slp,
                    debounceStage: deb,
                    tapSensitivity: tap
                )
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.isConnected = true
                    self.applySnapshotToUI(snap)
                    self.statusTitle = "\(snap.modelName) 연결됨"
                    self.statusDetail = nil
                    self.log("설정 적용 완료: 효과=\(LightingEffect.info(for: eff).titleKo), 밝기=\(bri), 속도=\(spd), 측면=\(side), 디바운스=\(deb)단계")
                    self.showToast("조명 효과 '\(LightingEffect.info(for: eff).titleKo)'(으)로 적용되었습니다")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.statusTitle = "설정 저장 실패"
                    self.statusDetail = error.localizedDescription
                    self.log("설정 적용 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Per-Key RGB Operations

    func handleKeyClick(_ key: KeyboardKey) {
        recordUndoState()
        switch perKeyTool {
        case .paint:
            perKeyColors[key.led] = selectedColor
        case .erase:
            perKeyColors.removeValue(forKey: key.led)
        case .eyedropper:
            if let existing = perKeyColors[key.led] {
                selectedColor = existing
                perKeyTool = .paint
            }
        case .select:
            if selectedLEDs.contains(key.led) {
                selectedLEDs.remove(key.led)
            } else {
                selectedLEDs.insert(key.led)
            }
        }
    }

    func selectKeyGroup(_ group: String) {
        switch group {
        case "all":
            selectedLEDs = Set(F87Layout.allKeys.map(\.led))
        case "none":
            selectedLEDs.removeAll()
        case "wasd":
            selectedLEDs = [14, 9, 15, 21] // W, A, S, D
        case "arrows":
            selectedLEDs = [94, 95, 89, 101] // Up, Down, Left, Right
        case "fkeys":
            selectedLEDs = [12, 18, 24, 30, 36, 42, 48, 54, 60, 66, 72, 78]
        case "numbers":
            selectedLEDs = [7, 13, 19, 25, 31, 37, 43, 49, 55, 61]
        case "modifiers":
            selectedLEDs = [0, 2, 3, 4, 5, 11, 17, 53, 59, 65, 83, 82, 81, 79]
        default:
            break
        }
    }

    func fillTargetKeysWithSelectedColor() {
        recordUndoState()
        let targets = selectedLEDs.isEmpty ? Set(F87Layout.allKeys.map(\.led)) : selectedLEDs
        for led in targets {
            perKeyColors[led] = selectedColor
        }
    }

    func clearTargetKeys() {
        recordUndoState()
        if selectedLEDs.isEmpty {
            perKeyColors.removeAll()
        } else {
            for led in selectedLEDs {
                perKeyColors.removeValue(forKey: led)
            }
        }
    }

    func applyPresetWASDGaming() {
        recordUndoState()
        let highlight: Set<Int> = [14, 9, 15, 21, 94, 95, 89, 101, 0, 35]
        let hot = RGBColor(red: 255, green: 50, blue: 80)
        let base = RGBColor(red: 15, green: 90, blue: 165)
        for key in F87Layout.allKeys {
            perKeyColors[key.led] = highlight.contains(key.led) ? hot : base
        }
    }

    func applyPresetRainbowSpectrum() {
        recordUndoState()
        let keys = F87Layout.allKeys
        for (idx, key) in keys.enumerated() {
            let hue = Double(idx) / Double(max(1, keys.count))
            perKeyColors[key.led] = RGBColor(color: Color(hue: hue, saturation: 0.9, brightness: 1.0))
        }
    }

    func applyPresetRowWaves() {
        recordUndoState()
        let hues: [Double] = [0.55, 0.46, 0.34, 0.14, 0.03, 0.82]
        for (rowIdx, row) in F87Layout.rows.enumerated() {
            let rowColor = RGBColor(color: Color(hue: hues[rowIdx % hues.count], saturation: 0.88, brightness: 1.0))
            for item in row {
                if case let .key(k) = item {
                    perKeyColors[k.led] = rowColor
                }
            }
        }
    }

    func applyGradientToPerKey() {
        recordUndoState()
        let targets = selectedLEDs.isEmpty ? Set(F87Layout.allKeys.map(\.led)) : selectedLEDs
        let rowCount = max(1, F87Layout.rows.count - 1)
        for (rIdx, row) in F87Layout.rows.enumerated() {
            let keysInRow = row.compactMap { item -> KeyboardKey? in
                if case let .key(k) = item { return k }
                return nil
            }
            let colCount = max(1, keysInRow.count - 1)
            for (cIdx, key) in keysInRow.enumerated() where targets.contains(key.led) {
                let nx = Double(cIdx) / Double(colCount)
                let ny = Double(rIdx) / Double(rowCount)
                let t: Double
                switch gradientDirection {
                case .horizontal: t = nx
                case .vertical: t = ny
                case .radial: t = min(1.0, hypot(nx - 0.5, ny - 0.5) * 1.7)
                }
                let r = UInt8(clamping: Int((Double(selectedColor.red) * (1 - t) + Double(gradientEndColor.red) * t).rounded()))
                let g = UInt8(clamping: Int((Double(selectedColor.green) * (1 - t) + Double(gradientEndColor.green) * t).rounded()))
                let b = UInt8(clamping: Int((Double(selectedColor.blue) * (1 - t) + Double(gradientEndColor.blue) * t).rounded()))
                perKeyColors[key.led] = RGBColor(red: r, green: g, blue: b)
            }
        }
    }

    func undoPerKey() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(perKeyColors)
        perKeyColors = prev
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func redoPerKey() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(perKeyColors)
        perKeyColors = next
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func recordUndoState() {
        undoStack.append(perKeyColors)
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll()
        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    func applyPerKeyToHardware() {
        guard !isBusy else { return }
        stopMusicSyncIfNeeded()
        isBusy = true
        statusTitle = "개별 키 RGB 맵 전송 중…"

        let colors = perKeyColors
        let bri = max(1, brightness)
        let side = sideLightMode
        let service = hidService

        hidQueue.async { [weak self] in
            do {
                let snap = try service.applyPerKeyColors(colors: colors, brightness: bri, sideLightMode: side)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.isConnected = true
                    self.applySnapshotToUI(snap)
                    self.statusTitle = "\(snap.modelName) 연결됨"
                    self.statusDetail = nil
                    self.log("개별 키 RGB (\(colors.count)개 키) 저장 완료 (F87 Pro Custom Mode #18 활성화)")
                    self.showToast("개별 키 RGB 색상이 키보드에 저장되었습니다")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.statusTitle = "개별 키 저장 실패"
                    self.statusDetail = error.localizedDescription
                    self.log("개별 키 RGB 저장 오류: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Key Matrix Remapping (Layers 0..2)

    func loadMatrixLayer(_ layer: Int) {
        guard !isBusy else { return }
        stopMusicSyncIfNeeded()
        isBusy = true
        statusTitle = "레이어 \(layer) 키 매트릭스 읽는 중…"

        let service = hidService
        hidQueue.async { [weak self] in
            do {
                let data = try service.readKeyMatrix(layer: layer)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.matrixLayers[layer] = data
                    self.statusTitle = "\(self.modelName) 연결됨"
                    self.log("레이어 \(layer) 키 매핑 데이터 로드 완료 (504 바이트)")
                    self.showToast("레이어 \(layer) 키 매핑을 불러왔습니다")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.statusTitle = "키 매트릭스 읽기 실패"
                    self.statusDetail = error.localizedDescription
                    self.log("레이어 \(layer) 읽기 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    func currentSlotBytes(for led: Int, in layer: Int) -> [UInt8] {
        guard let matrix = matrixLayers[layer],
              (0..<126).contains(led),
              matrix.count >= (led + 1) * 4 else {
            return [0, 0, 0, 0]
        }
        let start = led * 4
        return Array(matrix[start..<(start + 4)])
    }

    func assignBytesToSelectedKey(_ bytes: [UInt8]) {
        guard bytes.count == 4 else { return }
        let slot = selectedKeyForRemap.led
        if selectedMatrixLayer == 0 && slot == 59 {
            showToast("안전 보호: 기본 레이어의 Fn 키는 변경할 수 없습니다")
            return
        }
        guard var matrix = matrixLayers[selectedMatrixLayer] else {
            showToast("먼저 '현재 레이어 불러오기'를 눌러주세요")
            return
        }
        let start = slot * 4
        for i in 0..<4 {
            matrix[start + i] = bytes[i]
        }
        matrixLayers[selectedMatrixLayer] = matrix
        log("레이어 \(selectedMatrixLayer) [\(selectedKeyForRemap.label)] → \(KeymapCatalog.describe(bytes)) 지정됨")
    }

    func applyMacCommandOptionSwapPreset() {
        guard var matrix = matrixLayers[0] else {
            showToast("먼저 기본 레이어(Layer 0)를 불러와주세요")
            return
        }
        // LWin (slot 11) <-> LAlt (slot 17)
        // Set LWin(11) = LAlt(00 04 00 00), LAlt(17) = LWin/Cmd(00 08 00 00)
        let lwinOffset = 11 * 4
        let laltOffset = 17 * 4
        matrix.replaceSubrange(lwinOffset..<(lwinOffset + 4), with: [0x00, 0x04, 0x00, 0x00])
        matrix.replaceSubrange(laltOffset..<(laltOffset + 4), with: [0x00, 0x08, 0x00, 0x00])
        matrixLayers[0] = matrix
        showToast("LWin ↔ LAlt (Mac ⌘/⌥ 위치) 교환 프리셋이 적용되었습니다. '키보드에 레이어 저장'을 눌러 확정하세요.")
    }

    func applyRightAltToHangulPreset() {
        guard var matrix = matrixLayers[0] else {
            showToast("먼저 기본 레이어(Layer 0)를 불러와주세요")
            return
        }
        // RAlt (slot 53) -> 한/영 (00 00 00 90)
        let raltOffset = 53 * 4
        matrix.replaceSubrange(raltOffset..<(raltOffset + 4), with: [0x00, 0x00, 0x00, 0x90])
        matrixLayers[0] = matrix
        showToast("오른쪽 Alt(RAlt) 키가 '한/영 전환(0x90)'으로 설정되었습니다. '키보드에 레이어 저장'을 눌러 확정하세요.")
    }

    func saveCurrentMatrixLayerToHardware() {
        let layer = selectedMatrixLayer
        guard let matrix = matrixLayers[layer] else {
            showToast("저장할 레이어 데이터가 없습니다. 먼저 레이어를 불러와주세요.")
            return
        }
        guard !isBusy else { return }
        stopMusicSyncIfNeeded()
        isBusy = true
        statusTitle = "레이어 \(layer) 키 매핑 저장 중…"

        let service = hidService
        hidQueue.async { [weak self] in
            do {
                try service.writeKeyMatrix(layer: layer, matrix: matrix)
                let verified = try service.readKeyMatrix(layer: layer)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.matrixLayers[layer] = verified
                    self.statusTitle = "\(self.modelName) 연결됨"
                    self.log("레이어 \(layer) 키 매트릭스 하드웨어 저장 및 검증 완료")
                    self.showToast("레이어 \(layer) 키 매핑이 키보드에 저장되었습니다")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.statusTitle = "키 매핑 저장 실패"
                    self.statusDetail = error.localizedDescription
                    self.log("레이어 \(layer) 저장 오류: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Music Sync (Audio Dance)

    func refreshMicPermissionState() {
        let status = MusicVisualizer.currentPermissionStatus()
        micPermissionGranted = (status == .authorized)
        switch status {
        case .authorized:
            micStatusText = "마이크 권한 승인됨 (실시간 오디오 분석 가능)"
        case .notDetermined:
            micStatusText = "마이크 권한 미요청 (선택 시 권한 팝업 표시)"
        case .denied, .restricted:
            micStatusText = "마이크 권한 거부됨 (시스템 설정 > 마이크에서 허용 필요)"
        @unknown default:
            micStatusText = "마이크 상태 확인 필요"
        }
    }

    func requestMicPermissionNow() {
        Task { @MainActor in
            let granted = await MusicVisualizer.requestMicrophonePermission()
            refreshMicPermissionState()
            if granted {
                showToast("마이크 입력 권한이 확인되었습니다")
                if isMusicSyncActive && !musicDemoMode {
                    startLiveMicrophoneCapture()
                }
            } else {
                showToast("마이크 권한이 거부되었습니다. 시스템 설정 > 마이크에서 허용해주세요.")
            }
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func handleMusicModeChanged() {
        // Immediately stop any previous wave and reset bars to 0 so demo never bleeds into mic mode
        musicVisualizer.stop()
        audioLevels = Array(repeating: 0, count: 11)

        if !musicDemoMode {
            // User selected Real-Time Microphone mode -> check/request permission right away
            Task { @MainActor in
                let granted = await MusicVisualizer.requestMicrophonePermission()
                refreshMicPermissionState()
                if isMusicSyncActive {
                    if granted {
                        startLiveMicrophoneCapture()
                    } else {
                        isMusicSyncActive = false
                        log("마이크 권한이 없어 실시간 마이크 싱크를 시작할 수 없습니다.")
                        showToast("마이크 접근 권한을 허용해주세요")
                    }
                }
            }
        } else if isMusicSyncActive {
            let handler: ([Double]) -> Void = { [weak self] levels in
                Task { @MainActor in
                    self?.handleAudioLevels(levels)
                }
            }
            musicVisualizer.startDemoWave(callback: handler)
            log("뮤직 싱크 소스 전환: 내장 리듬 신디사이저 파형")
            showToast("내장 신디사이저 모드로 전환되었습니다")
        }
    }

    func toggleMusicSync() {
        if isMusicSyncActive {
            stopMusicSyncIfNeeded()
            showToast("뮤직 싱크가 중지되었습니다")
        } else {
            startMusicSync()
        }
    }

    private func startMusicSync() {
        guard isConnected, !isBusy else {
            showToast("먼저 키보드를 연결해주세요")
            return
        }
        audioLevels = Array(repeating: 0, count: 11)

        if musicDemoMode {
            isMusicSyncActive = true
            let handler: ([Double]) -> Void = { [weak self] levels in
                Task { @MainActor in
                    self?.handleAudioLevels(levels)
                }
            }
            musicVisualizer.startDemoWave(callback: handler)
            log("뮤직 싱크 시작 (내장 리듬 신디사이저 모드)")
            showToast("내장 리듬 뮤직 싱크가 시작되었습니다")
        } else {
            Task { @MainActor in
                let granted = await MusicVisualizer.requestMicrophonePermission()
                refreshMicPermissionState()
                guard granted else {
                    isMusicSyncActive = false
                    audioLevels = Array(repeating: 0, count: 11)
                    log("마이크 입력 권한 거부됨: 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 권한을 허용해주세요.")
                    showToast("마이크 권한이 필요합니다 (신디사이저로 대체하지 않음)")
                    return
                }
                isMusicSyncActive = true
                startLiveMicrophoneCapture()
            }
        }
    }

    private func startLiveMicrophoneCapture() {
        let handler: ([Double]) -> Void = { [weak self] levels in
            Task { @MainActor in
                self?.handleAudioLevels(levels)
            }
        }
        do {
            try musicVisualizer.startMicrophone(callback: handler)
            log("뮤직 싱크 시작 (실시간 마이크 오디오 입력 분석 중)")
            showToast("실시간 마이크 입력 뮤직 싱크가 시작되었습니다")
        } catch {
            // Never silently fall back to demo wave! Stop cleanly and show the exact error.
            musicVisualizer.stop()
            isMusicSyncActive = false
            audioLevels = Array(repeating: 0, count: 11)
            log("실시간 마이크 시작 실패: \(error.localizedDescription)")
            showToast("마이크 시작 실패: \(error.localizedDescription)")
        }
    }

    func stopMusicSyncIfNeeded() {
        guard isMusicSyncActive else { return }
        musicVisualizer.stop()
        isMusicSyncActive = false
        audioLevels = Array(repeating: 0, count: 11)
        let service = hidService
        hidQueue.async {
            service.stopLiveStream()
        }
    }

    private func handleAudioLevels(_ rawLevels: [Double]) {
        guard isMusicSyncActive else { return }
        let scaled = rawLevels.map { min(1.0, max(0.0, $0 * musicSensitivity)) }
        audioLevels = scaled

        guard !audioStreamFrameInFlight else { return }
        audioStreamFrameInFlight = true

        var colors: [Int: RGBColor] = [:]
        let meterPalette: [RGBColor] = [
            RGBColor(red: 0, green: 240, blue: 160),
            RGBColor(red: 0, green: 215, blue: 255),
            RGBColor(red: 80, green: 130, blue: 255),
            RGBColor(red: 190, green: 70, blue: 255),
            RGBColor(red: 255, green: 50, blue: 140),
            RGBColor(red: 255, green: 60, blue: 40)
        ]

        for (colIdx, columnLEDs) in F87Layout.audioColumns.enumerated() where colIdx < scaled.count {
            let activeCount = Int((scaled[colIdx] * Double(columnLEDs.count)).rounded())
            guard activeCount > 0 else { continue }
            for i in 0..<min(activeCount, columnLEDs.count) {
                let led = columnLEDs[i]
                if musicColorMode == 0 {
                    let tier = min(meterPalette.count - 1, (i * meterPalette.count) / max(1, columnLEDs.count))
                    colors[led] = meterPalette[tier]
                } else {
                    colors[led] = selectedColor
                }
            }
        }

        let service = hidService
        hidQueue.async { [weak self] in
            try? service.streamLiveColors(colors)
            DispatchQueue.main.async {
                self?.audioStreamFrameInFlight = false
            }
        }
    }

    // MARK: - Factory Reset

    func performFactoryReset() {
        guard !isBusy else { return }
        stopMusicSyncIfNeeded()
        isBusy = true
        statusTitle = "공장 초기화 진행 중…"

        let service = hidService
        hidQueue.async { [weak self] in
            do {
                let snap = try service.restoreFactoryDefaults()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.applySnapshotToUI(snap)
                    self.statusTitle = "\(snap.modelName) 연결됨"
                    self.log("공장 초기화 완료 (기본 네온 스트림 조명 및 5분 절전 복원)")
                    self.showToast("키보드 설정이 공장 초기값으로 복원되었습니다")
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.statusTitle = "초기화 실패"
                    self.statusDetail = error.localizedDescription
                    self.log("공장 초기화 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Profiles Management

    func saveCurrentAsProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "내 프로필 \(profiles.count + 1)" : trimmed
        let profile = F87Profile(
            effect: selectedEffect,
            brightness: brightness,
            speed: speed,
            colorful: colorful,
            color: selectedColor,
            sideLightMode: sideLightMode,
            perKey: perKeyColors
        )
        profiles.insert(StoredProfile(name: finalName, profile: profile), at: 0)
        saveProfilesToDisk()
        showToast("'\(finalName)' 프로필이 저장되었습니다")
    }

    func applyStoredProfile(_ stored: StoredProfile) {
        let p = stored.profile
        selectedEffect = p.effect
        brightness = p.brightness
        speed = p.speed
        colorful = p.colorful
        selectedColor = p.color
        sideLightMode = p.sideLightMode
        if !p.perKey.isEmpty {
            perKeyColors = p.perKey
        }
        if p.effect == LightingEffect.customPerKeyID && !p.perKey.isEmpty {
            applyPerKeyToHardware()
        } else {
            applyLightingAndSettingsToHardware()
        }
    }

    func deleteStoredProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        saveProfilesToDisk()
    }

    private func loadProfilesFromDisk() {
        if let data = try? Data(contentsOf: profilesURL),
           let decoded = try? JSONDecoder().decode([StoredProfile].self, from: data) {
            profiles = decoded
        } else {
            // Seed starter profiles
            profiles = [
                StoredProfile(
                    name: "사이버펑크 네온 스트림",
                    profile: F87Profile(effect: 11, brightness: 4, speed: 3, colorful: true, color: .cyan, sideLightMode: 1, perKey: [:])
                ),
                StoredProfile(
                    name: "아이스 시안 상시 점등",
                    profile: F87Profile(effect: 1, brightness: 4, speed: 2, colorful: false, color: .cyan, sideLightMode: 3, perKey: [:])
                ),
                StoredProfile(
                    name: "차분한 퍼플 숨쉬기",
                    profile: F87Profile(effect: 2, brightness: 3, speed: 2, colorful: false, color: .neonPurple, sideLightMode: 4, perKey: [:])
                )
            ]
        }
    }

    private func saveProfilesToDisk() {
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: profilesURL, options: .atomic)
        }
    }

    // MARK: - Helpers

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    func log(_ entry: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: .now))] \(entry)"
        logs.insert(line, at: 0)
        if logs.count > 100 {
            logs.removeLast()
        }
        let logURL = profilesURL.deletingLastPathComponent().appendingPathComponent("runtime.log")
        let body = logs.prefix(30).joined(separator: "\n")
        try? body.write(to: logURL, atomically: true, encoding: .utf8)
    }
}
