#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Attempt to connect to Wayland and register global shortcuts with the
// hyprland-global-shortcuts-v1 protocol.  Integrates with the GLib main loop
// so no extra threads are needed.
//
// app_id       – Wayland app_id passed to the protocol (matches the value the
//               user puts in hyprland.conf, e.g. "chat.tungstn.app.develop").
// dbus_service – Stable D-Bus well-known name the Dart side registered
//               (always "chat.tungstn.app" regardless of build flavour).
//
// Returns 1 if the Hyprland protocol global was found and shortcuts were
// registered, 0 if the protocol is unavailable (non-Hyprland compositor or
// no Wayland display).
int hyprland_shortcuts_init(const char* app_id, const char* dbus_service);

// Unregister all shortcuts and release resources.  Safe to call even if
// hyprland_shortcuts_init() returned 0.
void hyprland_shortcuts_cleanup(void);

#ifdef __cplusplus
}
#endif
