import AppKit

let appDelegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }
let application = NSApplication.shared
MainActor.assumeIsolated {
    application.delegate = appDelegate
    application.setActivationPolicy(.regular)
    application.appearance = NSAppearance(named: .aqua)
}

if CommandLine.arguments.contains("--render") {
    MainActor.assumeIsolated {
        RenderMode.run()
    }
    exit(0)
}

application.run()
