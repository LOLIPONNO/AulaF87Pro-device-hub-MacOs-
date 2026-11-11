import AppKit
import Foundation
import SwiftUI

struct RGBColor: Codable, Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    static let black = RGBColor(red: 0, green: 0, blue: 0)
    static let white = RGBColor(red: 255, green: 255, blue: 255)
    static let cyan = RGBColor(red: 0, green: 240, blue: 255)
    static let neonPurple = RGBColor(red: 165, green: 65, blue: 255)

    static let presets: [(name: String, color: RGBColor)] = [
        ("레드", RGBColor(red: 255, green: 0, blue: 0)),
        ("오렌지", RGBColor(red: 255, green: 96, blue: 0)),
        ("옐로우", RGBColor(red: 255, green: 215, blue: 0)),
        ("그린", RGBColor(red: 0, green: 255, blue: 64)),
        ("시안", RGBColor(red: 0, green: 240, blue: 255)),
        ("블루", RGBColor(red: 0, green: 85, blue: 255)),
        ("퍼플", RGBColor(red: 150, green: 40, blue: 255)),
        ("마젠타", RGBColor(red: 255, green: 0, blue: 180)),
        ("화이트", RGBColor(red: 255, green: 255, blue: 255))
    ]

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        red = UInt8(max(0, min(255, Int((ns.redComponent * 255).rounded()))))
        green = UInt8(max(0, min(255, Int((ns.greenComponent * 255).rounded()))))
        blue = UInt8(max(0, min(255, Int((ns.blueComponent * 255).rounded()))))
    }

    var color: Color {
        Color(red: Double(red) / 255.0, green: Double(green) / 255.0, blue: Double(blue) / 255.0)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct LightingEffect: Identifiable, Hashable, Sendable {
    let id: Int
    let titleKo: String
    let titleEn: String
    let icon: String
    let supportsSpeed: Bool
    let supportsColor: Bool
    let isReactive: Bool

    init(
        id: Int,
        titleKo: String,
        titleEn: String,
        icon: String,
        supportsSpeed: Bool,
        supportsColor: Bool,
        isReactive: Bool = false
    ) {
        self.id = id
        self.titleKo = titleKo
        self.titleEn = titleEn
        self.icon = icon
        self.supportsSpeed = supportsSpeed
        self.supportsColor = supportsColor
        self.isReactive = isReactive
    }

    static let customPerKeyID = 18

    static let all: [LightingEffect] = [
        .init(id: 0, titleKo: "백라이트 끄기", titleEn: "Off", icon: "lightbulb.slash", supportsSpeed: false, supportsColor: false),
        .init(id: 1, titleKo: "상시 점등", titleEn: "Static", icon: "sun.max.fill", supportsSpeed: false, supportsColor: true),
        .init(id: 2, titleKo: "숨쉬기", titleEn: "Breathing", icon: "wind", supportsSpeed: true, supportsColor: true),
        .init(id: 3, titleKo: "레인보우 웨이브", titleEn: "Rainbow Wave", icon: "rainbow", supportsSpeed: true, supportsColor: false),
        .init(id: 4, titleKo: "일촉즉발", titleEn: "Flash Away", icon: "bolt.fill", supportsSpeed: true, supportsColor: true, isReactive: true),
        .init(id: 5, titleKo: "빗방울", titleEn: "Raindrops", icon: "cloud.rain.fill", supportsSpeed: true, supportsColor: true),
        .init(id: 7, titleKo: "물결 확산", titleEn: "Ripples", icon: "dot.radiowaves.left.and.right", supportsSpeed: true, supportsColor: true, isReactive: true),
        .init(id: 8, titleKo: "별빛 반짝임", titleEn: "Twinkling Stars", icon: "sparkles", supportsSpeed: true, supportsColor: true),
        .init(id: 10, titleKo: "레트로 스네이크", titleEn: "Retro Snake", icon: "scribble.variable", supportsSpeed: true, supportsColor: true),
        .init(id: 11, titleKo: "네온 스트림", titleEn: "Neon Stream", icon: "water.waves", supportsSpeed: true, supportsColor: true),
        .init(id: 12, titleKo: "반응형 타건", titleEn: "Reactive", icon: "hand.tap.fill", supportsSpeed: true, supportsColor: true, isReactive: true),
        .init(id: 13, titleKo: "사인파 웨이브", titleEn: "Sine Wave", icon: "waveform.path.ecg", supportsSpeed: true, supportsColor: true),
        .init(id: 15, titleKo: "회전 풍차", titleEn: "Rotating Windmill", icon: "hurricane", supportsSpeed: true, supportsColor: false),
        .init(id: 16, titleKo: "컬러 폭포", titleEn: "Colorful Waterfall", icon: "arrow.down.to.line.compact", supportsSpeed: true, supportsColor: false),
        .init(id: 17, titleKo: "블로섬", titleEn: "Blossoming", icon: "camera.macro", supportsSpeed: true, supportsColor: false),
        .init(id: 18, titleKo: "개별 키 커스텀", titleEn: "Custom Per-Key", icon: "paintbrush.pointed.fill", supportsSpeed: false, supportsColor: false)
    ]

    static func info(for id: Int) -> LightingEffect {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

struct SideLightMode: Identifiable, Hashable, Sendable {
    let id: Int
    let titleKo: String
    let titleEn: String
    let icon: String

    static let all: [SideLightMode] = [
        .init(id: 0, titleKo: "끄기", titleEn: "Off", icon: "poweroff"),
        .init(id: 1, titleKo: "레인보우 흐르기", titleEn: "Rainbow Stream", icon: "rainbow"),
        .init(id: 2, titleKo: "레인보우 네온 전환", titleEn: "Rainbow Sync", icon: "sparkles"),
        .init(id: 3, titleKo: "단색 고정", titleEn: "Solid Color", icon: "circle.fill"),
        .init(id: 4, titleKo: "숨쉬기", titleEn: "Breathing", icon: "wind")
    ]
}

struct SleepTimerOption: Identifiable, Hashable, Sendable {
    let rawSteps: Int // 30-second units in config[24]
    let label: String
    var id: Int { rawSteps }

    static let all: [SleepTimerOption] = [
        .init(rawSteps: 0, label: "사용 안 함 (항상 켜짐)"),
        .init(rawSteps: 1, label: "30초"),
        .init(rawSteps: 2, label: "1분"),
        .init(rawSteps: 3, label: "1분 30초"),
        .init(rawSteps: 4, label: "2분"),
        .init(rawSteps: 6, label: "3분"),
        .init(rawSteps: 8, label: "4분"),
        .init(rawSteps: 10, label: "5분 (기본값)"),
        .init(rawSteps: 20, label: "10분"),
        .init(rawSteps: 30, label: "15분"),
        .init(rawSteps: 40, label: "20분"),
        .init(rawSteps: 60, label: "30분"),
        .init(rawSteps: 120, label: "60분")
    ]
}

struct KeyboardKey: Identifiable, Hashable, Sendable {
    let label: String
    let subLabel: String?
    let led: Int // LED index == Matrix slot index (0..101)
    let width: Double
    var id: Int { led }

    init(_ label: String, led: Int, width: Double = 1.0, subLabel: String? = nil) {
        self.label = label
        self.led = led
        self.width = width
        self.subLabel = subLabel
    }
}

enum KeyRowItem: Hashable, Sendable {
    case key(KeyboardKey)
    case gap(Double)
}

enum F87Layout {
    static let rows: [[KeyRowItem]] = [
        row([
            KeyboardKey("Esc", led: 0, subLabel: "초기화"),
            KeyboardKey("F1", led: 12, subLabel: "밝기-"),
            KeyboardKey("F2", led: 18, subLabel: "밝기+"),
            KeyboardKey("F3", led: 24, subLabel: "미션"),
            KeyboardKey("F4", led: 30, subLabel: "검색"),
            KeyboardKey("F5", led: 36, subLabel: "음성"),
            KeyboardKey("F6", led: 42, subLabel: "방해금지"),
            KeyboardKey("F7", led: 48, subLabel: "이전곡"),
            KeyboardKey("F8", led: 54, subLabel: "재생"),
            KeyboardKey("F9", led: 60, subLabel: "다음곡"),
            KeyboardKey("F10", led: 66, subLabel: "음소거"),
            KeyboardKey("F11", led: 72, subLabel: "볼륨-"),
            KeyboardKey("F12", led: 78, subLabel: "볼륨+"),
            KeyboardKey("PrtSc", led: 84),
            KeyboardKey("ScrLk", led: 90),
            KeyboardKey("Pause", led: 96)
        ], gaps: [1: 1.0, 5: 0.5, 9: 0.5, 13: 0.25]),
        row([
            KeyboardKey("`", led: 1, subLabel: "2.4G"),
            KeyboardKey("1", led: 7, subLabel: "BT1"),
            KeyboardKey("2", led: 13, subLabel: "BT2"),
            KeyboardKey("3", led: 19, subLabel: "BT3"),
            KeyboardKey("4", led: 25),
            KeyboardKey("5", led: 31),
            KeyboardKey("6", led: 37),
            KeyboardKey("7", led: 43),
            KeyboardKey("8", led: 49),
            KeyboardKey("9", led: 55),
            KeyboardKey("0", led: 61),
            KeyboardKey("-", led: 67),
            KeyboardKey("=", led: 73),
            KeyboardKey("Bksp", led: 79, width: 2.0),
            KeyboardKey("Ins", led: 85, subLabel: "효과"),
            KeyboardKey("Home", led: 91),
            KeyboardKey("PgUp", led: 97)
        ], gaps: [14: 0.25]),
        row([
            KeyboardKey("Tab", led: 2, width: 1.5),
            KeyboardKey("Q", led: 8, subLabel: "Android"),
            KeyboardKey("W", led: 14, subLabel: "Win"),
            KeyboardKey("E", led: 20, subLabel: "Mac"),
            KeyboardKey("R", led: 26, subLabel: "iOS"),
            KeyboardKey("T", led: 32),
            KeyboardKey("Y", led: 38),
            KeyboardKey("U", led: 44),
            KeyboardKey("I", led: 50),
            KeyboardKey("O", led: 56),
            KeyboardKey("P", led: 62),
            KeyboardKey("[", led: 68),
            KeyboardKey("]", led: 74),
            KeyboardKey("\\", led: 80, width: 1.5),
            KeyboardKey("Del", led: 86, subLabel: "색상"),
            KeyboardKey("End", led: 92),
            KeyboardKey("PgDn", led: 98)
        ], gaps: [14: 0.25]),
        row([
            KeyboardKey("Caps", led: 3, width: 1.75),
            KeyboardKey("A", led: 9),
            KeyboardKey("S", led: 15),
            KeyboardKey("D", led: 21),
            KeyboardKey("F", led: 27),
            KeyboardKey("G", led: 33),
            KeyboardKey("H", led: 39),
            KeyboardKey("J", led: 45),
            KeyboardKey("K", led: 51),
            KeyboardKey("L", led: 57),
            KeyboardKey(";", led: 63),
            KeyboardKey("'", led: 69),
            KeyboardKey("Enter", led: 81, width: 2.25)
        ]),
        row([
            KeyboardKey("LShift", led: 4, width: 2.25, subLabel: "라이트바"),
            KeyboardKey("Z", led: 10),
            KeyboardKey("X", led: 16),
            KeyboardKey("C", led: 22),
            KeyboardKey("V", led: 28),
            KeyboardKey("B", led: 34, subLabel: "배터리"),
            KeyboardKey("N", led: 40),
            KeyboardKey("M", led: 46),
            KeyboardKey(",", led: 52),
            KeyboardKey(".", led: 58),
            KeyboardKey("/", led: 64),
            KeyboardKey("RShift", led: 82, width: 2.75, subLabel: "측면등"),
            KeyboardKey("↑", led: 94, subLabel: "밝기+")
        ], gaps: [12: 1.25]),
        row([
            KeyboardKey("LCtrl", led: 5, width: 1.25),
            KeyboardKey("Win/⌘", led: 11, width: 1.25),
            KeyboardKey("LAlt/⌥", led: 17, width: 1.25),
            KeyboardKey("Space", led: 35, width: 6.25),
            KeyboardKey("RAlt/⌥", led: 53, width: 1.25),
            KeyboardKey("Fn", led: 59, width: 1.25),
            KeyboardKey("App", led: 65, width: 1.25),
            KeyboardKey("RCtrl", led: 83, width: 1.25),
            KeyboardKey("←", led: 89, subLabel: "속도-"),
            KeyboardKey("↓", led: 95, subLabel: "밝기-"),
            KeyboardKey("→", led: 101, subLabel: "속도+")
        ], gaps: [8: 0.25])
    ]

    static let allKeys: [KeyboardKey] = rows.flatMap { row in
        row.compactMap {
            if case let .key(key) = $0 { return key }
            return nil
        }
    }

    static let keyByLED: [Int: KeyboardKey] = Dictionary(uniqueKeysWithValues: allKeys.map { ($0.led, $0) })

    // 11-column Audio Dance equalizer band mapping (bottom-to-top per frequency band)
    static let audioColumns: [[Int]] = [
        [5, 11, 4, 3, 2, 1, 0],
        [17, 10, 16, 9, 15, 8, 14, 7, 13, 12, 18],
        [22, 28, 21, 27, 20, 26, 19, 25, 24, 30],
        [34, 35, 33, 39, 32, 38, 31, 37, 36, 42],
        [40, 46, 45, 51, 44, 50, 43, 49, 48, 54],
        [52, 58, 57, 63, 56, 62, 55, 61, 60, 66],
        [53, 59, 64, 69, 68, 74, 67, 73, 72, 78],
        [65, 83, 82, 81, 80, 79],
        [89, 86, 85, 84],
        [95, 94, 92, 91, 90],
        [101, 98, 97, 96]
    ]

    private static func row(_ keys: [KeyboardKey], gaps: [Int: Double] = [:]) -> [KeyRowItem] {
        var result: [KeyRowItem] = []
        for (index, key) in keys.enumerated() {
            if let gap = gaps[index] {
                result.append(.gap(gap))
            }
            result.append(.key(key))
        }
        return result
    }
}

enum PerKeyTool: String, CaseIterable, Identifiable, Sendable {
    case paint = "브러시"
    case erase = "지우개"
    case eyedropper = "스포이드"
    case select = "영역 선택"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .paint: return "paintbrush.fill"
        case .erase: return "eraser.fill"
        case .eyedropper: return "eyedropper"
        case .select: return "DirectSelection"
        }
    }
    var systemSymbol: String {
        switch self {
        case .paint: return "paintbrush.fill"
        case .erase: return "eraser.fill"
        case .eyedropper: return "eyedropper.halffull"
        case .select: return "lasso"
        }
    }
}

enum GradientDirection: String, CaseIterable, Identifiable, Sendable {
    case horizontal = "좌→우 수평"
    case vertical = "상→하 수직"
    case radial = "중심→외곽 원형"

    var id: String { rawValue }
}

// MARK: - 4-byte Key Matrix Action Encoding & Decoding

struct KeyMatrixItem: Identifiable, Hashable, Sendable {
    let id: String
    let category: String
    let title: String
    let subtitle: String
    let bytes: [UInt8] // 4 bytes: [type, b1, b2, b3]

    init(category: String, title: String, subtitle: String, bytes: [UInt8]) {
        self.id = "\(category)-\(title)-\(bytes.map { String(format: "%02X", $0) }.joined())"
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.bytes = bytes
    }
}

enum KeymapCatalog {
    static let hidKeyNames: [UInt8: String] = {
        var map: [UInt8: String] = [
            0x28: "Enter", 0x29: "Esc", 0x2A: "Backspace", 0x2B: "Tab", 0x2C: "Space",
            0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\", 0x33: ";", 0x34: "'",
            0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/", 0x39: "CapsLock",
            0x46: "PrtSc", 0x47: "ScrLk", 0x48: "Pause", 0x49: "Ins", 0x4A: "Home",
            0x4B: "PgUp", 0x4C: "Del", 0x4D: "End", 0x4E: "PgDn",
            0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑",
            0x65: "App (Menu)", 0x68: "F13",
            0x90: "한/영 (Lang1)", 0x91: "한자 (Lang2)"
        ]
        for i in 0..<26 {
            map[UInt8(0x04 + i)] = String(UnicodeScalar(65 + i)!)
        }
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        for (i, d) in digits.enumerated() {
            map[UInt8(0x1E + i)] = d
        }
        for i in 0..<12 {
            map[UInt8(0x3A + i)] = "F\(i + 1)"
        }
        return map
    }()

    static let modifierBitNames: [(bit: UInt8, name: String)] = [
        (0x01, "LCtrl"), (0x02, "LShift"), (0x04, "LAlt/⌥"), (0x08, "LWin/⌘"),
        (0x10, "RCtrl"), (0x20, "RShift"), (0x40, "RAlt/⌥"), (0x80, "RWin/⌘")
    ]

    static let presets: [KeyMatrixItem] = {
        var items: [KeyMatrixItem] = []

        // 1. 모디파이어 & 한국어/맥 필수 키
        items.append(contentsOf: [
            .init(category: "추천 / Mac & 한국어", title: "한/영 전환 (Lang1)", subtitle: "macOS/Windows 한영키 (0x90)", bytes: [0x00, 0x00, 0x00, 0x90]),
            .init(category: "추천 / Mac & 한국어", title: "한자 전환 (Lang2)", subtitle: "macOS/Windows 한자키 (0x91)", bytes: [0x00, 0x00, 0x00, 0x91]),
            .init(category: "추천 / Mac & 한국어", title: "Left Command (⌘ / LWin)", subtitle: "왼쪽 Command / Windows 키", bytes: [0x00, 0x08, 0x00, 0x00]),
            .init(category: "추천 / Mac & 한국어", title: "Left Option (⌥ / LAlt)", subtitle: "왼쪽 Option / Alt 키", bytes: [0x00, 0x04, 0x00, 0x00]),
            .init(category: "추천 / Mac & 한국어", title: "Right Command (⌘ / RWin)", subtitle: "오른쪽 Command / Windows 키", bytes: [0x00, 0x80, 0x00, 0x00]),
            .init(category: "추천 / Mac & 한국어", title: "Right Option (⌥ / RAlt)", subtitle: "오른쪽 Option / Alt 키", bytes: [0x00, 0x40, 0x00, 0x00]),
            .init(category: "추천 / Mac & 한국어", title: "Left Control", subtitle: "왼쪽 Control 키", bytes: [0x00, 0x01, 0x00, 0x00]),
            .init(category: "추천 / Mac & 한국어", title: "Left Shift", subtitle: "왼쪽 Shift 키", bytes: [0x00, 0x02, 0x00, 0x00]),
            .init(category: "추천 / Mac & 한국어", title: "Right Shift", subtitle: "오른쪽 Shift 키", bytes: [0x00, 0x20, 0x00, 0x00]),
            .init(category: "추천 / Mac & 한국어", title: "Right Control", subtitle: "오른쪽 Control 키", bytes: [0x00, 0x10, 0x00, 0x00]),
            .init(category: "추천 / Mac & 한국어", title: "CapsLock", subtitle: "대소문자 잠금", bytes: [0x00, 0x00, 0x00, 0x39]),
            .init(category: "추천 / Mac & 한국어", title: "F13", subtitle: "사용자 정의 단축키용 F13", bytes: [0x00, 0x00, 0x00, 0x68]),
            .init(category: "추천 / Mac & 한국어", title: "기능 없음 / 기본 레이어 유지", subtitle: "비활성화 (FN 레이어에서는 기본키 통과)", bytes: [0x00, 0x00, 0x00, 0x00])
        ])

        // 2. 멀티미디어 & 화면 밝기
        items.append(contentsOf: [
            .init(category: "멀티미디어", title: "재생 / 일시정지", subtitle: "Media Play/Pause", bytes: [0x02, 0x00, 0x00, 0xCD]),
            .init(category: "멀티미디어", title: "음소거 (Mute)", subtitle: "Audio Mute", bytes: [0x02, 0x00, 0x00, 0xE2]),
            .init(category: "멀티미디어", title: "볼륨 +", subtitle: "Volume Up", bytes: [0x02, 0x00, 0x00, 0xE9]),
            .init(category: "멀티미디어", title: "볼륨 -", subtitle: "Volume Down", bytes: [0x02, 0x00, 0x00, 0xEA]),
            .init(category: "멀티미디어", title: "이전 곡", subtitle: "Previous Track", bytes: [0x02, 0x00, 0x00, 0xB6]),
            .init(category: "멀티미디어", title: "다음 곡", subtitle: "Next Track", bytes: [0x02, 0x00, 0x00, 0xB5]),
            .init(category: "멀티미디어", title: "정지", subtitle: "Media Stop", bytes: [0x02, 0x00, 0x00, 0xB7]),
            .init(category: "멀티미디어", title: "화면 밝기 +", subtitle: "Display Brightness Up", bytes: [0x02, 0x00, 0x00, 0x6F]),
            .init(category: "멀티미디어", title: "화면 밝기 -", subtitle: "Display Brightness Down", bytes: [0x02, 0x00, 0x00, 0x70]),
            .init(category: "멀티미디어", title: "계산기 실행", subtitle: "Launch Calculator", bytes: [0x02, 0x00, 0x01, 0x92])
        ])

        // 3. 키보드 내장 & 조명 제어
        items.append(contentsOf: [
            .init(category: "키보드 내장 기능", title: "배터리 잔량 라이트바 표시", subtitle: "Fn+B 기본 기능", bytes: [0x07, 0x00, 0x00, 0x0C]),
            .init(category: "키보드 내장 기능", title: "Windows 키 잠금 토글", subtitle: "Lock Win Key", bytes: [0x07, 0x00, 0x00, 0x01]),
            .init(category: "키보드 내장 기능", title: "전체 키보드 잠금 토글", subtitle: "Lock Keyboard", bytes: [0x07, 0x00, 0x00, 0x02]),
            .init(category: "키보드 내장 기능", title: "백라이트 효과 전환", subtitle: "Cycle Main RGB Effect", bytes: [0x08, 0x00, 0x00, 0x00]),
            .init(category: "키보드 내장 기능", title: "백라이트 색상 전환", subtitle: "Cycle Main RGB Color", bytes: [0x08, 0x02, 0x00, 0x00]),
            .init(category: "키보드 내장 기능", title: "백라이트 밝기 +", subtitle: "Main Brightness +", bytes: [0x08, 0x03, 0x01, 0x00]),
            .init(category: "키보드 내장 기능", title: "백라이트 밝기 -", subtitle: "Main Brightness -", bytes: [0x08, 0x03, 0x02, 0x00]),
            .init(category: "키보드 내장 기능", title: "백라이트 속도 +", subtitle: "Main Speed +", bytes: [0x08, 0x04, 0x01, 0x00]),
            .init(category: "키보드 내장 기능", title: "백라이트 속도 -", subtitle: "Main Speed -", bytes: [0x08, 0x04, 0x02, 0x00]),
            .init(category: "키보드 내장 기능", title: "측면 조명 효과 전환", subtitle: "Cycle Side Light", bytes: [0x08, 0x00, 0x00, 0x01]),
            .init(category: "키보드 내장 기능", title: "라이트바 효과 전환", subtitle: "Cycle Light Bar", bytes: [0x08, 0x00, 0x00, 0x02])
        ])

        // 4. 마우스 동작
        items.append(contentsOf: [
            .init(category: "마우스 동작", title: "마우스 좌클릭", subtitle: "Left Click", bytes: [0x01, 0x01, 0x01, 0x00]),
            .init(category: "마우스 동작", title: "마우스 우클릭", subtitle: "Right Click", bytes: [0x01, 0x02, 0x01, 0x00]),
            .init(category: "마우스 동작", title: "마우스 휠클릭", subtitle: "Middle Click", bytes: [0x01, 0x03, 0x01, 0x00]),
            .init(category: "마우스 동작", title: "스크롤 위로", subtitle: "Scroll Up", bytes: [0x01, 0x08, 0x00, 0x00]),
            .init(category: "마우스 동작", title: "스크롤 아래로", subtitle: "Scroll Down", bytes: [0x01, 0x09, 0x00, 0x00])
        ])

        // 5. 일반 키
        for (code, label) in hidKeyNames.sorted(by: { $0.key < $1.key }) {
            items.append(.init(category: "일반 키", title: label, subtitle: String(format: "HID 0x%02X", code), bytes: [0x00, 0x00, 0x00, code]))
        }

        return items
    }()

    static func describe(_ bytes: [UInt8]) -> String {
        guard bytes.count == 4 else { return "알 수 없음" }
        let b0 = bytes[0], b1 = bytes[1], b2 = bytes[2], b3 = bytes[3]
        if b0 == 0 && b1 == 0 && b2 == 0 && b3 == 0 {
            return "비어 있음 (기본값)"
        }
        switch b0 {
        case 0x00:
            var parts: [String] = []
            for (bit, name) in modifierBitNames where (b1 & bit) != 0 {
                parts.append(name)
            }
            if b2 != 0 {
                parts.append(hidKeyNames[b2] ?? String(format: "0x%02X", b2))
            }
            if b3 != 0 {
                parts.append(hidKeyNames[b3] ?? String(format: "0x%02X", b3))
            }
            return parts.isEmpty ? "비어 있음" : parts.joined(separator: " + ")
        case 0x01:
            switch b1 {
            case 1: return b2 > 1 ? "좌클릭 ×\(b2)" : "마우스 좌클릭"
            case 2: return "마우스 우클릭"
            case 3: return "마우스 휠클릭"
            case 4: return "마우스 뒤로"
            case 5: return "마우스 앞으로"
            case 8: return "스크롤 위로"
            case 9: return "스크롤 아래로"
            default: return String(format: "마우스 (%02X %02X)", b1, b2)
            }
        case 0x02:
            let usage = (UInt16(b2) << 8) | UInt16(b3)
            switch usage {
            case 0x0CD: return "재생/일시정지"
            case 0x0E2: return "음소거"
            case 0x0E9: return "볼륨 +"
            case 0x0EA: return "볼륨 -"
            case 0x0B5: return "다음 곡"
            case 0x0B6: return "이전 곡"
            case 0x0B7: return "정지"
            case 0x06F: return "화면 밝기 +"
            case 0x070: return "화면 밝기 -"
            case 0x192: return "계산기"
            case 0x18A: return "메일"
            case 0x194: return "내 컴퓨터"
            case 0x223: return "브라우저 홈"
            default: return String(format: "미디어 (0x%03X)", usage)
            }
        case 0x03:
            return "매크로 #\(b3 + 1)"
        case 0x07:
            switch b3 {
            case 0x01: return "Win 키 잠금"
            case 0x02: return "키보드 잠금"
            case 0x04: return "키보드 초기화"
            case 0x05: return "블루투스 1"
            case 0x06: return "블루투스 2"
            case 0x07: return "블루투스 3"
            case 0x08: return "2.4G 무선 모드"
            case 0x0C: return "배터리 잔량 표시"
            case 0x18: return "Windows 모드"
            case 0x19: return "Android 모드"
            case 0x1A: return "Mac 모드"
            case 0x1B: return "iOS 모드"
            default: return String(format: "내장 기능 (0x%02X)", b3)
            }
        case 0x08:
            let area: String
            switch b3 {
            case 0: area = "메인 조명"
            case 1: area = "측면 조명"
            case 2: area = "라이트바"
            default: area = "조명(\(b3))"
            }
            let item: String
            switch b1 {
            case 0: item = "효과"
            case 2: item = "색상"
            case 3: item = "밝기"
            case 4: item = "속도"
            default: item = "설정(\(b1))"
            }
            let dir = b2 == 0 ? "전환" : (b2 == 1 ? "+" : "-")
            return "\(area) \(item) \(dir)"
        case 0x0D:
            return b1 == 0 ? "Fn (레이어 1)" : "Fn2 (레이어 2)"
        default:
            return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }
}

struct F87Profile: Codable, Hashable, Sendable {
    var effect: Int
    var brightness: Int
    var speed: Int
    var colorful: Bool
    var color: RGBColor
    var sideLightMode: Int
    var perKey: [Int: RGBColor]
}

struct StoredProfile: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var profile: F87Profile
    var createdAt: Date

    init(id: UUID = UUID(), name: String, profile: F87Profile, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.profile = profile
        self.createdAt = createdAt
    }
}

struct BatteryStatus: Equatable, Sendable {
    let percent: Int // 1..100
    let isCharging: Bool
    let updatedAt: Date
}

struct PowerTelemetry: Sendable {
    let percent: Int
    let isCharging: Bool
    let capacityMah: Int          // 4000 mAh
    let batteryVoltage: Double    // 3.5V ~ 4.2V
    let mcuCurrentMa: Double      // ~18 mA
    let mainLedsCurrentMa: Double // 0 ~ 295 mA
    let sideLedsCurrentMa: Double // 0 ~ 74 mA
    let totalDischargeCurrentMa: Double
    let totalPowerMw: Double      // Total consumption in milliwatts
    let totalPowerW: Double       // Total consumption in watts
    let chargingCurrentMa: Double // ~650 mA (5V USB input)
    let chargingPowerW: Double    // ~3.25 W
    let remainingUsageHours: Double
    let timeToFullChargeHours: Double
    let isReactiveMode: Bool
    let isActivelyTyping: Bool
    let typingSpeedCPM: Int
    let reactiveDutyPercent: Double // 0% ~ 100%

    static func calculate(
        battery: BatteryStatus?,
        effect: Int,
        brightness: Int,
        activePerKeyCount: Int,
        sideLightMode: Int,
        lightBarMode: Int,
        isWiredUSB: Bool,
        isActivelyTyping: Bool = false,
        typingSpeedCPM: Int = 0
    ) -> PowerTelemetry {
        let pct = battery?.percent ?? 36
        let charging = battery?.isCharging ?? false
        let capacity = 4000 // AULA F87 Pro V1 4000mAh Li-ion battery

        let v: Double = charging
            ? 3.85 + (Double(pct) / 100.0) * 0.35
            : 3.50 + (Double(pct) / 100.0) * 0.65

        let mcu: Double = isWiredUSB ? 24.0 : 18.0

        let isReactive = (effect == 12 || effect == 7 || effect == 4)
        let mainLeds: Double
        let dutyPercent: Double

        if effect == 0 || brightness == 0 {
            mainLeds = 0.0
            dutyPercent = 0.0
        } else if isReactive {
            let maxBrightnessScale = Double(max(1, brightness)) / 4.0
            if isActivelyTyping {
                // 실시간 타건 감지 중: 키 입력 빈도(CPM) 및 효과 확산 범위에 비례하여 동적 소비 전류 계산
                let spreadMultiplier: Double = (effect == 7 ? 2.2 : (effect == 4 ? 2.6 : 1.0))
                let kps = max(1.5, Double(typingSpeedCPM) / 60.0)
                let activeKeyEquivalent = min(14.0, kps * 0.38 * spreadMultiplier)
                mainLeds = max(4.0, (activeKeyEquivalent * 3.39 * maxBrightnessScale).rounded())
                dutyPercent = min(100.0, (mainLeds / max(1.0, 295.0 * maxBrightnessScale)) * 100.0)
            } else {
                // 키를 누르지 않고 대기 중인 상태: 모든 백라이트 LED 완전 소등 (0 mA)
                mainLeds = 0.0
                dutyPercent = 0.0
            }
        } else if effect == LightingEffect.customPerKeyID {
            let scale = Double(max(1, brightness)) / 4.0
            mainLeds = Double(activePerKeyCount) * 2.8 * scale
            dutyPercent = (Double(activePerKeyCount) / 87.0) * 100.0
        } else {
            switch brightness {
            case 1: mainLeds = 48.0
            case 2: mainLeds = 112.0
            case 3: mainLeds = 196.0
            case 4: mainLeds = 295.0
            default: mainLeds = 0.0
            }
            dutyPercent = 100.0
        }

        let sideLeds: Double = (sideLightMode == 0 ? 0.0 : (sideLightMode == 3 ? 36.0 : 52.0))
            + (lightBarMode == 0 ? 0.0 : 22.0)

        let totalDischarge = mcu + mainLeds + sideLeds
        let powerMw = totalDischarge * v
        let powerW = powerMw / 1000.0

        let chgCurrent: Double
        if charging {
            // Constant Current (CC) phase up to ~85%, then gentle Constant Voltage (CV) taper
            if pct < 85 {
                chgCurrent = 680.0
            } else {
                chgCurrent = 680.0 * max(0.25, Double(100 - pct) / 15.0)
            }
        } else {
            chgCurrent = 0.0
        }
        let chgPowerW = charging ? (chgCurrent * 5.0 / 1000.0) : 0.0

        let remainingMah = Double(capacity) * (Double(pct) / 100.0)

        // Estimated continuous battery life:
        // In reactive mode, typical typing sessions consist of intermittent typing + pauses.
        // Effective average current for battery life estimate is ~8mA LED + MCU + side.
        let effectiveDischargeForEstimate: Double
        if isReactive {
            let avgReactiveLed = 8.0 * (Double(max(1, brightness)) / 4.0)
            effectiveDischargeForEstimate = mcu + avgReactiveLed + sideLeds
        } else {
            effectiveDischargeForEstimate = totalDischarge
        }

        let usageHours = max(0.5, remainingMah / max(12.0, effectiveDischargeForEstimate))

        let neededMah = Double(capacity) * (Double(100 - pct) / 100.0)
        let netChargeCurrent = max(120.0, chgCurrent - (isWiredUSB ? 0 : totalDischarge))
        let chargeHours = charging ? max(0.1, neededMah / netChargeCurrent) : 0.0

        return PowerTelemetry(
            percent: pct,
            isCharging: charging,
            capacityMah: capacity,
            batteryVoltage: v,
            mcuCurrentMa: mcu,
            mainLedsCurrentMa: mainLeds,
            sideLedsCurrentMa: sideLeds,
            totalDischargeCurrentMa: totalDischarge,
            totalPowerMw: powerMw,
            totalPowerW: powerW,
            chargingCurrentMa: chgCurrent,
            chargingPowerW: chgPowerW,
            remainingUsageHours: usageHours,
            timeToFullChargeHours: chargeHours,
            isReactiveMode: isReactive,
            isActivelyTyping: isActivelyTyping,
            typingSpeedCPM: typingSpeedCPM,
            reactiveDutyPercent: dutyPercent
        )
    }
}

struct HardwareSnapshot: Sendable {
    let connectionMode: String // "2.4GHz 무선 (3554:FA09)" or "USB 유선 (258A:010C)"
    let modelName: String      // "AULA F87 Pro V1"
    let rawConfig: [UInt8]     // 128 bytes
    let effect: Int
    let brightness: Int
    let speed: Int
    let colorful: Bool
    let colorSlot: Int
    let sideLightMode: Int
    let lightBarMode: Int
    let sleepRawSteps: Int     // 30s steps
    let debounceStage: Int     // 1..5
    let tapSensitivity: Int    // 0 or 10..127
    let battery: BatteryStatus?
}
