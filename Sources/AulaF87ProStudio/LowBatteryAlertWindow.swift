import AppKit
import SwiftUI

// MARK: - Custom Full Screen Borderless Window with Key Handling
final class LowBatteryOverlayWindow: NSWindow {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Manager for Monitor-Wide Full-Screen Emergency Warning
final class LowBatteryOverlayManager: ObservableObject {
    static let shared = LowBatteryOverlayManager()

    private var activeWindows: [LowBatteryOverlayWindow] = []
    private(set) var isCurrentlyPresented: Bool = false

    private init() {}

    func show(vm: AppViewModel, isTest: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideNow()

            let screens = NSScreen.screens
            guard !screens.isEmpty else { return }

            for screen in screens {
                let window = LowBatteryOverlayWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                window.isReleasedWhenClosed = false

                window.level = .screenSaver
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                window.setFrame(screen.frame, display: true)

                let isMainScreen = (screen == NSScreen.main || screens.count == 1)

                let rootView = FullScreenEmergencyAlertView(
                    vm: vm,
                    isTest: isTest,
                    isMainDisplay: isMainScreen,
                    onDismiss: { [weak self] in
                        self?.hide()
                        vm.dismissLowBatteryBanner(snoozeMinutes: isTest ? 0 : 10)
                    },
                    onEmergencyEco: {
                        vm.applyEmergencyEcoMode()
                    }
                )

                window.contentView = NSHostingView(rootView: rootView)
                window.onDismiss = { [weak self] in
                    self?.hide()
                    vm.dismissLowBatteryBanner(snoozeMinutes: isTest ? 0 : 10)
                }

                window.makeKeyAndOrderFront(nil)
                self.activeWindows.append(window)
            }

            self.isCurrentlyPresented = true
            NSApp.activate(ignoringOtherApps: true)
            if let snd = NSSound(named: "Sosumi") {
                snd.play()
            } else {
                NSSound.beep()
            }
        }
    }

    func hide() {
        if Thread.isMainThread {
            hideNow()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.hideNow()
            }
        }
    }

    private func hideNow() {
        for win in activeWindows {
            win.onDismiss = nil
            win.orderOut(nil)
            win.contentView = nil
        }
        activeWindows.removeAll()
        isCurrentlyPresented = false
    }
}

// MARK: - Menacing Full-Screen Emergency View
struct FullScreenEmergencyAlertView: View {
    @ObservedObject var vm: AppViewModel
    let isTest: Bool
    let isMainDisplay: Bool
    let onDismiss: () -> Void
    let onEmergencyEco: () -> Void

    @State private var isPulsing: Bool = false
    @State private var stripeOffset: CGFloat = 0

    var displayPercent: Int {
        if isTest {
            return min(vm.effectiveBattery.percent, 10)
        } else {
            return vm.effectiveBattery.percent
        }
    }

    var body: some View {
        ZStack {
            // 1. Dark Menacing Background with Pulsing Blood-Red Radial Vignette
            Color.black.opacity(0.88)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.red.opacity(isPulsing ? 0.40 : 0.15)
                ]),
                center: .center,
                startRadius: 200,
                endRadius: 900
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 2. Screen Perimeter Hazard Border (Pulsing 10px Glow)
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.red,
                            Color.orange,
                            Color.red,
                            Color(red: 0.8, green: 0, blue: 0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isPulsing ? 10 : 6
                )
                .shadow(color: Color.red.opacity(isPulsing ? 0.9 : 0.4), radius: isPulsing ? 30 : 12)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // 3. Top & Bottom Hazard Caution Tape Bars
            VStack {
                hazardCautionTape(text: "⚠️ CRITICAL HARDWARE ALERT · KEYBOARD BATTERY LOW (10% 이하) · 즉시 케이블 연결 요망 ⚠️")
                Spacer()
                hazardCautionTape(text: "⚡ 무선 통신 두절 임박 · USB 충전 케이블 연결 시 이 전체 화면 경고는 자동으로 해제됩니다 ⚡")
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // 4. Central Emergency Console (Main Screen only, or on all screens)
            VStack(spacing: 24) {
                // Warning Beacon & Header Badge
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                            .scaleEffect(isPulsing ? 1.3 : 0.9)
                            .shadow(color: .red, radius: isPulsing ? 12 : 4)

                        Text("🚨 [CRITICAL HARDWARE EMERGENCY] 하드웨어 긴급 방전 경보")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundStyle(.red)

                        if isTest {
                            Text("🧪 시뮬레이션 테스트 모드")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.18))
                            .overlay(Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1.5))
                    )

                    Text("AULA F87 Pro 배터리 방전 위험 (10% 이하)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, Color(red: 1.0, green: 0.85, blue: 0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.red.opacity(0.8), radius: 15)

                    Text("키보드 내장 배터리 전원이 소진되어 무선 연결(Bluetooth/2.4G) 차단이 임박했습니다.\n작업 데이터 손실 및 입력 차단을 방지하기 위해 지금 즉시 USB-C 충전 케이블을 연결하십시오.")
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: 680)
                }

                // Telemetry HUD Box
                HStack(spacing: 24) {
                    // Big Battery Digits
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(isPulsing ? 0.35 : 0.20))
                                .frame(width: 110, height: 110)
                                .scaleEffect(isPulsing ? 1.08 : 0.95)

                            Circle()
                                .stroke(Color.red, lineWidth: 3)
                                .frame(width: 95, height: 95)

                            VStack(spacing: 0) {
                                Text("\(displayPercent)%")
                                    .font(.system(size: 36, weight: .black, design: .monospaced))
                                    .foregroundStyle(.red)
                                Text("잔여 배터리")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        Text("⚠️ 방전 진행 중")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                    .padding(.trailing, 10)

                    Divider()
                        .background(Color.red.opacity(0.3))
                        .frame(height: 110)

                    // Key Telemetry Points
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.cyan)
                                .frame(width: 20)
                            Text("현재 연결 방식:").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                            Text(vm.connectionMode).font(.system(size: 13, weight: .heavy)).foregroundStyle(.cyan)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .foregroundStyle(.orange)
                                .frame(width: 20)
                            Text("예상 유지 시간:").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                            Text(formatUsageHours(vm.powerTelemetry.remainingUsageHours))
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.orange)
                            Text("(LED 켜짐 시 약 15분 미만)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.green)
                                .frame(width: 20)
                            Text("케이블 연결 시:").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                            Text("USB 케이블 연결 즉시 전체 화면 경고 자동 해제")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: 420)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.35), lineWidth: 1))
                )

                // Action Buttons
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        Button {
                            onEmergencyEco()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.slash.fill")
                                    .font(.headline)
                                Text("💡 조명 즉시 끄고 비상 절전 (배터리 수명 최대화)")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button {
                            onDismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isTest ? "xmark.circle.fill" : "clock.arrow.circlepath")
                                Text(isTest ? "테스트 종료 (닫기)" : "10분 동안 일시 닫기 (작업 계속)")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }

                    Text("⌨️ 키보드 ESC 키를 누르면 경고 화면이 즉시 닫힙니다.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.red, Color.orange, Color.red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                    )
                    .shadow(color: Color.red.opacity(isPulsing ? 0.75 : 0.40), radius: isPulsing ? 45 : 25)
            )
            .frame(maxWidth: 820)
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func hazardCautionTape(text: String) -> some View {
        HStack(spacing: 12) {
            Text("///")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(Color.yellow)
            Text(text)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
            Text("///")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(Color.yellow)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            Color(red: 0.6, green: 0.05, blue: 0.05)
                .overlay(
                    Rectangle().stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                )
        )
    }
}
