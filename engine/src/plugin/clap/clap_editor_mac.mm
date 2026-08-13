#include "plugin/clap/clap_plugin_instance.h"

#import <AppKit/AppKit.h>

namespace onebeat::plugin::clap {
namespace {
struct EditorContext {
  NSWindow* window = nil;
  NSString* geometry_key = nil;
  id move_observer = nil;
  id resize_observer = nil;
};

void saveGeometry(EditorContext* context) {
  if (context == nullptr || context->window == nil || context->geometry_key == nil) return;
  [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(context->window.frame)
                                           forKey:context->geometry_key];
}

NSRect restoredFrame(NSString* key, NSRect fallback) {
  NSString* encoded = [[NSUserDefaults standardUserDefaults] stringForKey:key];
  if (encoded == nil) return fallback;
  NSRect restored = NSRectFromString(encoded);
  if (restored.size.width < 160 || restored.size.height < 120) return fallback;
  for (NSScreen* screen in [NSScreen screens]) {
    if (NSIntersectsRect(restored, screen.visibleFrame)) return restored;
  }
  // The saved display is gone. Keep the plug-in's size but move it onto the
  // current primary display so the editor never reopens off-screen.
  NSScreen* screen = [NSScreen mainScreen];
  if (screen == nil) return fallback;
  restored.origin.x = NSMidX(screen.visibleFrame) - restored.size.width / 2;
  restored.origin.y = NSMidY(screen.visibleFrame) - restored.size.height / 2;
  return restored;
}
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
  NSString* plugin_id = [NSString stringWithUTF8String:plugin_->desc->id];
  NSString* geometry_key = [@"onebeat.plugin-editor." stringByAppendingString:plugin_id];
  [window setFrame:restoredFrame(geometry_key, frame) display:NO];
  NSView* root = [[NSView alloc] initWithFrame:frame];
  [root setWantsLayer:YES];
  root.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.114 green:0.122 blue:0.110 alpha:1].CGColor;
  NSView* parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
  [parent setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [root addSubview:parent];
  NSTextField* title = [NSTextField labelWithString:[NSString stringWithUTF8String:name().text()]];
  [title setTextColor:[NSColor colorWithCalibratedWhite:0.91 alpha:1]];
  [title setFont:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]];
  [title setFrame:NSMakeRect(16, height + 14, width / 2, 20)];
  [title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [root addSubview:title];
  NSTextField* preset = [NSTextField labelWithString:@"BYPASS     Factory   Default"];
  [preset setTextColor:[NSColor colorWithCalibratedWhite:0.62 alpha:1]];
  [preset setAlignment:NSTextAlignmentRight];
  [preset setFrame:NSMakeRect(width / 2, height + 14, width / 2 - 16, 20)];
  [preset setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
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
  if ([[NSUserDefaults standardUserDefaults] stringForKey:geometry_key] == nil) [window center];
  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  auto* context = new EditorContext{window, geometry_key};
  NSNotificationCenter* notifications = [NSNotificationCenter defaultCenter];
  context->move_observer =
      [notifications addObserverForName:NSWindowDidMoveNotification
                                 object:window
                                  queue:nil
                             usingBlock:^(NSNotification*) { saveGeometry(context); }];
  context->resize_observer =
      [notifications addObserverForName:NSWindowDidResizeNotification
                                 object:window
                                  queue:nil
                             usingBlock:^(NSNotification*) { saveGeometry(context); }];
  editor_context_ = context;
  return true;
}

void ClapPluginInstance::hideEditor() {
  auto* context = static_cast<EditorContext*>(editor_context_);
  if (context == nullptr) return;
  if (gui_ != nullptr && plugin_ != nullptr) {
    if (gui_->hide != nullptr) gui_->hide(plugin_);
    if (gui_->destroy != nullptr) gui_->destroy(plugin_);
  }
  saveGeometry(context);
  NSNotificationCenter* notifications = [NSNotificationCenter defaultCenter];
  if (context->move_observer != nil) [notifications removeObserver:context->move_observer];
  if (context->resize_observer != nil) [notifications removeObserver:context->resize_observer];
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
