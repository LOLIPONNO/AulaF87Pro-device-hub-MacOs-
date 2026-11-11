import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: AppViewModel
    @State private var newProfileName: String = ""
    @State private var showResetConfirm = false

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 220, ideal: 235, max: 260)
        } detail: {
            VStack(spacing: 0) {
                topStatusBar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Interactive 87-Key TKL Preview Canvas at the top of the workspace
                        VStack(alignment: .center, spacing: 8) {
                            HStack {
                                Label(canvasHeaderTitle, systemImage: "keyboard")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(canvasHintText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)

                            KeyboardCanvasView(vm: vm, mode: currentCanvasMode)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        )

                        // Tab-specific Control Panel
                        tabDetailContent
                    }
                    .padding(20)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = vm.toastMessage {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.82))
                                .shadow(radius: 8)
                        )
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.toastMessage)
        }
        .frame(minWidth: 1080, minHeight: 760)
        .alert("키보드 설정을 공장 초기값으로 복원할까요?", isPresented: $showResetConfirm) {
            Button("취소", role: .cancel) {}
            Button("공장 초기화 실행", role: .destructive) {
                vm.performFactoryReset()
            }
        } message: {
            Text("조명 효과(네온 스트림), 팔레트 색상, 절전 타이머(5분), 디바운스 설정이 출고 초기 상태로 복원됩니다.")
        }
    }

    private var currentCanvasMode: KeyboardCanvasMode {
        switch vm.currentTab {
        case .batteryMonitor: return .effectPreview
        case .perKey: return .perKeyPainter
        case .keymap: return .keyRemapInspector
        case .music: return vm.isMusicSyncActive ? .musicVisualizer : .effectPreview
        default: return .effectPreview
        }
    }

    private var canvasHeaderTitle: String {
        switch vm.currentTab {
        case .batteryMonitor:
            return vm.powerTelemetry.isReactiveMode
                ? "AULA F87 Pro V1 실시간 전력 모니터 (반응형 타건 모드 · 키 미입력 시 암전)"
                : "AULA F87 Pro V1 실시간 하드웨어 전력 & 조명 연동 상태"
        case .perKey: return "87키 TKL 개별 키 RGB 캔버스 (클릭하여 키 색상 지정)"
        case .keymap: return "87키 TKL 키 매핑 인스펙터 (변경할 키를 클릭하세요)"
        case .music: return "87키 TKL 11밴드 오디오 스펙트럼 실시간 프리뷰"
        default: return "AULA F87 Pro V1 실시간 조명 & 측면 RGB 프리뷰"
        }
    }

    private var canvasHintText: String {
        switch vm.currentTab {
        case .batteryMonitor:
            let tel = vm.powerTelemetry
            if tel.isReactiveMode {
                return tel.isActivelyTyping
                    ? "반응형 실시간 타건 중 (\(tel.typingSpeedCPM)타/분): 소비 전력 약 \(Int(tel.totalPowerMw))mW (\(Int(tel.totalDischargeCurrentMa))mA) · 잔여 약 \(formatHours(tel.remainingUsageHours))"
                    : "반응형 타건 대기: 키 미입력으로 백라이트 완전 소등 (0mA) · 초절전 상태 · 잔여 약 \(formatHours(tel.remainingUsageHours))"
            }
            return tel.isCharging
                ? "충전 중: 약 \(String(format: "%.2f", tel.chargingPowerW))W (+약 \(Int(tel.chargingCurrentMa))mA) · 완충까지 약 \(formatHours(tel.timeToFullChargeHours))"
                : "배터리 잔량 \(tel.percent)% · 소비 전력 약 \(String(format: "%.2f", tel.totalPowerW))W (\(Int(tel.totalDischargeCurrentMa))mA) · 약 \(formatHours(tel.remainingUsageHours)) 사용 가능"
        case .perKey: return "색칠된 키: \(vm.perKeyColors.count)개 · 선택된 키: \(vm.selectedLEDs.count)개"
        case .keymap: return "선택된 키: \(vm.selectedKeyForRemap.label) (슬롯 #\(vm.selectedKeyForRemap.led)) · 레이어 \(vm.selectedMatrixLayer)"
        default: return "현재 효과: \(vm.selectedEffectInfo.titleKo) (\(vm.selectedEffectInfo.titleEn)) · 밝기 \(vm.brightness)/4 · 속도 \(vm.speed)/4"
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard.badge.eye.fill")
                        .font(.title2)
                        .foregroundStyle(Color.cyan)
                    Text("F87 Pro Studio")
                        .font(.title3.bold())
                }
                Text("AULA F87 Pro V1 전용 설정 앱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            List(NavigationTab.allCases, selection: $vm.currentTab) { tab in
                Label(tab.rawValue, systemImage: tab.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.vertical, 4)
                    .tag(tab)
            }
            .listStyle(.sidebar)

            Divider()

            // Quick Hardware Status Footer in Sidebar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(vm.statusTitle)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                Text(vm.connectionMode)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let bat = vm.battery {
                    HStack(spacing: 6) {
                        Image(systemName: batterySymbol(for: bat))
                            .foregroundStyle(batteryColor(for: bat))
                        Text(bat.isCharging ? "충전 중 (\(bat.percent)%)" : "배터리 잔량: \(bat.percent)%")
                            .font(.caption.bold())
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Top Status Bar

    private var topStatusBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(vm.isConnected ? Color.green : (vm.isBusy ? Color.orange : Color.red))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.statusTitle)
                        .font(.system(size: 13, weight: .bold))
                    if let detail = vm.statusDetail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else {
                        Text(vm.connectionMode)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let bat = vm.battery {
                Divider().frame(height: 22)
                HStack(spacing: 6) {
                    Image(systemName: batterySymbol(for: bat))
                        .font(.system(size: 14))
                        .foregroundStyle(batteryColor(for: bat))
                    Text("\(bat.percent)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(bat.isCharging ? "충전 중" : "무선 사용 중")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            if let lat = vm.latencyStats {
                Divider().frame(height: 22)
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13))
                        .foregroundStyle(lat.currentRttMs < 3.0 ? Color.green : (lat.currentRttMs < 10.0 ? Color.cyan : Color.orange))
                    Text("\(String(format: "%.1f", lat.currentRttMs)) ms")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(lat.currentRttMs < 3.0 ? Color.green : (lat.currentRttMs < 10.0 ? Color.cyan : Color.orange))
                    Text("(\(lat.pollingRateHz)Hz)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            Spacer()

            if vm.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            if let detail = vm.statusDetail, detail.contains("입력 모니터링") {
                Button {
                    vm.openInputMonitoringSettings()
                } label: {
                    Label("입력 모니터링 권한 열기", systemImage: "lock.shield")
                }
                .controlSize(.small)
            }

            Button {
                vm.refreshFromHardware()
            } label: {
                Label("상태 새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(vm.isBusy)

            Button {
                if vm.currentTab == .perKey {
                    vm.applyPerKeyToHardware()
                } else {
                    vm.applyLightingAndSettingsToHardware()
                }
            } label: {
                Label("키보드에 즉시 적용", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(vm.isBusy || !vm.isConnected)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab Contents

    @ViewBuilder
    private var tabDetailContent: some View {
        switch vm.currentTab {
        case .batteryMonitor:
            batteryMonitorTabView
        case .lighting:
            lightingTabView
        case .perKey:
            perKeyTabView
        case .sideLight:
            sideLightTabView
        case .keymap:
            keymapTabView
        case .music:
            musicTabView
        case .performance:
            performanceTabView
        case .profiles:
            profilesTabView
        }
    }

    // MARK: - 1. Lighting Tab

    private var lightingTabView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Effect Grid
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("백라이트 조명 효과 (16종)", systemImage: "sparkles")
                            .font(.headline)
                        Spacer()
                        Button("선택한 효과 키보드에 저장") {
                            vm.applyLightingAndSettingsToHardware()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isBusy || !vm.isConnected)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                        ForEach(LightingEffect.all) { effect in
                            let selected = vm.selectedEffect == effect.id
                            Button {
                                vm.selectedEffect = effect.id
                                if !effect.supportsColor && effect.id != 0 {
                                    vm.colorful = true
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: effect.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(selected ? Color.cyan : Color.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(effect.titleKo)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text(effect.titleEn)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selected ? Color.cyan.opacity(0.16) : Color.primary.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(selected ? Color.cyan : Color.clear, lineWidth: 1.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(8)
            }

            // Brightness, Speed, Color Controls
            HStack(alignment: .top, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("밝기 및 애니메이션 속도", systemImage: "slider.horizontal.3")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("밝기 단계 (Brightness)")
                                Spacer()
                                Text("\(vm.brightness) / 4 단계")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.cyan)
                            }
                            Picker("밝기", selection: $vm.brightness) {
                                ForEach(0...4, id: \.self) { level in
                                    Text(level == 0 ? "0 (꺼짐)" : "\(level)단계").tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("애니메이션 속도 (Speed)")
                                Spacer()
                                Text(vm.selectedEffectInfo.supportsSpeed ? "\(vm.speed) / 4 단계" : "고정 효과")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(vm.selectedEffectInfo.supportsSpeed ? .cyan : .secondary)
                            }
                            Picker("속도", selection: $vm.speed) {
                                ForEach(0...4, id: \.self) { level in
                                    Text("\(level + 1)단").tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(!vm.selectedEffectInfo.supportsSpeed)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("색상 모드 & RGB 팔레트", systemImage: "paintpalette.fill")
                            .font(.headline)

                        if vm.selectedEffectInfo.supportsColor {
                            Toggle("레인보우 다채로운 색상 (Colorful 멀티컬러 모드)", isOn: $vm.colorful)
                                .toggleStyle(.switch)

                            if !vm.colorful {
                                HStack(spacing: 12) {
                                    ColorPicker("사용자 지정 단색", selection: Binding(
                                        get: { vm.selectedColor.color },
                                        set: { vm.selectedColor = RGBColor(color: $0) }
                                    ), supportsOpacity: false)
                                    Text(vm.selectedColor.hex)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                                }

                                HStack(spacing: 8) {
                                    ForEach(RGBColor.presets, id: \.name) { preset in
                                        Button {
                                            vm.selectedColor = preset.color
                                            vm.colorful = false
                                        } label: {
                                            Circle()
                                                .fill(preset.color.color)
                                                .frame(width: 24, height: 24)
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(vm.selectedColor == preset.color ? Color.white : Color.clear, lineWidth: 2)
                                                )
                                                .help(preset.name)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        } else if vm.selectedEffect == LightingEffect.customPerKeyID {
                            Text("개별 키 커스텀 모드입니다. '개별 키 RGB 페인터' 탭에서 키별 색상을 직접 칠하고 저장할 수 있습니다.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("개별 키 RGB 페인터 열기") {
                                vm.currentTab = .perKey
                            }
                        } else {
                            Text("선택한 효과(\(vm.selectedEffectInfo.titleKo))는 하드웨어 전용 무지개 팔레트로 동작합니다.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 2. Per-Key RGB Painter Tab

    private var perKeyTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("개별 키 RGB 페인팅 도구", systemImage: "paintbrush.pointed.fill")
                            .font(.headline)
                        Spacer()
                        Button {
                            vm.undoPerKey()
                        } label: {
                            Label("실행 취소", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!vm.canUndo)

                        Button {
                            vm.redoPerKey()
                        } label: {
                            Label("다시 실행", systemImage: "arrow.uturn.forward")
                        }
                        .disabled(!vm.canRedo)

                        Button {
                            vm.applyPerKeyToHardware()
                        } label: {
                            Label("개별 키 RGB 키보드에 저장", systemImage: "tray.and.arrow.down.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .disabled(vm.isBusy || !vm.isConnected)
                    }

                    HStack(spacing: 16) {
                        Picker("도구", selection: $vm.perKeyTool) {
                            ForEach(PerKeyTool.allCases) { tool in
                                Label(tool.rawValue, systemImage: tool.systemSymbol).tag(tool)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 380)

                        ColorPicker("브러시 색상", selection: Binding(
                            get: { vm.selectedColor.color },
                            set: { vm.selectedColor = RGBColor(color: $0) }
                        ), supportsOpacity: false)

                        HStack(spacing: 6) {
                            ForEach(RGBColor.presets, id: \.name) { preset in
                                Button {
                                    vm.selectedColor = preset.color
                                } label: {
                                    Circle()
                                        .fill(preset.color.color)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    // Group Selection & Quick Fill (2 clean rows so buttons never wrap vertically)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("영역 선택:")
                                .font(.subheadline.bold())
                            Button("전체 선택") { vm.selectKeyGroup("all") }
                            Button("선택 해제") { vm.selectKeyGroup("none") }
                            Button("WASD") { vm.selectKeyGroup("wasd") }
                            Button("방향키") { vm.selectKeyGroup("arrows") }
                            Button("F1~F12") { vm.selectKeyGroup("fkeys") }
                            Button("숫자 1~0") { vm.selectKeyGroup("numbers") }
                            Button("모디파이어") { vm.selectKeyGroup("modifiers") }
                            Spacer()
                            Button("선택/전체 채우기") { vm.fillTargetKeysWithSelectedColor() }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                            Button("선택/전체 지우기") { vm.clearTargetKeys() }
                        }
                        .controlSize(.small)

                        HStack(spacing: 10) {
                            Text("테마 프리셋:")
                                .font(.subheadline.bold())
                            Button("게이밍 (WASD+방향키)") { vm.applyPresetWASDGaming() }
                            Button("무지개 스펙트럼") { vm.applyPresetRainbowSpectrum() }
                            Button("행별 네온 웨이브") { vm.applyPresetRowWaves() }

                            Divider().frame(height: 18)

                            Picker("그라데이션", selection: $vm.gradientDirection) {
                                ForEach(GradientDirection.allCases) { dir in
                                    Text(dir.rawValue).tag(dir)
                                }
                            }
                            .frame(width: 145)

                            ColorPicker("끝 색상", selection: Binding(
                                get: { vm.gradientEndColor.color },
                                set: { vm.gradientEndColor = RGBColor(color: $0) }
                            ), supportsOpacity: false)

                            Button("그라데이션 채우기") {
                                vm.applyGradientToPerKey()
                            }
                            Spacer()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - 3. Side Light & Light Bar Tab

    private var sideLightTabView: some View {
        HStack(alignment: .top, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("양측면 RGB 조명 (Side Lights)", systemImage: "light.strip.2")
                        .font(.headline)
                    Text("키보드 좌우 측면 RGB 스트립의 효과를 설정합니다. (하드웨어 단축키: Fn + Right Shift)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(SideLightMode.all) { mode in
                        let selected = vm.sideLightMode == mode.id
                        Button {
                            vm.sideLightMode = mode.id
                        } label: {
                            HStack {
                                Image(systemName: mode.icon)
                                    .foregroundStyle(selected ? Color.cyan : Color.secondary)
                                    .frame(width: 24)
                                Text(mode.titleKo)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("(\(mode.titleEn))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.cyan)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? Color.cyan.opacity(0.15) : Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button("측면 조명 설정 저장") {
                        vm.applyLightingAndSettingsToHardware()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isBusy || !vm.isConnected)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("방향키 상단 라이트바 & 하드웨어 단축키 안내", systemImage: "sparkles.rectangle.stack")
                        .font(.headline)

                    Picker("상단 라이트바 모드", selection: $vm.lightBarMode) {
                        ForEach(SideLightMode.all) { mode in
                            Text(mode.titleKo).tag(mode.id)
                        }
                    }

                    Text("※ 참고: AULA F87 Pro 펌웨어 특성상 방향키 상단 라이트바는 키보드 자체 단축키(Fn + Left Shift)로 전환할 때 가장 확실하게 반영됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("F87 Pro V1 필수 하드웨어 FN 단축키")
                            .font(.subheadline.bold())
                        shortcutRow("Fn + B", "라이트바로 실시간 배터리 잔량 확인 (초록=충분, 빨강=부족)")
                        shortcutRow("Fn + Right Shift", "좌우 측면 RGB 조명 모드 순환")
                        shortcutRow("Fn + Left Shift", "방향키 위 라이트바 모드 순환")
                        shortcutRow("Fn + Ins / Del", "메인 백라이트 효과 전환 / 색상 전환")
                        shortcutRow("Fn + ↑ / ↓ / ← / →", "백라이트 밝기 조절 / 애니메이션 속도 조절")
                        shortcutRow("Fn + W / E", "Windows 모드 전환 (Fn+W) / Mac 모드 전환 (Fn+E)")
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func shortcutRow(_ keys: String, _ desc: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(.caption, design: .monospaced).bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.cyan.opacity(0.15)))
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 4. Key Matrix Remapping Tab

    private var keymapTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                HStack(spacing: 16) {
                    Picker("편집할 레이어", selection: $vm.selectedMatrixLayer) {
                        Text("기본 레이어 (Layer 0)").tag(0)
                        Text("FN1 레이어 (Fn 조합)").tag(1)
                        Text("FN2 레이어 (Tap)").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)

                    Button {
                        vm.loadMatrixLayer(vm.selectedMatrixLayer)
                    } label: {
                        Label("현재 레이어 키보드에서 불러오기", systemImage: "arrow.down.doc.fill")
                    }
                    .disabled(vm.isBusy || !vm.isConnected)

                    Button {
                        vm.saveCurrentMatrixLayerToHardware()
                    } label: {
                        Label("키보드에 레이어 저장", systemImage: "checkmark.seal.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(vm.isBusy || !vm.isConnected || vm.matrixLayers[vm.selectedMatrixLayer] == nil)

                    Spacer()
                }
                .padding(8)
            }

            HStack(alignment: .top, spacing: 16) {
                // Selected Key Details & Quick Mac/KR Presets
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("선택된 키 정보", systemImage: "key.fill")
                            .font(.headline)

                        let currentBytes = vm.currentSlotBytes(for: vm.selectedKeyForRemap.led, in: vm.selectedMatrixLayer)
                        HStack(spacing: 14) {
                            Text(vm.selectedKeyForRemap.label)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .frame(width: 76, height: 52)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.cyan.opacity(0.18)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("현재 할당된 동작: \(KeymapCatalog.describe(currentBytes))")
                                    .font(.subheadline.bold())
                                Text(String(format: "슬롯 #%d · 원시 바이트: [%02X %02X %02X %02X]",
                                            vm.selectedKeyForRemap.led,
                                            currentBytes[0], currentBytes[1], currentBytes[2], currentBytes[3]))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        Text("원클릭 한국어 / Mac 편의 프리셋 (Layer 0 전용)")
                            .font(.subheadline.bold())

                        Button {
                            vm.applyRightAltToHangulPreset()
                        } label: {
                            Label("오른쪽 Alt(RAlt) → '한/영 전환(Lang1)' 키로 매핑", systemImage: "globe.asia.australia.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            vm.applyMacCommandOptionSwapPreset()
                        } label: {
                            Label("왼쪽 Win ↔ Alt 위치를 Mac 배열(⌥ Option / ⌘ Command)로 교환", systemImage: "command")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()

                        Text("사용자 정의 단축키 조합 만들기")
                            .font(.subheadline.bold())

                        HStack(spacing: 8) {
                            ForEach(KeymapCatalog.modifierBitNames.prefix(4), id: \.bit) { mod in
                                let isOn = (vm.customComboMods & mod.bit) != 0
                                Button(mod.name) {
                                    if isOn { vm.customComboMods &= ~mod.bit }
                                    else { vm.customComboMods |= mod.bit }
                                }
                                .buttonStyle(.bordered)
                                .tint(isOn ? .cyan : .secondary)
                            }
                        }

                        HStack {
                            Picker("일반 키", selection: $vm.customComboKey) {
                                ForEach(KeymapCatalog.hidKeyNames.sorted(by: { $0.key < $1.key }), id: \.key) { code, name in
                                    Text(name).tag(code)
                                }
                            }
                            Button("조합 할당") {
                                vm.assignBytesToSelectedKey([0x00, vm.customComboMods, 0x00, vm.customComboKey])
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(8)
                    .frame(width: 390, alignment: .leading)
                }

                // Action Catalog
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("할당할 기능 선택 (클릭 시 선택된 키에 즉시 반영)", systemImage: "list.bullet.rectangle")
                                .font(.headline)
                            Spacer()
                            Picker("분류", selection: $vm.selectedRemapCategory) {
                                Text("추천 / Mac & 한국어").tag("추천 / Mac & 한국어")
                                Text("멀티미디어").tag("멀티미디어")
                                Text("키보드 내장 기능").tag("키보드 내장 기능")
                                Text("마우스 동작").tag("마우스 동작")
                                Text("일반 키").tag("일반 키")
                            }
                            .frame(width: 220)
                        }

                        let filtered = KeymapCatalog.presets.filter { $0.category == vm.selectedRemapCategory }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 8)], spacing: 8) {
                            ForEach(filtered) { item in
                                Button {
                                    vm.assignBytesToSelectedKey(item.bytes)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text(item.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.primary.opacity(0.05))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear {
            if vm.matrixLayers[vm.selectedMatrixLayer] == nil && vm.isConnected && !vm.isBusy {
                vm.loadMatrixLayer(vm.selectedMatrixLayer)
            }
        }
        .onChange(of: vm.selectedMatrixLayer) { _, newLayer in
            if vm.matrixLayers[newLayer] == nil && vm.isConnected && !vm.isBusy {
                vm.loadMatrixLayer(newLayer)
            }
        }
    }

    // MARK: - 5. Music Sync Tab

    private var musicTabView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("실시간 오디오 리액티브 이퀄라이저 (Audio Dance)", systemImage: "waveform.badge.mic")
                            .font(.headline)
                        Text("11개 주파수 대역의 에너지를 실시간 분석하여 키보드 11개 열에 스펙트럼 바로 스트리밍합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.toggleMusicSync()
                    } label: {
                        Label(
                            vm.isMusicSyncActive ? "뮤직 싱크 중지" : "뮤직 싱크 시작",
                            systemImage: vm.isMusicSyncActive ? "stop.circle.fill" : "play.circle.fill"
                        )
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isMusicSyncActive ? .red : .cyan)
                    .disabled(!vm.isConnected)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 20) {
                        Picker("오디오 소스", selection: $vm.musicDemoMode) {
                            Text("내장 신디사이저 파형").tag(true)
                            Text("실시간 마이크 입력").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 340)

                        Picker("색상 스타일", selection: $vm.musicColorMode) {
                            Text("멀티컬러 스펙트럼").tag(0)
                            Text("사용자 지정 단색").tag(1)
                        }
                        .frame(width: 220)

                        HStack(spacing: 8) {
                            Text("감도 \(String(format: "%.1fx", vm.musicSensitivity))")
                                .font(.caption.monospacedDigit())
                                .frame(width: 68, alignment: .leading)
                            Slider(value: $vm.musicSensitivity, in: 0.5...2.5)
                                .frame(width: 130)
                        }
                        Spacer()
                    }

                    if !vm.musicDemoMode {
                        HStack(spacing: 10) {
                            Image(systemName: vm.micPermissionGranted ? "mic.fill" : "mic.slash.fill")
                                .foregroundStyle(vm.micPermissionGranted ? Color.green : Color.orange)
                            Text(vm.micStatusText)
                                .font(.caption.bold())
                                .foregroundStyle(vm.micPermissionGranted ? Color.primary : Color.orange)
                            Spacer()
                            if !vm.micPermissionGranted {
                                Button("마이크 권한 요청") {
                                    vm.requestMicPermissionNow()
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            Button("시스템 마이크 권한 설정 열기") {
                                vm.openMicrophoneSettings()
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(vm.micPermissionGranted ? Color.green.opacity(0.10) : Color.orange.opacity(0.14))
                        )
                    }
                }
                .onChange(of: vm.musicDemoMode) { _, _ in
                    vm.handleMusicModeChanged()
                }
                .onAppear {
                    vm.refreshMicPermissionState()
                }

                // 11-Band Equalizer Bar Meter Preview
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(0..<11, id: \.self) { band in
                        let level = band < vm.audioLevels.count ? vm.audioLevels[band] : 0
                        VStack(spacing: 6) {
                            GeometryReader { geo in
                                VStack {
                                    Spacer()
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            LinearGradient(
                                                colors: [.pink, .purple, .cyan, .green],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(height: max(6, geo.size.height * level))
                                }
                            }
                            .frame(height: 110)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

                            Text("B\(band + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .padding(10)
        }
    }

    // MARK: - 6. Performance, Power & Backup Tab

    private var performanceTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("키 입력 응답 속도 & 전원 절전 설정", systemImage: "bolt.badge.clock.fill")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("키 디바운스 지연 시간 (Debounce Stage)")
                                Spacer()
                                Text("\(vm.debounceStage)단계 (약 \(vm.debounceStage)ms)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.cyan)
                            }
                            Picker("디바운스", selection: $vm.debounceStage) {
                                Text("1단계 (1ms · 게이밍 최고속)").tag(1)
                                Text("2단계 (2ms)").tag(2)
                                Text("3단계 (3ms · 기본)").tag(3)
                                Text("4단계 (4ms)").tag(4)
                                Text("5단계 (5ms · 채터링 방지)").tag(5)
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("무선 백라이트 자동 절전 타이머 (Sleep Timeout)")
                                Spacer()
                            }
                            Picker("절전 타이머", selection: $vm.sleepRawSteps) {
                                ForEach(SleepTimerOption.all) { opt in
                                    Text(opt.label).tag(opt.rawSteps)
                                }
                            }
                        }

                        HStack {
                            Button("성능 및 절전 설정 키보드에 저장") {
                                vm.applyLightingAndSettingsToHardware()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .disabled(vm.isBusy || !vm.isConnected)

                            Spacer()

                            Button("공장 초기화…", role: .destructive) {
                                showResetConfirm = true
                            }
                            .disabled(vm.isBusy || !vm.isConnected)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("하드웨어 통신 로그 & 안전 검증 상태", systemImage: "terminal.fill")
                            .font(.headline)

                        Text("모든 설정 읽기와 쓰기는 128바이트 서명(5A A5) 및 고정 레지스터 무결성 검증을 통과한 경우에만 실행되며, 자동으로 로컬 백업본이 보관됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, entry in
                                    Text(entry)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(height: 150)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 7. Profiles Tab

    private var profilesTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                HStack(spacing: 12) {
                    Label("현재 조명 & 개별 키 상태를 새 프로필로 저장", systemImage: "plus.square.on.square")
                        .font(.headline)
                    TextField("프로필 이름 (예: 야간 코딩, FPS 게이밍)", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                    Button("프로필 보관함에 추가") {
                        vm.saveCurrentAsProfile(name: newProfileName)
                        newProfileName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding(8)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(vm.profiles) { stored in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle()
                                    .fill(stored.profile.color.color)
                                    .frame(width: 14, height: 14)
                                Text(stored.name)
                                    .font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    vm.deleteStoredProfile(stored.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }

                            let effName = LightingEffect.info(for: stored.profile.effect).titleKo
                            Text("효과: \(effName) · 밝기 \(stored.profile.brightness)/4 · 속도 \(stored.profile.speed)/4")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !stored.profile.perKey.isEmpty {
                                Text("개별 키 색상 \(stored.profile.perKey.count)개 포함")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan)
                            }

                            Button {
                                vm.applyStoredProfile(stored)
                            } label: {
                                Label("불러와서 키보드에 적용", systemImage: "bolt.horizontal.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                        }
                        .padding(6)
                    }
                }
            }
        }
    }

    // MARK: - 0. Battery & Power Monitor Tab

    private var batteryMonitorTabView: some View {
        let tel = vm.powerTelemetry
        return VStack(alignment: .leading, spacing: 18) {
            // Real-time Refresh Status Banner with Configurable Interval
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("\(String(format: "%.1f", vm.refreshInterval))초 실시간 연동")
                        .font(.caption.bold())
                        .foregroundStyle(vm.isConnected ? Color.green : Color.orange)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill((vm.isConnected ? Color.green : Color.orange).opacity(0.12)))

                // Interval Picker Menu
                Menu {
                    Button("0.5초 (초고속 실시간)") { vm.setRefreshInterval(0.5) }
                    Button("1.0초 (표준 권장)") { vm.setRefreshInterval(1.0) }
                    Button("2.0초 (부드러운 연동)") { vm.setRefreshInterval(2.0) }
                    Button("3.0초 (보통 주기)") { vm.setRefreshInterval(3.0) }
                    Button("5.0초 (초절전 모니터링)") { vm.setRefreshInterval(5.0) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption2)
                        Text("주기: \(String(format: "%.1f", vm.refreshInterval))s")
                            .font(.caption2.bold())
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("갱신 시각: \(vm.lastTelemetryUpdate, format: .dateTime.hour().minute().second())")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button {
                    vm.forcePollBatteryNow()
                } label: {
                    Label("지금 갱신", systemImage: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.isBusy)
            }
            .padding(.bottom, -4)

            // 1. Top 4 KPI Metric Cards
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                // Card 1: Battery Level & Cell Voltage
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("배터리 잔량", systemImage: batterySymbol(for: vm.battery ?? BatteryStatus(percent: tel.percent, isCharging: tel.isCharging, updatedAt: .now)))
                                .font(.subheadline.bold())
                                .foregroundStyle(batteryColor(for: vm.battery ?? BatteryStatus(percent: tel.percent, isCharging: tel.isCharging, updatedAt: .now)))
                            Spacer()
                            Text("\(tel.percent)%")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(batteryColor(for: vm.battery ?? BatteryStatus(percent: tel.percent, isCharging: tel.isCharging, updatedAt: .now)))
                        }

                        // Progress Gauge Bar with AlDente Limit Line
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.10))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [tel.percent <= 20 ? .red : (tel.percent <= 40 ? .orange : .green), .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(8, geo.size.width * CGFloat(tel.percent) / 100.0))

                                if vm.isAlDenteEnabled {
                                    let markX = geo.size.width * CGFloat(vm.alDenteLimitPercent) / 100.0
                                    Rectangle()
                                        .fill(Color.orange)
                                        .frame(width: 2, height: 12)
                                        .offset(x: max(0, min(geo.size.width - 2, markX - 1)), y: -2)
                                }
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text("셀 전압: 약 \(String(format: "%.2f", tel.batteryVoltage))V")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if vm.isAlDenteEnabled {
                                Text("AlDente 목표: \(vm.alDenteLimitPercent)%")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            } else {
                                Text("내장 용량: 4,000 mAh")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                // Card 2: Charging Rate & Power In
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(tel.isCharging ? "충전 유입 속도" : "충전 상태", systemImage: tel.isCharging ? "bolt.fill" : "powerplug")
                                .font(.subheadline.bold())
                                .foregroundStyle(tel.isCharging ? .green : .secondary)
                            Spacer()
                            if tel.isCharging {
                                Text("\(String(format: "%.2f", tel.chargingPowerW)) W")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(.green)
                            } else {
                                Text("미충전")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            if tel.isCharging {
                                Text("USB 5V 입력 · 유입 전류 약 +\(Int(tel.chargingCurrentMa)) mA")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("2.4GHz 무선 배터리 방전 구동 중")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        HStack {
                            Text(tel.isCharging ? "시간당 약 +17% 충전 속도" : "충전 케이블 연결 시 자동 충전")
                                .font(.caption2)
                                .foregroundStyle(tel.isCharging ? .green : .secondary)
                            Spacer()
                        }
                    }
                    .padding(8)
                }

                // Card 3: Power Consumption (Discharge Rate)
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("키보드 소비 전력", systemImage: "gauge.with.dots.needle.bottom.50percent")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                            Spacer()
                            Text(tel.isReactiveMode && !tel.isActivelyTyping ? "\(Int(tel.totalPowerMw)) mW (대기)" : "\(Int(tel.totalPowerMw)) mW")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                        }

                        HStack {
                            Text(tel.isReactiveMode && !tel.isActivelyTyping ? "총 소모 전류: \(Int(tel.totalDischargeCurrentMa)) mA (LED 암전)" : "총 소모 전류: 약 \(Int(tel.totalDischargeCurrentMa)) mA")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "(%.2f W)", tel.totalPowerW))
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(.orange)
                        }

                        HStack {
                            let levelText: String = {
                                if tel.isReactiveMode && !tel.isActivelyTyping { return "반응형 타건 키 입력 대기 (초절전)" }
                                if tel.totalDischargeCurrentMa < 50 { return "초절전 수준 (매우 낮음)" }
                                if tel.totalDischargeCurrentMa < 140 { return "보통 절전 수준" }
                                if tel.totalDischargeCurrentMa < 230 { return "표준 게이밍 수준" }
                                return "최대 화려 조명 소비 수준"
                            }()
                            Text("전력 소비 등급: \(levelText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding(8)
                }

                // Card 4: Estimated Remaining Battery Life
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(tel.isCharging ? "완충 예상 시간" : "예상 사용 시간", systemImage: tel.isCharging ? "hourglass.bottomhalf.filled" : "clock.arrow.circlepath")
                                .font(.subheadline.bold())
                                .foregroundStyle(.cyan)
                            Spacer()
                            Text(tel.isCharging ? formatHours(tel.timeToFullChargeHours) : formatHours(tel.remainingUsageHours))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.cyan)
                        }

                        HStack {
                            Text(tel.isCharging ? "현재 배터리 잔량 \(tel.percent)% 기준" : (tel.isReactiveMode ? "반응형 타건 모드 (상시 대비 5~8배 연장)" : "현재 조명(밝기 \(vm.brightness)단계) 유지 시"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        HStack {
                            if tel.isCharging {
                                Text("완충 시 자동 과충전 방지 모드 작동")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else if tel.isReactiveMode {
                                Text("키를 누를 때만 점등되어 배터리 극대화")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan)
                            } else {
                                Text("백라이트 끄면 최대 180시간까지 연장")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan)
                            }
                            Spacer()
                        }
                    }
                    .padding(8)
                }
            }

            // Dedicated Reactive Typing Mode Notice & Live Status
            if tel.isReactiveMode {
                GroupBox {
                    HStack(spacing: 14) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("반응형 타건 모드 (키 입력 감응형) 작동 중")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.cyan)
                                if tel.isActivelyTyping {
                                    HStack(spacing: 4) {
                                        Circle().fill(.green).frame(width: 7, height: 7)
                                        Text("실시간 타건 감지됨 (\(tel.typingSpeedCPM) 타/분) · 동적 전류 약 \(Int(tel.mainLedsCurrentMa)) mA")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.green)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.green.opacity(0.12)))
                                } else {
                                    HStack(spacing: 4) {
                                        Circle().fill(.secondary).frame(width: 7, height: 7)
                                        Text("키 미입력 대기 상태 (메인 LED 0 mA 소등)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                }
                            }
                            Text("반응형 타건은 평상시 모든 백라이트 LED가 소등(0 mA)되어 전력을 소모하지 않으며, 키를 누르는 순간에만 해당 키가 일시 점등됩니다. 상시 점등(295 mA) 대비 최대 95% 전력을 아껴 배터리를 훨씬 오래 사용할 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }

            // AlDente Battery Health Guard Card
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                            .font(.system(size: 26))
                            .foregroundStyle(vm.isAlDenteEnabled ? (vm.isAlDenteTriggered ? Color.orange : Color.green) : Color.secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("AlDente 배터리 수명 보호기")
                                    .font(.system(size: 14, weight: .bold))

                                if vm.isAlDenteEnabled {
                                    if vm.isAlDenteTriggered {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.orange).frame(width: 7, height: 7)
                                            Text("⚠️ 목표 한계(\(vm.alDenteLimitPercent)%) 도달 · 케이블 분리 권장")
                                                .font(.caption2.bold())
                                                .foregroundStyle(Color.orange)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                                    } else {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.green).frame(width: 7, height: 7)
                                            Text("보호 활성화 중 (목표 \(vm.alDenteLimitPercent)%)")
                                                .font(.caption2.bold())
                                                .foregroundStyle(Color.green)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.green.opacity(0.12)))
                                    }
                                }
                            }

                            Text("리튬이온 배터리를 100%까지 지속 완충하지 않고 70~80%에서 유지하여 배터리 수명을 최대 3배 연장합니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $vm.isAlDenteEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if vm.isAlDenteEnabled {
                        Divider()

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("충전 제한 목표치:")
                                        .font(.caption.bold())
                                    Text("\(vm.alDenteLimitPercent)%")
                                        .font(.caption.bold().monospacedDigit())
                                        .foregroundStyle(.orange)
                                }

                                HStack(spacing: 6) {
                                    ForEach([70, 75, 80, 85, 90], id: \.self) { pct in
                                        Button {
                                            vm.alDenteLimitPercent = pct
                                        } label: {
                                            Text(pct == 80 ? "80% (권장)" : "\(pct)%")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(vm.alDenteLimitPercent == pct ? Color.orange : Color.primary.opacity(0.06))
                                                )
                                                .foregroundStyle(vm.alDenteLimitPercent == pct ? Color.white : Color.primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 6) {
                                Toggle("한계 도달 시 사운드 알림", isOn: $vm.alDenteSoundAlert)
                                    .font(.caption)
                                    .toggleStyle(.checkbox)

                                Text("80% 제한 시 예상 사이클 수명: 약 1,500회 (기본 500회 대비 3배)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
            }

            // Real-Time Hardware Latency & Polling Rate Benchmark Card
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("실시간 하드웨어 연결 레이턴시 & 폴링레이트", systemImage: "speedometer")
                            .font(.headline)

                        if let lat = vm.latencyStats {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(lat.currentRttMs < 3.0 ? Color.green : (lat.currentRttMs < 10.0 ? Color.cyan : Color.orange))
                                    .frame(width: 7, height: 7)
                                Text(lat.connectionKind)
                                    .font(.caption.bold())
                                    .foregroundStyle(lat.currentRttMs < 3.0 ? Color.green : (lat.currentRttMs < 10.0 ? Color.cyan : Color.orange))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill((lat.currentRttMs < 3.0 ? Color.green : (lat.currentRttMs < 10.0 ? Color.cyan : Color.orange)).opacity(0.12)))
                        }

                        Spacer()

                        Button {
                            vm.runLatencyBenchmarkBurst()
                        } label: {
                            Label("10회 벤치마크 연속 측정", systemImage: "bolt.horizontal.fill")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .controlSize(.small)
                        .disabled(vm.isBusy)
                    }

                    if let lat = vm.latencyStats {
                        // 4 KPI Subcards
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            latencyMetricCard(
                                title: "실시간 왕복 핑 (RTT)",
                                value: "\(String(format: "%.2f", lat.currentRttMs)) ms",
                                subtitle: "Mac ↔ 키보드 양방향 왕복 지연",
                                color: lat.currentRttMs < 3.0 ? .green : (lat.currentRttMs < 10.0 ? .cyan : .orange)
                            )
                            latencyMetricCard(
                                title: "실효 타건 입력 지연",
                                value: "\(String(format: "%.2f", lat.effectiveInputMs)) ms",
                                subtitle: "1-Way 하드웨어 단방향 전송 (0.001초대)",
                                color: .cyan
                            )
                            latencyMetricCard(
                                title: "평균 / 지터 (Jitter)",
                                value: "\(String(format: "%.2f", lat.avgMs)) ms",
                                subtitle: "편차 ±\(String(format: "%.2f", lat.jitterMs)) ms (안정성)",
                                color: .purple
                            )
                            latencyMetricCard(
                                title: "최저 / 최고 지연",
                                value: "\(String(format: "%.1f", lat.minMs)) / \(String(format: "%.1f", lat.maxMs)) ms",
                                subtitle: "\(lat.sampleCount)개 표본 실시간 통계",
                                color: .primary
                            )
                        }

                        // Connection Mode Comparison Bar
                        VStack(alignment: .leading, spacing: 8) {
                            Text("연결 방식별 레이턴시 & 폴링레이트 스펙 비교")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                comparisonModePill(
                                    title: "USB 유선",
                                    speed: "~0.8 ms",
                                    rate: "1,000 Hz",
                                    tag: "eSports 공식 경기",
                                    isCurrent: vm.connectionMode.contains("USB")
                                )
                                comparisonModePill(
                                    title: "2.4GHz 무선",
                                    speed: "~2.1 ms",
                                    rate: "1,000 Hz",
                                    tag: "초고속 게이밍 무선",
                                    isCurrent: vm.connectionMode.contains("2.4GHz")
                                )
                                comparisonModePill(
                                    title: "Bluetooth 5.0",
                                    speed: "~11.2 ms",
                                    rate: "133 Hz",
                                    tag: "저전력 장시간 사무",
                                    isCurrent: vm.connectionMode.contains("Bluetooth")
                                )
                            }
                        }
                    } else {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("실시간 레이턴시 측정 중…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(8)
            }

            // 2. Power Breakdown & Battery Life Simulation
            HStack(alignment: .top, spacing: 16) {
                // Left: Component-by-Component Power Breakdown
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("구성 요소별 전력 소모 비중 분석", systemImage: "chart.pie.fill")
                                .font(.headline)
                            Spacer()
                            Text("총 \(Int(tel.totalDischargeCurrentMa)) mA")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(.cyan)
                        }

                        let mainRatio = tel.totalDischargeCurrentMa > 0 ? (tel.mainLedsCurrentMa / tel.totalDischargeCurrentMa) : 0
                        let sideRatio = tel.totalDischargeCurrentMa > 0 ? (tel.sideLedsCurrentMa / tel.totalDischargeCurrentMa) : 0
                        let mcuRatio = tel.totalDischargeCurrentMa > 0 ? (tel.mcuCurrentMa / tel.totalDischargeCurrentMa) : 0

                        let mainTitle: String = {
                            if tel.isReactiveMode {
                                return tel.isActivelyTyping
                                    ? "87키 메인 백라이트 (반응형 타건 중 · \(tel.typingSpeedCPM)타/분)"
                                    : "87키 메인 백라이트 (반응형 대기 중 · 키 미입력 암전 0 mA)"
                            }
                            return "87키 메인 백라이트 LED (현재 밝기 \(vm.brightness)단계)"
                        }()

                        powerBarRow(
                            title: mainTitle,
                            ma: Int(tel.mainLedsCurrentMa),
                            ratio: mainRatio,
                            color: .pink
                        )

                        powerBarRow(
                            title: "양측면 RGB 스트립 & 방향키 라이트바",
                            ma: Int(tel.sideLedsCurrentMa),
                            ratio: sideRatio,
                            color: .purple
                        )

                        powerBarRow(
                            title: "2.4GHz 무선 RF 트랜시버 & 32비트 MCU",
                            ma: Int(tel.mcuCurrentMa),
                            ratio: mcuRatio,
                            color: .cyan
                        )

                        Divider()

                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.secondary)
                            Text(tel.isReactiveMode
                                ? "현재 반응형 타건 모드입니다. 키를 누르지 않을 때는 메인 백라이트가 0 mA로 꺼져 배터리가 초장시간 보존됩니다."
                                : "AULA F87 Pro는 87개의 독립 RGB LED가 전체 전력의 70% 이상을 차지합니다. 배터리를 오래 쓰려면 밝기를 1~2단계로 낮추는 것이 가장 효과적입니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Right: Battery Life Simulation & One-Click Eco Optimizer
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(tel.isReactiveMode ? "반응형 타건 단계별 예상 배터리 지속 시간" : "밝기 단계별 예상 배터리 지속 시간", systemImage: "slider.horizontal.below.sun.max")
                            .font(.headline)

                        VStack(spacing: 8) {
                            if tel.isReactiveMode {
                                simulatedRow(levelName: "반응형 밝기 4단계 (최대)", hours: "약 110~130시간 (상시 대비 10배)", current: vm.brightness == 4)
                                simulatedRow(levelName: "반응형 밝기 3단계 (권장)", hours: "약 130~150시간", current: vm.brightness == 3)
                                simulatedRow(levelName: "반응형 밝기 2단계 (은은한)", hours: "약 150~170시간", current: vm.brightness == 2)
                                simulatedRow(levelName: "반응형 밝기 1단계 (초절전)", hours: "약 170~190시간", current: vm.brightness == 1)
                                simulatedRow(levelName: "키 미입력 대기 / 조명 OFF", hours: "약 180~220시간", current: vm.brightness == 0)
                            } else {
                                simulatedRow(levelName: "밝기 4단계 (최대 밝기)", hours: "약 11~12시간", current: vm.brightness == 4)
                                simulatedRow(levelName: "밝기 3단계 (권장 게이밍)", hours: "약 18~20시간", current: vm.brightness == 3)
                                simulatedRow(levelName: "밝기 2단계 (은은한 실내)", hours: "약 32~36시간", current: vm.brightness == 2)
                                simulatedRow(levelName: "밝기 1단계 (초절전 조명)", hours: "약 58~65시간", current: vm.brightness == 1)
                                simulatedRow(levelName: "조명 OFF (무조명 타이핑)", hours: "약 180~200시간 (최대 8일)", current: vm.brightness == 0)
                            }
                        }

                        Divider()

                        HStack(spacing: 10) {
                            Button {
                                vm.applyEcoMode()
                            } label: {
                                Label("에코 절전 모드 적용 (~60시간)", systemImage: "leaf.fill")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(vm.isBusy || !vm.isConnected)

                            Button {
                                vm.brightness = 0
                                vm.sideLightMode = 0
                                vm.lightBarMode = 0
                                vm.sleepRawSteps = 2
                                vm.applyLightingAndSettingsToHardware()
                                vm.showToast("최대 배터리 절약 모드가 적용되었습니다 (조명 완전 OFF)")
                            } label: {
                                Label("조명 완전 OFF (최장 180h)", systemImage: "poweroff")
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.isBusy || !vm.isConnected)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // 3. Hardware Health & Specifications Summary
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("AULA F87 Pro V1 배터리 및 전원 하드웨어 스펙", systemImage: "checkmark.shield.fill")
                        .font(.headline)

                    HStack(spacing: 24) {
                        specItem("배터리 용량", "4,000 mAh (14.8 Wh)")
                        specItem("정격 전압", "3.7V (충전 완료 4.2V)")
                        specItem("권장 충전 규격", "5V 1A ~ 2A USB")
                        specItem("충전 IC 보호", "과충전 / 과방전 보호 회로 내장")
                        specItem("현재 절전 타이머", "\(vm.sleepRawSteps * 30)초 후 자동 슬립")
                    }
                    .padding(.top, 4)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func powerBarRow(title: String, ma: Int, ratio: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                Spacer()
                Text("\(ma) mA (\(Int((ratio * 100).rounded()))%)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1.0, ratio))))
                }
            }
            .frame(height: 6)
        }
    }

    private func simulatedRow(levelName: String, hours: String, current: Bool) -> some View {
        HStack {
            Circle()
                .fill(current ? Color.cyan : Color.primary.opacity(0.18))
                .frame(width: 7, height: 7)
            Text(levelName)
                .font(.system(size: 12.5, weight: current ? .bold : .regular))
                .foregroundStyle(current ? Color.cyan : Color.primary)
            Spacer()
            Text(hours)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(current ? Color.cyan : Color.secondary)
            if current {
                Text("(현재)")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.cyan)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(current ? Color.cyan.opacity(0.12) : Color.clear)
        )
    }

    private func specItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }

    private func formatHours(_ hours: Double) -> String {
        guard hours > 0 else { return "0분" }
        let h = Int(hours)
        let m = Int(((hours - Double(h)) * 60).rounded())
        if h == 0 {
            return "\(m)분"
        } else if m == 0 {
            return "\(h)시간"
        } else {
            return "\(h)시간 \(m)분"
        }
    }

    private func batterySymbol(for bat: BatteryStatus) -> String {
        if bat.isCharging { return "battery.100percent.bolt" }
        switch bat.percent {
        case 80...100: return "battery.100percent"
        case 55..<80: return "battery.75percent"
        case 30..<55: return "battery.50percent"
        case 15..<30: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func latencyMetricCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func comparisonModePill(title: String, speed: String, rate: String, tag: String, isCurrent: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isCurrent ? Color.green : Color.primary.opacity(0.18))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(isCurrent ? Color.green : Color.primary)
                    if isCurrent {
                        Text("(현재 연결)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                }
                Text("\(speed) · \(rate) (\(tag))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.green.opacity(0.10) : Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isCurrent ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }

    private func batteryColor(for bat: BatteryStatus) -> Color {
        if bat.isCharging { return .green }
        if bat.percent <= 20 { return .red }
        if bat.percent <= 40 { return .orange }
        return .green
    }
}
