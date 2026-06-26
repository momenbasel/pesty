import AppKit

@main
struct PestyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController.shared
        app.delegate = delegate
        app.run()
    }
}
