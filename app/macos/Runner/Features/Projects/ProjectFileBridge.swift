import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// The native half of ⌘O and ⌘S: the two panels, and nothing else.
///
/// A `.obt` project is a directory that Finder presents as one document
/// (ADR-004 §2). That single fact is what shapes both panels here — the open
/// panel has to accept a *package* while refusing to descend into it, and the
/// save panel has to own the extension so a project can never be written under
/// a name Finder will not open.
final class ProjectFileBridge {
  static let channelName = "onebeat/project_files"
  static let projectExtension = "obt"
  static let projectTypeIdentifier = "dev.onebeat.project"

  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?

  init(messenger: FlutterBinaryMessenger, window: NSWindow? = nil) {
    self.channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.window = window
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickProjectToOpen":
      result(openPanel())

    case "pickProjectDestination":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(
        savePanel(
          suggestedName: arguments["suggestedName"] as? String ?? "Untitled.obt",
          directory: arguments["directory"] as? String ?? ""
        )
      )

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openPanel() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    // A package is a directory. Both flags are on so the panel accepts the
    // bundle itself, and `treatsFilePackagesAsDirectories` stays off so a
    // double-click selects the project rather than opening it like a folder.
    panel.canChooseDirectories = true
    panel.treatsFilePackagesAsDirectories = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    panel.message = "Choose a OneBeat project."
    Self.restrictToProjects(panel)

    return panel.runModal() == .OK ? panel.url?.path : nil
  }

  private func savePanel(suggestedName: String, directory: String) -> String? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = suggestedName
    Self.restrictToProjects(panel)
    panel.canCreateDirectories = true
    // The panel would otherwise hide the extension it is about to append, and a
    // user renaming `Untitled` to `Untitled 2` cannot see what they are making.
    panel.isExtensionHidden = false
    panel.prompt = "Save"
    panel.message = "Save the project as a .obt bundle."
    if !directory.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
    }

    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url.pathExtension.lowercased() == Self.projectExtension
      ? url.path
      : url.appendingPathExtension(Self.projectExtension).path
  }

  /// Limits a panel to project bundles.
  ///
  /// The type identifier is what the app exports in its Info.plist, so it is
  /// what a built app matches on. `UTType` arrived in macOS 11 and the app
  /// deploys back to 10.15, hence the older extension list underneath — and the
  /// extension is also the fallback on 11+ for a debug run whose exported type
  /// Launch Services has not registered yet.
  private static func restrictToProjects(_ panel: NSSavePanel) {
    if #available(macOS 11.0, *) {
      if let declared = UTType(projectTypeIdentifier) {
        panel.allowedContentTypes = [declared]
        return
      }
      if let byExtension = UTType(filenameExtension: projectExtension) {
        panel.allowedContentTypes = [byExtension]
        return
      }
    }
    panel.allowedFileTypes = [projectExtension]
  }
}
