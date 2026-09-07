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
  FlMethodChannel* desktop_window_channel;
  FlMethodChannel* notification_channel;
  FlMethodChannel* push_channel;
  GDBusProxy* notification_proxy;
  GHashTable* notification_routes;
  gboolean tray_ready;
  gboolean quit_on_close;
  gboolean start_hidden;
};

typedef struct {
  gchar* conversation_id;
  gchar* message_id;
} NotificationRoute;

typedef struct {
  MyApplication* application;
  NotificationRoute* route;
} PendingNotification;

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void notification_route_free(gpointer data) {
  NotificationRoute* route = static_cast<NotificationRoute*>(data);
  g_free(route->conversation_id);
  g_free(route->message_id);
  g_free(route);
}

static FlValue* notification_route_value(const NotificationRoute* route) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(
      value, "conversation_id",
      fl_value_new_string(route->conversation_id));
  fl_value_set_string_take(value, "message_id",
                           fl_value_new_string(route->message_id));
  return value;
}

static void open_notification_route(MyApplication* self,
                                    const NotificationRoute* route) {
  gtk_widget_show(GTK_WIDGET(self->window));
  gtk_window_deiconify(self->window);
  gtk_window_present(self->window);
  g_autoptr(FlValue) value = notification_route_value(route);
  fl_method_channel_invoke_method(self->push_channel, "routeOpened", value,
                                  nullptr, nullptr, nullptr);
}

static void notification_signal_cb(GDBusProxy* proxy,
                                   gchar* sender_name,
                                   gchar* signal_name,
                                   GVariant* parameters,
                                   gpointer user_data) {
  (void)proxy;
  (void)sender_name;
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_strcmp0(signal_name, "ActionInvoked") == 0) {
    guint32 notification_id = 0;
    const gchar* action = nullptr;
    g_variant_get(parameters, "(u&s)", &notification_id, &action);
    if (g_strcmp0(action, "default") == 0) {
      NotificationRoute* route = static_cast<NotificationRoute*>(
          g_hash_table_lookup(self->notification_routes,
                              GUINT_TO_POINTER(notification_id)));
      if (route != nullptr) {
        open_notification_route(self, route);
      }
    }
    g_hash_table_remove(self->notification_routes,
                        GUINT_TO_POINTER(notification_id));
  } else if (g_strcmp0(signal_name, "NotificationClosed") == 0) {
    guint32 notification_id = 0;
    guint32 reason = 0;
    g_variant_get(parameters, "(uu)", &notification_id, &reason);
    (void)reason;
    g_hash_table_remove(self->notification_routes,
                        GUINT_TO_POINTER(notification_id));
  }
}

static void notification_sent_cb(GObject* object,
                                 GAsyncResult* result,
                                 gpointer user_data) {
  PendingNotification* pending = static_cast<PendingNotification*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) response =
      g_dbus_proxy_call_finish(G_DBUS_PROXY(object), result, &error);
  if (response != nullptr) {
    guint32 notification_id = 0;
    g_variant_get(response, "(u)", &notification_id);
    g_hash_table_replace(pending->application->notification_routes,
                         GUINT_TO_POINTER(notification_id), pending->route);
    pending->route = nullptr;
  }
  if (pending->route != nullptr) {
    notification_route_free(pending->route);
  }
  g_object_unref(pending->application);
  g_free(pending);
}

static void show_notification(MyApplication* self,
                              const gchar* conversation_id,
                              const gchar* message_id,
                              const gchar* title,
                              const gchar* body) {
  GVariantBuilder actions;
  g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
  g_variant_builder_add(&actions, "s", "default");
  g_variant_builder_add(&actions, "s", "打开");
  GVariantBuilder hints;
  g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&hints, "{sv}", "suppress-sound",
                        g_variant_new_boolean(TRUE));
  g_autofree gchar* escaped_body = g_markup_escape_text(body, -1);
  PendingNotification* pending = g_new0(PendingNotification, 1);
  pending->application = MY_APPLICATION(g_object_ref(self));
  pending->route = g_new0(NotificationRoute, 1);
  pending->route->conversation_id = g_strdup(conversation_id);
  pending->route->message_id = g_strdup(message_id);
  g_dbus_proxy_call(
      self->notification_proxy, "Notify",
      g_variant_new("(susssasa{sv}i)", "MagicChat", 0, "", title,
                    escaped_body, &actions, &hints, -1),
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, notification_sent_cb, pending);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (!self->start_hidden) {
    gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  }
}

static gboolean window_delete_cb(GtkWidget* widget, GdkEvent* event,
                                 gpointer user_data) {
  (void)event;
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->quit_on_close) {
    g_application_quit(G_APPLICATION(self));
    return TRUE;
  }
  // 托盘可用时隐藏窗口；不可用时保留任务栏入口，避免窗口无法恢复。
  if (self->tray_ready) {
    gtk_widget_hide(widget);
  } else {
    gtk_window_iconify(GTK_WINDOW(widget));
  }
  return TRUE;
}

static void desktop_window_method_call_cb(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "show") == 0) {
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_deiconify(self->window);
    gtk_window_present(self->window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setTitle") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_STRING) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_args", "setTitle expects a string", nullptr));
    } else {
      const gchar* title = fl_value_get_string(args);
      gtk_window_set_title(self->window, title);
      GtkWidget* title_bar = gtk_window_get_titlebar(self->window);
      if (GTK_IS_HEADER_BAR(title_bar)) {
        gtk_header_bar_set_title(GTK_HEADER_BAR(title_bar), title);
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "setTrayReady") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    self->tray_ready = args != nullptr &&
                       fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                       fl_value_get_bool(args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setCloseBehavior") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    self->quit_on_close =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING &&
        strcmp(fl_value_get_string(args), "quit") == 0;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "quit") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
  if (strcmp(method, "quit") == 0) {
    g_application_quit(G_APPLICATION(self));
  }
}

static void notification_method_call_cb(FlMethodChannel* channel,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "getPermissionStatus") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string(self->notification_proxy == nullptr
                                ? "unsupported"
                                : "granted")));
  } else if (strcmp(method, "requestPermission") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(self->notification_proxy != nullptr)));
  } else if (strcmp(method, "showMessage") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* conversation = args == nullptr
                                ? nullptr
                                : fl_value_lookup_string(args, "conversation_id");
    FlValue* message =
        args == nullptr ? nullptr : fl_value_lookup_string(args, "message_id");
    FlValue* title =
        args == nullptr ? nullptr : fl_value_lookup_string(args, "title");
    FlValue* body =
        args == nullptr ? nullptr : fl_value_lookup_string(args, "body");
    if (self->notification_proxy == nullptr || conversation == nullptr ||
        fl_value_get_type(conversation) != FL_VALUE_TYPE_STRING ||
        strlen(fl_value_get_string(conversation)) == 0 || title == nullptr ||
        fl_value_get_type(title) != FL_VALUE_TYPE_STRING || body == nullptr ||
        fl_value_get_type(body) != FL_VALUE_TYPE_STRING) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "notification", "Unable to show notification", nullptr));
    } else {
      const gchar* message_id =
          message != nullptr && fl_value_get_type(message) == FL_VALUE_TYPE_STRING
              ? fl_value_get_string(message)
              : "";
      show_notification(self, fl_value_get_string(conversation), message_id,
                        fl_value_get_string(title), fl_value_get_string(body));
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void push_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "getPendingRoute") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
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
    gtk_header_bar_set_title(header_bar, "MagicChat");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "MagicChat");
  }

  gtk_window_set_default_size(window, 1280, 720);
  g_signal_connect(window, "delete-event", G_CALLBACK(window_delete_cb),
                   self);
  // Bundled SVG supplies a stable taskbar/dock icon for Linux distributions
  // that do not install an icon theme entry for the application ID.
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* runner_dir = g_path_get_dirname(executable);
    g_autofree gchar* icon_path =
        g_build_filename(runner_dir, "data", "magicchat.svg", nullptr);
    gtk_window_set_icon_from_file(window, icon_path, nullptr);
  }

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

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->desktop_window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "magicchat/desktop_window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->desktop_window_channel,
                                            desktop_window_method_call_cb, self,
                                            nullptr);
  self->notification_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "magicchat/notifications", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->notification_channel,
                                            notification_method_call_cb, self,
                                            nullptr);
  self->push_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "magicchat/push", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->push_channel,
                                            push_method_call_cb, self, nullptr);

  self->notification_proxy = g_dbus_proxy_new_for_bus_sync(
      G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_NONE, nullptr,
      "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", nullptr, nullptr);
  if (self->notification_proxy != nullptr) {
    g_signal_connect(self->notification_proxy, "g-signal",
                     G_CALLBACK(notification_signal_cb), self);
  }

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->start_hidden = FALSE;
  for (gchar** argument = *arguments + 1; *argument != nullptr; argument++) {
    if (g_strcmp0(*argument, "--hidden") == 0) {
      self->start_hidden = TRUE;
      break;
    }
  }
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
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

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
  g_clear_object(&self->desktop_window_channel);
  g_clear_object(&self->notification_channel);
  g_clear_object(&self->push_channel);
  g_clear_object(&self->notification_proxy);
  g_clear_pointer(&self->notification_routes, g_hash_table_unref);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
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
  self->notification_routes =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr,
                            notification_route_free);
  self->tray_ready = FALSE;
  self->quit_on_close = FALSE;
  self->start_hidden = FALSE;
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
