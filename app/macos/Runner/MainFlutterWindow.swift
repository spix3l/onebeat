import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  private let titlebarHitHeight: CGFloat = 24
  private var samplePackBridge: SamplePackBridge?
  private var projectFileBridge: ProjectFileBridge?

  override func awakeFromNib() {
    // The app draws its own top bar, exactly as the design screens do: the
    // window's title bar is made transparent and its content view extends up
    // under it, so the only chrome above the transport is the real traffic
    // lights. Without this there are two title strips stacked on each other.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    // The Flutter surface draws plugin titlebars under the transparent native
    // titlebar. AppKit must not claim those drags as moves of the main window.
    self.isMovable = false
    self.isMovableByWindowBackground = false
    self.minSize = NSSize(width: 1280, height: 720)

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    samplePackBridge = SamplePackBridge(
      messenger: flutterViewController.engine.binaryMessenger,
      window: self
    )
    projectFileBridge = ProjectFileBridge(
      messenger: flutterViewController.engine.binaryMessenger,
      window: self
    )
    registerForDraggedTypes([.fileURL])

    super.awakeFromNib()
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown,
       event.clickCount == 2,
       event.window === self,
       event.locationInWindow.y >= frame.height - titlebarHitHeight {
      // fullSizeContentView puts Flutter's view over the titlebar, so AppKit
      // never receives the native double-click that normally toggles zoom.
      performZoom(nil)
      return
    }
    super.sendEvent(event)
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    samplePackBridge?.draggingEntered(sender) ?? []
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    samplePackBridge?.performDragOperation(sender) ?? false
  }
}
