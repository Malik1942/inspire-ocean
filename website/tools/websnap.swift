// WebKit snapshot: renders a page the way Safari does (ui-serif is New York).
// usage: websnap <url> <width> <height> <out.png> [full|view] [extra-css] [scale]
import AppKit
import WebKit

let args = CommandLine.arguments
if args.count < 5 {
    print("usage: websnap <url> <width> <height> <out.png> [full|view] [extra-css] [scale]")
    exit(2)
}
let url = URL(string: args[1])!
let width = Double(args[2])!
let height = Double(args[3])!
let out = args[4]
let fullPage = args.count > 5 && args[5] == "full"
let css = args.count > 6 ? args[6] : ""
let scale = args.count > 7 ? (Double(args[7]) ?? 1) : 1

final class Snapper: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    init(_ webView: WKWebView) { self.webView = webView }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.measure() }
    }

    func measure() {
        guard fullPage else { return take(height: height) }
        webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)") { value, _ in
            let full = (value as? Double) ?? height
            self.webView.setFrameSize(NSSize(width: width, height: full))
            self.webView.window?.setContentSize(NSSize(width: width, height: full))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.take(height: full) }
        }
    }

    func take(height: Double) {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: width, height: height)
        config.snapshotWidth = NSNumber(value: width * scale)
        webView.takeSnapshot(with: config) { image, error in
            guard let image, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                print("snapshot failed: \(String(describing: error))")
                exit(1)
            }
            try? png.write(to: URL(fileURLWithPath: out))
            print("wrote \(out) \(Int(width * scale))x\(Int(height * scale))")
            exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let configuration = WKWebViewConfiguration()
if !css.isEmpty {
    let source = "var s=document.createElement('style');s.textContent=\(String(reflecting: css));document.documentElement.appendChild(s);"
    configuration.userContentController.addUserScript(
        WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
}
let frame = NSRect(x: 0, y: 0, width: width, height: height)
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
let webView = WKWebView(frame: frame, configuration: configuration)
window.contentView = webView
window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
window.orderBack(nil)
let snapper = Snapper(webView)
webView.navigationDelegate = snapper
webView.load(URLRequest(url: url))
DispatchQueue.main.asyncAfter(deadline: .now() + 40) { print("timed out"); exit(3) }
app.run()
