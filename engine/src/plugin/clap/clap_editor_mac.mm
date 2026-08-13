#include "plugin/clap/clap_plugin_instance.h"

#import <AppKit/AppKit.h>

namespace onebeat::plugin::clap {
namespace {
struct EditorContext { NSWindow* window = nil; };
}

bool ClapPluginInstance::showEditor() {
  if (gui_ == nullptr || plugin_ == nullptr || gui_->is_api_supported == nullptr ||
      !gui_->is_api_supported(plugin_, CLAP_WINDOW_API_COCOA, false)) return false;
  if (editor_context_ != nullptr) {
    [static_cast<EditorContext*>(editor_context_)->window makeKeyAndOrderFront:nil];
    return true;
  }
  if (gui_->create == nullptr || !gui_->create(plugin_, CLAP_WINDOW_API_COCOA, false)) return false;
  uint32_t width = 640;
  uint32_t height = 480;
  if (gui_->get_size != nullptr) gui_->get_size(plugin_, &width, &height);
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
  const CGFloat header = 48.0;
  const NSRect frame = NSMakeRect(0, 0, static_cast<CGFloat>(width),
                                  static_cast<CGFloat>(height) + header);
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                  backing:NSBackingStoreBuffered defer:NO];
  [window setTitle:[NSString stringWithUTF8String:name().text()]];
  [window setReleasedWhenClosed:NO];
  NSView* root = [[NSView alloc] initWithFrame:frame];
  [root setWantsLayer:YES];
  root.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.114 green:0.122 blue:0.110 alpha:1].CGColor;
  NSView* parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
  [root addSubview:parent];
  NSTextField* title = [NSTextField labelWithString:[NSString stringWithUTF8String:name().text()]];
  [title setTextColor:[NSColor colorWithCalibratedWhite:0.91 alpha:1]];
  [title setFont:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]];
  [title setFrame:NSMakeRect(16, height + 14, width / 2, 20)];
  [root addSubview:title];
  NSTextField* preset = [NSTextField labelWithString:@"BYPASS     Factory   Default"];
  [preset setTextColor:[NSColor colorWithCalibratedWhite:0.62 alpha:1]];
  [preset setAlignment:NSTextAlignmentRight];
  [preset setFrame:NSMakeRect(width / 2, height + 14, width / 2 - 16, 20)];
  [root addSubview:preset];
  [window setContentView:root];
  clap_window_t clap_window{};
  clap_window.api = CLAP_WINDOW_API_COCOA;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wold-style-cast"
  clap_window.cocoa = (__bridge void*)parent;
#pragma clang diagnostic pop
  if (gui_->set_parent == nullptr || !gui_->set_parent(plugin_, &clap_window)) {
    gui_->destroy(plugin_);
    [window close];
    return false;
  }
  if (gui_->can_resize == nullptr || !gui_->can_resize(plugin_))
    [window setStyleMask:[window styleMask] & ~NSWindowStyleMaskResizable];
  if (gui_->show != nullptr) gui_->show(plugin_);
  [window center];
  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  editor_context_ = new EditorContext{window};
  return true;
}

void ClapPluginInstance::hideEditor() {
  auto* context = static_cast<EditorContext*>(editor_context_);
  if (context == nullptr) return;
  if (gui_ != nullptr && plugin_ != nullptr) {
    if (gui_->hide != nullptr) gui_->hide(plugin_);
    if (gui_->destroy != nullptr) gui_->destroy(plugin_);
  }
  [context->window close];
  delete context;
  editor_context_ = nullptr;
}

void ClapPluginInstance::pumpEditorEvents() {
  if (editor_context_ == nullptr) return;
  for (;;) {
    NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                        untilDate:[NSDate date]
                                           inMode:NSDefaultRunLoopMode
                                          dequeue:YES];
    if (event == nil) break;
    [NSApp sendEvent:event];
  }
  [NSApp updateWindows];
}

}  // namespace onebeat::plugin::clap
