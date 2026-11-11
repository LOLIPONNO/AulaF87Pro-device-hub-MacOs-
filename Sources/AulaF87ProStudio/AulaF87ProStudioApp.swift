import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct AulaF87ProStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = AppViewModel()

    init() {
        if CommandLine.arguments.contains("--probe") {
            let service = HIDService()
            do {
                let snap = try service.connectAndReadSnapshot()
                print("=== HARDWARE SNAPSHOT ===")
                print("Model:", snap.modelName)
                print("Mode:", snap.connectionMode)
                if let bat = snap.battery {
                    print("Battery: \(bat.percent)% (charging: \(bat.isCharging))")
                }
                print("Effect: #\(snap.effect) (\(LightingEffect.info(for: snap.effect).titleKo))")
                print("Brightness: \(snap.brightness)/4, Speed: \(snap.speed)/4, Colorful: \(snap.colorful)")
                print("SideLight: \(snap.sideLightMode), LightBar: \(snap.lightBarMode)")
                print("Debounce: Stage \(snap.debounceStage), SleepSteps: \(snap.sleepRawSteps) (\(snap.sleepRawSteps * 30)s)")
                if let matrix0 = try? service.readKeyMatrix(layer: 0) {
                    print("Layer 0 Matrix read OK (\(matrix0.count) bytes)")
                } else {
                    print("Layer 0 Matrix: Keyboard currently in wireless idle sleep")
                }
                exit(0)
            } catch {
                print("Probe error:", error.localizedDescription)
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup("AULA F87 Pro Studio") {
            ContentView(vm: vm)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1160, height: 820)
    }
}
