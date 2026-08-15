import Cocoa

/// Presents the native folder picker for importing a sample pack.
struct SamplePackFolderPicker {
  func pickFolder() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Add Pack"
    panel.message = "Choose a folder containing at least one WAV audio file."
    return panel.runModal() == .OK ? panel.url?.path : nil
  }
}
