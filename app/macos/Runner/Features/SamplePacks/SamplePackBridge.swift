import Cocoa
import FlutterMacOS

/// Owns the native boundary for sample packs: Flutter method calls, persisted
/// folders, the folder picker, and Finder drops. The window only forwards
/// lifecycle and dragging callbacks to this object.
final class SamplePackBridge {
  static let channelName = "onebeat/sample_packs"

  private let channel: FlutterMethodChannel
  private let store: SamplePackStore
  private let folderPicker: SamplePackFolderPicker

  init(
    messenger: FlutterBinaryMessenger,
    store: SamplePackStore = SamplePackStore(),
    folderPicker: SamplePackFolderPicker = SamplePackFolderPicker()
  ) {
    self.channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.store = store
    self.folderPicker = folderPicker
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    sender.draggingPasteboard.types?.contains(.fileURL) == true ? .copy : []
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true,
    ]
    guard let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self],
      options: options
    ) as? [URL] else {
      return false
    }

    let paths = urls.map(\.path)
    guard !paths.isEmpty else { return false }
    channel.invokeMethod("samplePackFoldersDropped", arguments: paths)
    return true
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickSampleFolder":
      result(folderPicker.pickFolder())

    case "loadSampleFolders":
      result(store.loadPaths())

    case "saveSampleFolders":
      guard let paths = call.arguments as? [String] else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "Sample folder paths are required.",
          details: nil
        ))
        return
      }
      store.savePaths(paths)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
