import SwiftUI

enum KeyboardCanvasMode {
    case effectPreview
    case perKeyPainter
    case keyRemapInspector
    case musicVisualizer
}

struct KeyboardCanvasView: View {
    @ObservedObject var vm: AppViewModel
    let mode: KeyboardCanvasMode

    private let unitWidth: CGFloat = 41
    private let unitHeight: CGFloat = 39
    private let keySpacing: CGFloat = 5
    private let rowSpacing: CGFloat = 6

    private var pitch: CGFloat {
        unitWidth + keySpacing
    }

    private var needsAnimation: Bool {
        if mode == .effectPreview {
            return vm.selectedEffect != 0 && vm.selectedEffect != 1 && vm.selectedEffect != LightingEffect.customPerKeyID
        }
        return vm.sideLightMode == 1 || vm.sideLightMode == 2 || vm.sideLightMode == 4
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: needsAnimation ? (1.0 / 15.0) : 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 12) {
                // Left Side Light Strip
                sideLightStrip(phase: phase)

                // Main 87-Key TKL Chassis (Exact 18.25U Width on All 6 Rows)
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(F87Layout.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: keySpacing) {
                            ForEach(Array(row.enumerated()), id: \.offset) { itemIndex, item in
                                switch item {
                                case .gap(let gapUnits):
                                    Color.clear
                                        .frame(width: max(0, CGFloat(gapUnits) * pitch - keySpacing), height: unitHeight)
                                case .key(let key):
                                    keyCapView(
                                        key: key,
                                        rowIndex: rowIndex,
                                        colIndex: logicalColumn(for: row, upTo: itemIndex),
                                        phase: phase
                                    )
                                }
                            }

                            // Row 3 (Caps..Enter = 15.0U): Dedicated 3.0U Navigation Cluster Housing for Light Bar
                            if rowIndex == 3 {
                                Color.clear
                                    .frame(width: max(0, 0.25 * pitch - keySpacing), height: unitHeight)
                                lightBarHousing(phase: phase)
                                    .frame(width: 3.0 * pitch - keySpacing, height: unitHeight)
                            }

                            // Row 4 (LShift..RShift + 1.25U gap + ↑ = 17.25U): Trailing 1.0U spacer above →
                            if rowIndex == 4 {
                                Color.clear
                                    .frame(width: 1.0 * pitch - keySpacing, height: unitHeight)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.11, green: 0.12, blue: 0.16),
                                    Color(red: 0.07, green: 0.08, blue: 0.11)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.42), radius: 14, x: 0, y: 6)
                )

                // Right Side Light Strip
                sideLightStrip(phase: phase)
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private func logicalColumn(for row: [KeyRowItem], upTo index: Int) -> Int {
        var u = 0.0
        for i in 0..<index {
            switch row[i] {
            case .gap(let g): u += g
            case .key(let k): u += k.width
            }
        }
        return Int(u.rounded())
    }

    @ViewBuilder
    private func sideLightStrip(phase: Double) -> some View {
        let colors = stripColors(mode: vm.sideLightMode, phase: phase)
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 8, height: 268)
            .shadow(color: colors.first?.opacity(vm.sideLightMode == 0 ? 0 : 0.65) ?? .clear, radius: 6)
    }

    @ViewBuilder
    private func lightBarHousing(phase: Double) -> some View {
        let colors = stripColors(mode: vm.lightBarMode, phase: phase + 0.35)
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green.opacity(vm.isConnected ? 0.85 : 0.2))
                    .frame(width: 5, height: 5)
                Text("AULA LIGHT BAR")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Capsule()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 108, height: 7)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                )
                .shadow(color: colors.first?.opacity(vm.lightBarMode == 0 ? 0 : 0.75) ?? .clear, radius: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .help("방향키 상단 라이트바 (Fn + Left Shift: 모드 전환, Fn + B: 배터리 잔량 표시)")
    }

    private func stripColors(mode: Int, phase: Double) -> [Color] {
        switch mode {
        case 0:
            return [Color.white.opacity(0.08), Color.white.opacity(0.08)]
        case 1:
            return (0..<5).map { idx in
                let h = positiveMod(phase * 0.25 + Double(idx) * 0.16, 1.0)
                return Color(hue: h, saturation: 0.9, brightness: 1.0)
            }
        case 2:
            let h = positiveMod(phase * 0.18, 1.0)
            let c = Color(hue: h, saturation: 0.9, brightness: 1.0)
            return [c, c]
        case 3:
            return [vm.selectedColor.color, vm.selectedColor.color]
        case 4:
            let pulse = 0.2 + 0.8 * (0.5 + 0.5 * sin(phase * 2.2))
            let c = vm.selectedColor.color.opacity(pulse)
            return [c, c]
        default:
            return [Color.cyan, Color.purple]
        }
    }

    @ViewBuilder
    private func keyCapView(key: KeyboardKey, rowIndex: Int, colIndex: Int, phase: Double) -> some View {
        let width = CGFloat(key.width) * pitch - keySpacing
        let keyColor = computeKeyColor(key: key, rowIndex: rowIndex, colIndex: colIndex, phase: phase)
        let isSelected: Bool = {
            switch mode {
            case .perKeyPainter:
                return vm.selectedLEDs.contains(key.led)
            case .keyRemapInspector:
                return vm.selectedKeyForRemap.led == key.led
            default:
                return false
            }
        }()

        let remapShortText: String? = {
            guard mode == .keyRemapInspector else { return nil }
            let bytes = vm.currentSlotBytes(for: key.led, in: vm.selectedMatrixLayer)
            let desc = KeymapCatalog.describe(bytes)
            if desc == "비어 있음 (기본값)" || desc == key.label {
                return nil
            }
            return desc
        }()

        ZStack {
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(Color(red: 0.14, green: 0.15, blue: 0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(keyColor.opacity(0.38))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.white : keyColor.opacity(0.92),
                            lineWidth: isSelected ? 2.2 : 1.3
                        )
                )

            VStack(spacing: 1) {
                Text(key.label)
                    .font(.system(size: key.label.count > 4 ? 9.0 : 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let remapShortText {
                    Text(remapShortText)
                        .font(.system(size: 7.0, weight: .bold))
                        .foregroundStyle(Color.yellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if let sub = key.subLabel {
                    Text(sub)
                        .font(.system(size: 7.0, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width, height: unitHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            switch mode {
            case .perKeyPainter:
                vm.handleKeyClick(key)
            case .keyRemapInspector:
                vm.selectedKeyForRemap = key
            case .effectPreview:
                vm.handleKeyClick(key)
            case .musicVisualizer:
                break
            }
        }
    }

    // MARK: - Distinct Non-Overlapping Effect Shaders for All 16 Modes

    private func positiveMod(_ x: Double, _ m: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }

    private func tintedColor(hue: Double, intensity: Double, isRainbow: Bool, bScale: Double) -> Color {
        let clamped = max(0.0, min(1.0, intensity))
        if clamped < 0.04 {
            return Color.white.opacity(0.05)
        }
        let base = isRainbow
            ? Color(hue: positiveMod(hue, 1.0), saturation: 0.90, brightness: 1.0)
            : vm.selectedColor.color
        return base.opacity(max(0.06, clamped * bScale))
    }

    private func computeKeyColor(key: KeyboardKey, rowIndex: Int, colIndex: Int, phase: Double) -> Color {
        switch mode {
        case .perKeyPainter:
            if let rgb = vm.perKeyColors[key.led] {
                return rgb.color
            }
            return Color.white.opacity(0.08)

        case .keyRemapInspector:
            if vm.selectedKeyForRemap.led == key.led {
                return Color.cyan
            }
            let bytes = vm.currentSlotBytes(for: key.led, in: vm.selectedMatrixLayer)
            let isNonEmpty = bytes.contains(where: { $0 != 0 })
            if vm.selectedMatrixLayer > 0 && isNonEmpty {
                return Color.orange
            }
            return isNonEmpty ? Color.blue.opacity(0.65) : Color.white.opacity(0.10)

        case .musicVisualizer:
            for (bandIdx, colLEDs) in F87Layout.audioColumns.enumerated() where bandIdx < vm.audioLevels.count {
                if let pos = colLEDs.firstIndex(of: key.led) {
                    let activeCount = Int((vm.audioLevels[bandIdx] * Double(colLEDs.count)).rounded())
                    if pos < activeCount {
                        if vm.musicColorMode == 1 {
                            return vm.selectedColor.color
                        }
                        let ratio = Double(pos) / Double(max(1, colLEDs.count - 1))
                        return Color(hue: max(0, 0.52 - ratio * 0.50), saturation: 0.92, brightness: 1.0)
                    }
                }
            }
            return Color.white.opacity(0.05)

        case .effectPreview:
            if vm.selectedEffect == 0 || vm.brightness == 0 {
                return Color.white.opacity(0.05)
            }
            let bScale = Double(vm.brightness) / 4.0
            if vm.selectedEffect == LightingEffect.customPerKeyID {
                return (vm.perKeyColors[key.led]?.color ?? Color.white.opacity(0.08))
                    .opacity(max(0.25, bScale))
            }

            let spdRate = 0.55 + Double(vm.speed) * 0.45
            let info = vm.selectedEffectInfo
            let isRainbow = vm.colorful || !info.supportsColor
            let x = Double(colIndex)       // 0 .. 18
            let y = Double(rowIndex)       // 0 .. 5
            let cx = 7.5
            let cy = 2.5

            switch vm.selectedEffect {
            case 1:
                // 1. 상시 점등 (Static): 고정 점등 (움직임 없음)
                return tintedColor(hue: x / 18.0, intensity: 1.0, isRainbow: isRainbow, bScale: bScale)

            case 2:
                // 2. 숨쉬기 (Breathing): 키보드 전체가 동시에 서서히 밝아졌다 어두워짐
                let breath = 0.10 + 0.90 * pow(0.5 + 0.5 * sin(phase * spdRate * 2.0), 1.6)
                let cycleHue = floor(phase * spdRate * 2.0 / (2.0 * .pi)) * 0.19
                return tintedColor(hue: cycleHue, intensity: breath, isRainbow: isRainbow, bScale: bScale)

            case 3:
                // 3. 레인보우 웨이브 (Rainbow Wave): 좌→우 수평 무지개 파동
                let wavePos = x / 18.0 - phase * spdRate * 0.35
                if isRainbow {
                    return tintedColor(hue: wavePos, intensity: 1.0, isRainbow: true, bScale: bScale)
                } else {
                    let level = 0.25 + 0.75 * (0.5 + 0.5 * sin(wavePos * 2.0 * .pi))
                    return tintedColor(hue: 0, intensity: level, isRainbow: false, bScale: bScale)
                }

            case 4:
                // 4. 일촉즉발 (Flash Away): 키를 가로지르는 날카로운 섬광 스캔 + 잔상 감쇠
                let headX = positiveMod(phase * spdRate * 8.5, 22.0) - 2.0
                let dist = headX - x
                let rowMatch = (Int(floor(phase * spdRate * 8.5 / 22.0)) + rowIndex) % 2 == 0
                let flash = (dist >= 0 && dist < 5.5 && rowMatch) ? exp(-dist * 0.65) : 0.0
                return tintedColor(hue: x * 0.06 + y * 0.1, intensity: flash, isRainbow: isRainbow, bScale: bScale)

            case 5:
                // 5. 빗방울 (Raindrops): 열마다 서로 다른 속도와 타이밍으로 위에서 아래로 떨어지는 빗방울
                let colSeed = Double((colIndex * 37 + 13) % 19) / 19.0
                let colSpeed = spdRate * (1.8 + Double((colIndex * 11) % 5) * 0.32)
                let dropY = positiveMod(phase * colSpeed + colSeed * 9.0, 8.5) - 1.5
                let dy = y - dropY
                let trail = (dy <= 0 && dy > -2.4) ? exp(dy * 1.35) : 0.0
                return tintedColor(hue: colSeed + y * 0.05, intensity: trail, isRainbow: isRainbow, bScale: bScale)

            case 7:
                // 7. 물결 확산 (Ripples): 중앙에서 바깥으로 퍼져나가는 동심원 파동 고리
                let dist = hypot((x - cx) * 0.85, (y - cy) * 1.35)
                let ringRadius = positiveMod(phase * spdRate * 4.2, 11.5)
                let ringDiff = abs(dist - ringRadius)
                let ringIntensity = max(0.0, 1.0 - ringDiff / 1.65)
                return tintedColor(hue: dist * 0.09 - phase * 0.2, intensity: pow(ringIntensity, 1.5), isRainbow: isRainbow, bScale: bScale)

            case 8:
                // 8. 별빛 반짝임 (Twinkling Stars): 개별 키가 밤하늘의 별처럼 제각기 반짝임
                let seed = Double((key.led * 73 + 29) % 101)
                let rate = spdRate * (1.4 + Double(key.led % 7) * 0.28)
                let raw = 0.5 + 0.5 * sin(phase * rate + seed)
                let twinkle = raw > 0.72 ? pow((raw - 0.72) / 0.28, 1.8) : 0.0
                return tintedColor(hue: seed * 0.013 + phase * 0.05, intensity: twinkle, isRainbow: isRainbow, bScale: bScale)

            case 10:
                // 10. 레트로 스네이크 (Retro Snake): 지그재그(S자)로 모든 행을 타고 기어가는 뱀 궤적
                let snakeCol = (rowIndex % 2 == 0) ? x : (18.0 - x)
                let pathPos = Double(rowIndex) * 19.0 + snakeCol // 0 .. 113
                let totalLen = 114.0
                let headPos = positiveMod(phase * spdRate * 18.0, totalLen)
                let behind = positiveMod(headPos - pathPos, totalLen)
                let snakeLength = 16.0
                let intensity = behind < snakeLength ? (1.0 - behind / snakeLength) : 0.0
                return tintedColor(hue: pathPos / totalLen, intensity: intensity, isRainbow: isRainbow, bScale: bScale)

            case 11:
                // 11. 네온 스트림 (Neon Stream): 45도 대각선 방향의 부드러운 듀얼 네온 리본 흐름
                let diag = (x * 0.055 + y * 0.095) - phase * spdRate * 0.32
                let ribbon = 0.25 + 0.75 * pow(0.5 + 0.5 * sin(diag * 2.0 * .pi * 1.5), 1.3)
                return tintedColor(hue: diag, intensity: ribbon, isRainbow: isRainbow, bScale: bScale)

            case 12:
                // 12. 반응형 타건 (Reactive): 타이핑하듯 개별 키가 순차적으로 타건되며 주변으로 잔광이 번진 뒤 사라짐
                var reactiveLevel = 0.0
                var hitHue = 0.0
                for slot in 0..<3 {
                    let stepPeriod = 0.45 / spdRate
                    let t = phase + Double(slot) * (stepPeriod * 0.33)
                    let stepIdx = Int(floor(t / stepPeriod))
                    let localAge = (t - Double(stepIdx) * stepPeriod) / stepPeriod // 0 .. 1
                    let targetCol = Double((stepIdx * 41 + slot * 19 + 7) % 15)
                    let targetRow = Double((stepIdx * 23 + slot * 11 + 3) % 6)
                    let d = hypot(x - targetCol, y - targetRow)
                    if d < 1.8 {
                        let spatial = max(0.0, 1.0 - d / 1.8)
                        let temporal = exp(-localAge * 3.2)
                        let val = spatial * temporal
                        if val > reactiveLevel {
                            reactiveLevel = val
                            hitHue = Double((stepIdx * 17 + slot * 31) % 100) / 100.0
                        }
                    }
                }
                return tintedColor(hue: hitHue, intensity: reactiveLevel, isRainbow: isRainbow, bScale: bScale)

            case 13:
                // 13. 사인파 웨이브 (Sine Wave): 키보드 상하(Row 0~5)를 실제로 오르락내리락하는 사인 곡선 궤적
                let curveY = 2.5 + 2.25 * sin(x * 0.52 - phase * spdRate * 2.8)
                let distToCurve = abs(y - curveY)
                let curveGlow = max(0.0, 1.0 - distToCurve / 1.35)
                return tintedColor(hue: x / 18.0 - phase * 0.15, intensity: pow(curveGlow, 1.6), isRainbow: isRainbow, bScale: bScale)

            case 15:
                // 15. 회전 풍차 (Rotating Windmill): 중심축을 기준으로 360도 회전하는 4날개 바람개비
                let dx = x - cx
                let dy = (y - cy) * 1.6
                let angle = atan2(dy, dx) // -pi .. pi
                let normalizedAngle = positiveMod(angle / (2.0 * .pi) + phase * spdRate * 0.28, 1.0)
                let blade = 0.25 + 0.75 * (0.5 + 0.5 * cos(normalizedAngle * 2.0 * .pi * 3.0))
                return tintedColor(hue: normalizedAngle, intensity: blade, isRainbow: true, bScale: bScale)

            case 16:
                // 16. 컬러 폭포 (Colorful Waterfall): 상단(F열)에서 하단(스페이스열)으로 쏟아져 내리는 수직 폭포
                let fall = (y / 5.5) - phase * spdRate * 0.48 + sin(x * 0.65) * 0.08
                let crest = 0.35 + 0.65 * (0.5 + 0.5 * sin(fall * 2.0 * .pi * 1.5))
                return tintedColor(hue: fall, intensity: crest, isRainbow: true, bScale: bScale)

            case 17:
                // 17. 블로섬 (Blossoming): 중앙에서 6개의 꽃잎 모양으로 피어오르는 만개 효과
                let dx = x - cx
                let dy = (y - cy) * 1.5
                let angle = atan2(dy, dx)
                let r = hypot(dx, dy)
                let petalRadius = 3.2 + 1.8 * cos(angle * 5.0) + 3.0 * (0.5 + 0.5 * sin(phase * spdRate * 2.2))
                let bloom = max(0.0, 1.0 - abs(r - petalRadius * 0.75) / 2.6)
                let hue = positiveMod(angle / (2.0 * .pi) + r * 0.06 - phase * 0.2, 1.0)
                return tintedColor(hue: hue, intensity: pow(bloom, 1.3), isRainbow: true, bScale: bScale)

            default:
                return tintedColor(hue: x / 18.0, intensity: 1.0, isRainbow: isRainbow, bScale: bScale)
            }
        }
    }
}
