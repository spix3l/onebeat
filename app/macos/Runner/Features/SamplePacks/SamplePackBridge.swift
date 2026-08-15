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
  private weak var window: NSWindow?

  init(
    messenger: FlutterBinaryMessenger,
    window: NSWindow? = nil,
    store: SamplePackStore = SamplePackStore(),
    folderPicker: SamplePackFolderPicker = SamplePackFolderPicker()
  ) {
    self.channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.window = window
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

    var folders: [String] = []
    var audioFiles: [String] = []
    for url in urls {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        continue
      }
      if isDirectory.boolValue {
        folders.append(url.path)
      } else if Self.isSupportedAudioFile(url) {
        audioFiles.append(url.path)
      }
    }

    let location = sender.draggingLocation
    let contentHeight = window?.contentView?.bounds.height ?? 0
    let position: [String: Double] = [
      "x": Double(location.x),
      // Cocoa's window origin is bottom-left; Flutter's is top-left.
      "y": Double(contentHeight > 0 ? contentHeight - location.y : location.y),
    ]

    if !folders.isEmpty {
      channel.invokeMethod("samplePackFoldersDropped", arguments: folders)
    }
    if !audioFiles.isEmpty {
      channel.invokeMethod(
        "audioFilesDropped",
        arguments: ["paths": audioFiles, "x": position["x"]!, "y": position["y"]!]
      )
    }
    return !folders.isEmpty || !audioFiles.isEmpty
  }

  private static func isSupportedAudioFile(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "wav"
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
