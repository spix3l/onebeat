import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  private var samplePackBridge: SamplePackBridge?

  override func awakeFromNib() {
    // The app draws its own top bar, exactly as the design screens do: the
    // window's title bar is made transparent and its content view extends up
    // under it, so the only chrome above the transport is the real traffic
    // lights. Without this there are two title strips stacked on each other.
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

    samplePackBridge = SamplePackBridge(
      messenger: flutterViewController.engine.binaryMessenger,
      window: self
    )
    registerForDraggedTypes([.fileURL])

    super.awakeFromNib()
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    samplePackBridge?.draggingEntered(sender) ?? []
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    samplePackBridge?.performDragOperation(sender) ?? false
  }
}
