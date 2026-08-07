#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* window_channel;
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

// Handle window-control calls coming from the Flutter side ("dragWindow",
// "closeWindow"). Keeping all of this in native code means we do not pull in
// bitsdojo_window or any other package just to retitle the bar — we already
// have the GTK window handle.
static void window_method_call_handler(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "dragWindow") == 0) {
    // Begin a window move using GTK; the backend picks X11 vs Wayland
    // appropriately. GDK_CURRENT_TIME marks this as user-initiated so the
    // window manager does not refuse the drag.
    gtk_window_begin_move_drag(window, 1, 0, 0, GDK_CURRENT_TIME);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
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

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Drop both server- and client-side decorations so the bulky GTK title bar
  // disappears. The Flutter UI supplies its own branded top bar (drag handle
  // plus window buttons) which is a single pixel-perfect strip instead of the
  // default OS frame.
  gtk_window_set_decorated(window, FALSE);

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

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  self->window = window;
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete), nullptr);

  // Set up the MethodChannel bridge for the custom Flutter title bar.
  g_autoptr(FlEngine) engine = fl_view_get_engine(view);
  g_autoptr(FlBinaryMessenger) messenger =
      fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      messenger, "dev.affection.affection_vpn/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_handler, g_object_ref(window),
      g_object_unref);
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

  g_application_activate(application);
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
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
