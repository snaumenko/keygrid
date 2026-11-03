// Entry point. Creates the app, hands control to AppController, and runs
// the event loop. Everything else happens in AppController.
import AppKit

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
