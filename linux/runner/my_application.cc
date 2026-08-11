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
  FlMethodChannel* tray_channel;
  AppIndicator* tray_indicator;
  GtkWidget* tray_menu;
  GtkWidget* tray_open_item;
  gboolean menu_connected;
  gboolean menu_connecting;
  gboolean menu_disconnecting;
  gboolean menu_has_subscription;
  gchar* menu_current_server;
  GPtrArray* menu_server_names;
  gint menu_selected_index;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void present_window(gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  gtk_window_present(window);
}

static void hide_window(gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  gtk_widget_hide(GTK_WIDGET(window));
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

static gchar* get_tray_icon_path() {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) return nullptr;
  g_autofree gchar* bin_dir = g_path_get_dirname(exe_path);
  return g_build_filename(bin_dir, "data", "flutter_assets", "assets",
                          "app_icon.png", nullptr);
}

static void send_to_dart(MyApplication* self, const gchar* method,
                         FlValue* args) {
  fl_method_channel_invoke_method(self->tray_channel, method, args, nullptr,
                                  nullptr, self);
}

static void tray_toggle_connection(G_GNUC_UNUSED GtkWidget* widget,
                                   gpointer user_data) {
  send_to_dart(MY_APPLICATION(user_data), "toggleConnection", nullptr);
}

static void tray_select_server(GtkWidget* widget, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  gint index =
      GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "server-index"));
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "index", fl_value_new_int(index));
  send_to_dart(self, "selectServer", args);
}

static void tray_refresh_subscription(G_GNUC_UNUSED GtkWidget* widget,
                                      gpointer user_data) {
  send_to_dart(MY_APPLICATION(user_data), "refreshSubscription", nullptr);
}

static void rebuild_tray_menu(MyApplication* self) {
  if (self->tray_menu == nullptr) {
    self->tray_menu = gtk_menu_new();
  }

  GList* children = gtk_container_get_children(GTK_CONTAINER(self->tray_menu));
  for (GList* l = children; l != nullptr; l = l->next) {
    gtk_widget_destroy(GTK_WIDGET(l->data));
  }
  g_list_free(children);

  self->tray_open_item = gtk_menu_item_new_with_label("Открыть");
  g_signal_connect_swapped(self->tray_open_item, "activate",
                           G_CALLBACK(present_window), self->window);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu),
                        self->tray_open_item);

  GtkWidget* hide_item = gtk_menu_item_new_with_label("Скрыть окно");
  g_signal_connect_swapped(hide_item, "activate", G_CALLBACK(hide_window),
                           self->window);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), hide_item);

  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu),
                        gtk_separator_menu_item_new());

  // Status line: connection state plus the active server.
  gchar* status_text = nullptr;
  if (self->menu_connected) {
    status_text = g_strdup_printf(
        "Подключено%s%s", self->menu_current_server != nullptr ? " · " : "",
        self->menu_current_server != nullptr ? self->menu_current_server : "");
  } else if (self->menu_connecting) {
    status_text = g_strdup("Подключение…");
  } else if (self->menu_disconnecting) {
    status_text = g_strdup("Отключение…");
  } else {
    status_text = g_strdup("Отключено");
  }
  GtkWidget* status_item = gtk_menu_item_new_with_label(status_text);
  gtk_widget_set_sensitive(status_item, FALSE);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), status_item);
  g_free(status_text);

  // Connect / disconnect toggle.
  const gchar* toggle_label = "Подключить";
  gboolean toggle_sensitive = TRUE;
  if (self->menu_connected) {
    toggle_label = "Отключить";
  } else if (self->menu_connecting || self->menu_disconnecting) {
    toggle_label = self->menu_connecting ? "Подключение…" : "Отключение…";
    toggle_sensitive = FALSE;
  } else if (!self->menu_has_subscription) {
    toggle_sensitive = FALSE;
  }
  GtkWidget* toggle_item = gtk_menu_item_new_with_label(toggle_label);
  gtk_widget_set_sensitive(toggle_item, toggle_sensitive);
  g_signal_connect(toggle_item, "activate",
                   G_CALLBACK(tray_toggle_connection), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), toggle_item);

  // Server selection submenu.
  GtkWidget* servers_item = gtk_menu_item_new_with_label("Выбор сервера");
  GtkWidget* servers_submenu = gtk_menu_new();
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(servers_item), servers_submenu);
  if (self->menu_server_names->len == 0) {
    GtkWidget* none_item = gtk_menu_item_new_with_label("Нет серверов");
    gtk_widget_set_sensitive(none_item, FALSE);
    gtk_menu_shell_append(GTK_MENU_SHELL(servers_submenu), none_item);
  } else {
    GSList* group = nullptr;
    for (guint i = 0; i < self->menu_server_names->len; i++) {
      const gchar* name =
          (const gchar*)g_ptr_array_index(self->menu_server_names, i);
      GtkWidget* item = gtk_radio_menu_item_new_with_label(group, name);
      group = gtk_radio_menu_item_get_group(GTK_RADIO_MENU_ITEM(item));
      if ((gint)i == self->menu_selected_index) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(item), TRUE);
      }
      g_object_set_data(G_OBJECT(item), "server-index", GINT_TO_POINTER(i));
      g_signal_connect(item, "activate", G_CALLBACK(tray_select_server), self);
      gtk_menu_shell_append(GTK_MENU_SHELL(servers_submenu), item);
    }
  }
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), servers_item);

  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu),
                        gtk_separator_menu_item_new());

  GtkWidget* refresh_item = gtk_menu_item_new_with_label("Обновить подписку");
  gtk_widget_set_sensitive(refresh_item, self->menu_has_subscription);
  g_signal_connect(refresh_item, "activate",
                   G_CALLBACK(tray_refresh_subscription), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), refresh_item);

  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu),
                        gtk_separator_menu_item_new());

  GtkWidget* quit_item = gtk_menu_item_new_with_label("Выход");
  g_signal_connect_swapped(quit_item, "activate", G_CALLBACK(quit_from_tray),
                           self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), quit_item);

  gtk_widget_show_all(self->tray_menu);

  if (self->tray_indicator != nullptr) {
    app_indicator_set_secondary_activate_target(self->tray_indicator,
                                                self->tray_open_item);
  }
}

static void apply_menu_state(MyApplication* self, FlValue* args) {
  FlValue* connected = fl_value_lookup_string(args, "connected");
  self->menu_connected =
      connected != nullptr ? fl_value_get_bool(connected) : FALSE;

  FlValue* connecting = fl_value_lookup_string(args, "connecting");
  self->menu_connecting =
      connecting != nullptr ? fl_value_get_bool(connecting) : FALSE;

  FlValue* disconnecting = fl_value_lookup_string(args, "disconnecting");
  self->menu_disconnecting =
      disconnecting != nullptr ? fl_value_get_bool(disconnecting) : FALSE;

  FlValue* has_subscription = fl_value_lookup_string(args, "hasSubscription");
  self->menu_has_subscription =
      has_subscription != nullptr ? fl_value_get_bool(has_subscription) : FALSE;

  FlValue* current_server = fl_value_lookup_string(args, "currentServer");
  g_free(self->menu_current_server);
  self->menu_current_server =
      current_server != nullptr && fl_value_get_type(current_server) ==
                                       FL_VALUE_TYPE_STRING
          ? g_strdup(fl_value_get_string(current_server))
          : nullptr;

  FlValue* selected = fl_value_lookup_string(args, "selected");
  self->menu_selected_index =
      selected != nullptr ? (gint)fl_value_get_int(selected) : 0;

  FlValue* servers = fl_value_lookup_string(args, "servers");
  g_ptr_array_set_size(self->menu_server_names, 0);
  if (servers != nullptr && fl_value_get_type(servers) == FL_VALUE_TYPE_LIST) {
    size_t count = fl_value_get_length(servers);
    for (size_t i = 0; i < count; i++) {
      FlValue* item = fl_value_get_list_value(servers, i);
      if (fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
        g_ptr_array_add(self->menu_server_names,
                        g_strdup(fl_value_get_string(item)));
      }
    }
  }
}

static void tray_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "updateMenu") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      apply_menu_state(self, args);
      rebuild_tray_menu(self);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send response: %s", error->message);
  }
}

static void setup_tray(MyApplication* self) {
  if (self->tray_indicator != nullptr) return;
  if (self->tray_menu == nullptr) {
    self->tray_menu = gtk_menu_new();
  }

  g_autofree gchar* icon_path = get_tray_icon_path();
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  self->tray_indicator =
      app_indicator_new(APPLICATION_ID, "affection-vpn",
                        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  G_GNUC_END_IGNORE_DEPRECATIONS
  if (icon_path != nullptr) {
    app_indicator_set_icon_full(self->tray_indicator, icon_path, "");
  }
  app_indicator_set_title(self->tray_indicator, "Affection VPN");
  app_indicator_set_menu(self->tray_indicator, GTK_MENU(self->tray_menu));
  app_indicator_set_status(self->tray_indicator, APP_INDICATOR_STATUS_ACTIVE);

  rebuild_tray_menu(self);
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

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
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(window));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  self->window = window;
  g_signal_connect(window, "delete-event",
                   G_CALLBACK(+[](GtkWidget* widget, GdkEvent* event,
                                  gpointer user_data) -> gboolean {
                     gtk_widget_hide_on_delete(widget);
                     return TRUE;
                   }),
                   nullptr);

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->shutdown_channel = fl_method_channel_new(
      messenger, "dev.affection.affection_vpn/shutdown",
      FL_METHOD_CODEC(codec));
  self->tray_channel = fl_method_channel_new(
      messenger, "dev.affection.affection_vpn/tray", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->tray_channel, tray_method_call_cb, self, nullptr);

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

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_startup(GApplication* application) {
  if (!g_getenv("GDK_BACKEND")) {
    g_setenv("GDK_BACKEND", "x11", FALSE);
  }

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->shutdown_channel);
  g_clear_object(&self->tray_channel);
  g_free(self->menu_current_server);
  self->menu_current_server = nullptr;
  g_clear_pointer(&self->menu_server_names, g_ptr_array_unref);
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
  self->tray_channel = nullptr;
  self->menu_connected = FALSE;
  self->menu_connecting = FALSE;
  self->menu_disconnecting = FALSE;
  self->menu_has_subscription = FALSE;
  self->menu_current_server = nullptr;
  self->menu_server_names = g_ptr_array_new_with_free_func(g_free);
  self->menu_selected_index = 0;
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
