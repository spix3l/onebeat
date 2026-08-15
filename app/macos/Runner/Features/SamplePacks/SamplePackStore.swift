import Foundation

/// Owns persistence for the browser: the folders imported into it, and which of
/// its rows the user has opened or closed.
///
/// Keeping UserDefaults out of the window and channel code makes the storage
/// policy independently testable and leaves room for migration later.
final class SamplePackStore {
  private static let pathsKey = "onebeat.samplePackPaths"
  private static let expansionKey = "onebeat.browserExpandedNodes"
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

  /// Only the rows the user has actually toggled are stored, so a row whose
  /// default changes in a later build follows the new default until it is
  /// touched.
  func loadExpansion() -> [String: Bool] {
    defaults.dictionary(forKey: Self.expansionKey) as? [String: Bool] ?? [:]
  }

  func saveExpansion(_ expansion: [String: Bool]) {
    defaults.set(expansion, forKey: Self.expansionKey)
  }
}
