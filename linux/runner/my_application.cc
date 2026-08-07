#include "my_application.h"

#include <libayatana-appindicator/app-indicator.h>
#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* window_channel;
  FlMethodChannel* shutdown_channel;
  AppIndicator* tray_indicator;
  GtkWidget* tray_menu;
  GtkWidget* tray_open_item;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Hide instead of destroying so the app stays in the system tray.
static gboolean on_window_delete(GtkWidget* widget, GdkEvent* event,
                                 gpointer user_data) {
  gtk_widget_hide_on_delete(widget);
  return TRUE;
}

// Bring the (possibly hidden) window back to the foreground.
static void present_window(gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  gtk_window_present(window);
}

// Tray "Выход": let Dart tear the tunnel down first, then quit the process.
static void on_vpn_stopped_before_quit(GObject* source_object,
                                       GAsyncResult* result,
                                       gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response =
      fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(source_object),
                                             result, &error);
  if (error != nullptr) {
    g_warning("Failed to stop VPN before quit: %s", error->message);
  }
  g_application_quit(G_APPLICATION(self));
}

static void quit_from_tray(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  fl_method_channel_invoke_method(self->shutdown_channel, "quit", nullptr,
                                  nullptr, on_vpn_stopped_before_quit, self);
}

static void ensure_tray_menu(MyApplication* self) {
  if (self->tray_menu != nullptr) {
    return;
  }
  self->tray_menu = gtk_menu_new();

  self->tray_open_item = gtk_menu_item_new_with_label("Открыть");
  g_signal_connect_swapped(self->tray_open_item, "activate",
                           G_CALLBACK(present_window), self->window);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu),
                        self->tray_open_item);

  GtkWidget* quit_item = gtk_menu_item_new_with_label("Выход");
  g_signal_connect_swapped(quit_item, "activate", G_CALLBACK(quit_from_tray),
                           self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), quit_item);
}

// Creates the tray icon once. It lives for the whole process, so the user can
// reopen the window (or quit) after the window has been hidden to the tray.
// Uses the StatusNotifierItem protocol via libayatana-appindicator, which
// modern desktops (KDE Plasma, GNOME with the AppIndicator extension) render
// natively — the deprecated GtkStatusIcon/XEmbed path no longer shows on them.
static void setup_tray(MyApplication* self) {
  if (self->tray_indicator != nullptr) {
    return;
  }
  ensure_tray_menu(self);
  // app_indicator_new is the last remaining ABI-stable constructor; the whole
  // ayatana-appindicator3 API is deprecated upstream, so silence the warning
  // that -Wall -Werror would otherwise promote to an error.
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  self->tray_indicator =
      app_indicator_new(APPLICATION_ID, "affection-vpn",
                        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  G_GNUC_END_IGNORE_DEPRECATIONS
  app_indicator_set_title(self->tray_indicator, "Affection VPN");
  // Bind the primary (left-click / "activate") action to the "Открыть" menu
  // item so the tray icon restores the hidden window on a single click.
  app_indicator_set_secondary_activate_target(self->tray_indicator,
                                              self->tray_open_item);
  app_indicator_set_menu(self->tray_indicator, GTK_MENU(self->tray_menu));
  app_indicator_set_status(self->tray_indicator, APP_INDICATOR_STATUS_ACTIVE);
}

// Handle window-control calls coming from the Flutter side ("minimizeWindow",
// "closeWindow"). Window drag is handled by the native event callback
// (on_view_event) which fires inside GDK event processing and preserves
// the correct event serial on Wayland.
static void window_method_call_handler(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "minimizeWindow") == 0) {
    gtk_window_iconify(window);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "closeWindow") == 0) {
    gtk_widget_hide(GTK_WIDGET(window));
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  fl_method_call_respond_not_implemented(method_call, nullptr);
}

// GtkWindow::event handler. Fires before the event propagates to the
// child FlView, so Flutter never sees title-bar clicks (they are consumed
// with TRUE). On Wayland the button-press serial is still the press serial
// at this stage, so xdg_toplevel_move accepts it every time.
static gboolean on_window_event(GtkWidget* widget, GdkEvent* event,
                                gpointer user_data) {
  if (event->type == GDK_BUTTON_PRESS) {
    GdkEventButton* bev = (GdkEventButton*)event;
    if (bev->y >= 0 && bev->y <= 36) {
      GtkWindow* win = GTK_WINDOW(user_data);
      gint w = gtk_widget_get_allocated_width(widget);
      if (bev->x < w - 80) {
        gtk_window_begin_move_drag(win, bev->button, bev->x_root, bev->y_root,
                                   bev->time);
        return TRUE;
      }
    }
  }
  return FALSE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Hide the OS title bar so only the Flutter custom bar is visible. On X11
  // gtk_window_set_decorated(FALSE) drops the WM decorations while keeping
  // resize borders. On Wayland it is ignored by KWin, so the same effect is
  // achieved by forcing GTK3 into CSD mode with a zero-height hidden header
  // bar — the compositor then skips its own title bar, and window resizing
  // still works via KWin's invisible edge handles.
  GdkDisplay* display = gdk_display_get_default();
  const gchar* gdk_backend = gdk_display_get_name(display);
  if (!g_str_has_prefix(gdk_backend, "wayland")) {
    gtk_window_set_decorated(window, FALSE);
  } else {
    GtkWidget* header_bar = gtk_header_bar_new();
    gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header_bar), FALSE);
    gtk_widget_set_visible(header_bar, FALSE);
    gtk_widget_set_no_show_all(header_bar, TRUE);
    gtk_widget_set_size_request(header_bar, -1, 0);

    GtkCssProvider* css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(
        css,
        "headerbar { min-height: 0px; padding: 0; margin: 0; "
        "border: none; background: transparent; }",
        -1, nullptr);
    GtkStyleContext* ctx = gtk_widget_get_style_context(header_bar);
    gtk_style_context_add_provider(ctx, GTK_STYLE_PROVIDER(css),
                                   GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(css);

    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  // GtkWindow::event fires before events reach child FlView, so Flutter
  // never sees title-bar clicks that we consume with TRUE. Both the serial
  // (Wayland) and the event coordinates are correct at this stage.
  g_signal_connect(window, "event", G_CALLBACK(on_window_event), window);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  self->window = window;
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete), nullptr);

  // Set up the MethodChannel bridge for the custom Flutter title bar. The
  // engine and its messenger are owned by the view — borrow them only. Using
  // g_autoptr here would g_object_unref them at the end of activate(), which
  // disposes the engine and stops Flutter from ever presenting its first
  // frame (the window stays hidden).
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      messenger, "dev.affection.affection_vpn/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_handler, g_object_ref(window),
      g_object_unref);

  // Native -> Dart channel so the tray's "Выход" can stop the tunnel before
  // the process exits (avoids orphaning the xray core and its system proxy).
  self->shutdown_channel = fl_method_channel_new(
      messenger, "dev.affection.affection_vpn/shutdown",
      FL_METHOD_CODEC(codec));

  setup_tray(self);
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // Single-instance app: a second launch is handed to the primary instance
  // (its "activate" handler presents the hidden window), so only the primary
  // creates its own window here.
  if (!g_application_get_is_remote(application)) {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // Keep the dark preference so any GTK dialogs (file picker, etc.) match
  // the in-app dark palette.
  g_object_set(gtk_settings_get_default(),
               "gtk-application-prefer-dark-theme", TRUE, nullptr);

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
  g_clear_object(&self->shutdown_channel);
  g_clear_object(&self->tray_indicator);
  g_clear_object(&self->tray_menu);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window_channel = nullptr;
  self->shutdown_channel = nullptr;
  self->tray_indicator = nullptr;
  self->tray_menu = nullptr;
  self->tray_open_item = nullptr;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
