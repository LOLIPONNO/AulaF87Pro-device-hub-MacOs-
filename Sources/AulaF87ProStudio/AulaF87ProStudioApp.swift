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

    func applicationWillTerminate(_ notification: Notification) {
        HIDService.restorePendingKarabinerConfigIfNeeded()
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
                var snap = try service.connectAndReadSnapshot()
                if snap.connectionMode.contains("Bluetooth") && snap.battery == nil {
                    let waitEnd = Date().addingTimeInterval(1.5)
                    while service.cachedBattery == nil && Date() < waitEnd {
                        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                    }
                    if let bleBat = service.cachedBattery {
                        snap = HardwareSnapshot(
                            connectionMode: snap.connectionMode,
                            modelName: snap.modelName,
                            rawConfig: snap.rawConfig,
                            effect: snap.effect,
                            brightness: snap.brightness,
                            speed: snap.speed,
                            colorful: snap.colorful,
                            colorSlot: snap.colorSlot,
                            sideLightMode: snap.sideLightMode,
                            lightBarMode: snap.lightBarMode,
                            sleepRawSteps: snap.sleepRawSteps,
                            debounceStage: snap.debounceStage,
                            tapSensitivity: snap.tapSensitivity,
                            battery: bleBat
                        )
                    }
                }
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
                if snap.connectionMode.contains("Bluetooth") {
                    print("Layer 0 Matrix: Bluetooth preview mode (hardware flash read requires 2.4GHz or USB)")
                } else if let matrix0 = try? service.readKeyMatrix(layer: 0) {
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
