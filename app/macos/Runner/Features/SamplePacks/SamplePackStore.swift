import Foundation

/// Owns persistence for the folders imported into the browser.
///
/// Keeping UserDefaults out of the window and channel code makes the storage
/// policy independently testable and leaves room for migration later.
final class SamplePackStore {
  private static let pathsKey = "onebeat.samplePackPaths"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func loadPaths() -> [String] {
    defaults.stringArray(forKey: Self.pathsKey) ?? []
  }

  func savePaths(_ paths: [String]) {
    defaults.set(paths, forKey: Self.pathsKey)
  }
}
