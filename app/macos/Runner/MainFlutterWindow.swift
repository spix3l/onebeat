import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // The app draws its own top bar, exactly as the design screens do: the
    // window's title bar is made transparent and its content view extends up
    // under it, so the only chrome above the transport is the real traffic
    // lights. Without this there are two title strips stacked on each other.
    //
    // These run *before* the Flutter view is installed. Mutating `styleMask`
    // makes AppKit rebuild the window's frame view, which drops the already
    // attached content view's constraints and leaves a black window.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false
    self.minSize = NSSize(width: 1280, height: 720)

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
