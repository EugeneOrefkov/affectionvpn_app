#include "my_application.h"

#include <libayatana-appindicator/app-indicator.h>
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* shutdown_channel;
  AppIndicator* tray_indicator;
  GtkWidget* tray_menu;
  GtkWidget* tray_open_item;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static gboolean on_window_delete(GtkWidget* widget, GdkEvent* event,
                                 gpointer user_data) {
  gtk_widget_hide_on_delete(widget);
  return TRUE;
}

static void present_window(gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  gtk_window_present(window);
}

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

static void setup_tray(MyApplication* self) {
  if (self->tray_indicator != nullptr) {
    return;
  }
  ensure_tray_menu(self);
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  self->tray_indicator =
      app_indicator_new(APPLICATION_ID, "affection-vpn",
                        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  G_GNUC_END_IGNORE_DEPRECATIONS
  app_indicator_set_title(self->tray_indicator, "Affection VPN");
  app_indicator_set_secondary_activate_target(self->tray_indicator,
                                              self->tray_open_item);
  app_indicator_set_menu(self->tray_indicator, GTK_MENU(self->tray_menu));
  app_indicator_set_status(self->tray_indicator, APP_INDICATOR_STATUS_ACTIVE);
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications. If running on X and not using GNOME then just use a
  // traditional title bar in case the window manager does more exotic layout.
  // If running on Wayland assume the header bar will work.
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Affection VPN");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Affection VPN");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  self->window = window;
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete), nullptr);

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  self->shutdown_channel = fl_method_channel_new(
      messenger, "dev.affection.affection_vpn/shutdown",
      FL_METHOD_CODEC(codec));

  gtk_widget_show(GTK_WIDGET(window));

  setup_tray(self);
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (!g_application_get_is_remote(application)) {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

static void my_application_startup(GApplication* application) {
  // Flutter's GTK embedder has known issues with Wayland input handling
  // (gdk_device_get_source assertion failures causing freezes on text input).
  // Force X11 via XWayland until Flutter resolves this upstream.
  if (!g_getenv("GDK_BACKEND")) {
    g_setenv("GDK_BACKEND", "x11", FALSE);
  }

  g_object_set(gtk_settings_get_default(),
               "gtk-application-prefer-dark-theme", TRUE, nullptr);

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
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
  self->shutdown_channel = nullptr;
  self->tray_indicator = nullptr;
  self->tray_menu = nullptr;
  self->tray_open_item = nullptr;
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
