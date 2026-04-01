#include "ui_theme.h"

#include <filesystem>

#if MOLLOTOV_LINUX_HAS_GTK
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gtk/gtk.h>
#if MOLLOTOV_LINUX_HAS_FONTCONFIG
#include <fontconfig/fontconfig.h>
#endif
#endif

namespace mollotov::linuxapp::ui {

namespace {

constexpr const char* kCss = R"CSS(
.mollotov-window {
  background: #f6f2ed;
}

.mollotov-toolbar {
  background: rgba(255, 255, 255, 0.92);
  border-bottom: 1px solid rgba(83, 68, 53, 0.10);
  padding: 10px 14px;
}

.mollotov-nav-button {
  background: #ebe6df;
  border-radius: 10px;
  border: 1px solid rgba(83, 68, 53, 0.08);
  color: #443327;
  min-width: 36px;
  min-height: 36px;
  padding: 0;
}

.mollotov-nav-button:hover {
  background: #e3ddd6;
}

.mollotov-nav-button:disabled {
  color: rgba(68, 51, 39, 0.35);
}

.mollotov-url-shell {
  background: rgba(255, 255, 255, 0.96);
  border-radius: 16px;
  border: 1px solid rgba(83, 68, 53, 0.10);
  padding: 6px 10px;
}

.mollotov-brand-pill {
  background: #efe9e2;
  border-radius: 10px;
  color: #5b4a3d;
  min-width: 28px;
  min-height: 28px;
}

.mollotov-brand-icon {
  color: #5b4a3d;
}

.mollotov-url-entry,
.mollotov-url-entry entry {
  background: transparent;
  border: none;
  box-shadow: none;
  color: #2f241b;
  font-size: 14px;
}

.mollotov-fab {
  background: #f4b078;
  border-radius: 999px;
  border: none;
  color: #ffffff;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
}

.mollotov-fab:hover {
  background: #f1a96d;
}

.mollotov-fab-label {
  color: #ffffff;
  font-size: 20px;
}

.mollotov-menu-popover {
  background: rgba(255, 255, 255, 0.95);
  border-radius: 18px;
  padding: 8px;
}

.mollotov-menu-row {
  background: transparent;
  border: none;
  border-radius: 14px;
  padding: 6px 8px;
}

.mollotov-menu-row:hover {
  background: rgba(240, 148, 90, 0.10);
}

.mollotov-menu-chip {
  background: #f0945a;
  border-radius: 999px;
  color: #ffffff;
  min-width: 38px;
  min-height: 38px;
  padding: 0;
}

.mollotov-menu-label {
  color: #403126;
  font-weight: 600;
}
 )CSS";

#if MOLLOTOV_LINUX_HAS_GTK
void AddCssClass(GtkWidget* widget, const char* class_name) {
  gtk_style_context_add_class(gtk_widget_get_style_context(widget), class_name);
}

std::filesystem::path CurrentExecutableDir() {
  std::error_code error;
  const std::filesystem::path executable = std::filesystem::read_symlink("/proc/self/exe", error);
  return error ? std::filesystem::path() : executable.parent_path();
}

std::filesystem::path AppIconPath() {
  return CurrentExecutableDir() / "icon-1024.png";
}

GdkPixbuf* LoadScaledPixbuf(const std::filesystem::path& path, int size) {
  if (path.empty() || !std::filesystem::exists(path)) {
    return nullptr;
  }
  return gdk_pixbuf_new_from_file_at_scale(path.string().c_str(), size, size, TRUE, nullptr);
}

void RegisterFontAwesomeBrands() {
#if MOLLOTOV_LINUX_HAS_FONTCONFIG
  static bool registered = false;
  if (registered) {
    return;
  }
  registered = true;
  const std::filesystem::path font_path = CurrentExecutableDir() / "FontAwesome6Brands-Regular.otf";
  if (font_path.empty() || !std::filesystem::exists(font_path)) {
    return;
  }
  FcConfigAppFontAddFile(nullptr,
                         reinterpret_cast<const FcChar8*>(font_path.string().c_str()));
#endif
}
#endif

}  // namespace

void InstallTheme() {
#if MOLLOTOV_LINUX_HAS_GTK
  static bool installed = false;
  if (installed) {
    return;
  }
  installed = true;
  RegisterFontAwesomeBrands();
  auto* provider = gtk_css_provider_new();
  gtk_css_provider_load_from_data(provider, kCss, -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      gdk_screen_get_default(),
      GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(provider);
#endif
}

GtkWidget* CreateSymbolButton(const char* icon_name, const char* tooltip_text) {
#if MOLLOTOV_LINUX_HAS_GTK
  auto* button = gtk_button_new();
  auto* image = gtk_image_new_from_icon_name(icon_name, GTK_ICON_SIZE_BUTTON);
  gtk_button_set_image(GTK_BUTTON(button), image);
  gtk_widget_set_tooltip_text(button, tooltip_text);
  AddCssClass(button, "mollotov-nav-button");
  return button;
#else
  (void)icon_name;
  (void)tooltip_text;
  return nullptr;
#endif
}

GtkWidget* CreateBrandBadge(const char* icon_text, const char* tooltip_text) {
#if MOLLOTOV_LINUX_HAS_GTK
  auto* frame = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  auto* label = gtk_label_new(icon_text);
  gtk_widget_set_tooltip_text(frame, tooltip_text);
  gtk_label_set_xalign(GTK_LABEL(label), 0.5f);
  gtk_widget_set_halign(label, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(label, GTK_ALIGN_CENTER);
  AddCssClass(frame, "mollotov-brand-pill");
  AddCssClass(label, "mollotov-brand-icon");
  PangoAttrList* attrs = pango_attr_list_new();
  pango_attr_list_insert(attrs, pango_attr_family_new("Font Awesome 6 Brands"));
  pango_attr_list_insert(attrs, pango_attr_size_new_absolute(14 * PANGO_SCALE));
  gtk_label_set_attributes(GTK_LABEL(label), attrs);
  pango_attr_list_unref(attrs);
  gtk_box_pack_start(GTK_BOX(frame), label, FALSE, FALSE, 8);
  return frame;
#else
  (void)icon_text;
  (void)tooltip_text;
  return nullptr;
#endif
}

GtkWidget* CreateFabChild() {
#if MOLLOTOV_LINUX_HAS_GTK
  auto* drawing = gtk_drawing_area_new();
  gtk_widget_set_size_request(drawing, 24, 24);
  g_signal_connect(
      drawing,
      "draw",
      G_CALLBACK(+[](GtkWidget* widget, cairo_t* cr, gpointer) -> gboolean {
        GtkAllocation allocation{};
        gtk_widget_get_allocation(widget, &allocation);
        const double width = static_cast<double>(allocation.width);
        const double height = static_cast<double>(allocation.height);
        const double scale = std::min(width, height) / 24.0;

        cairo_scale(cr, scale, scale);
        cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);

        // Simple filled flame silhouette to mirror the Apple flame FAB.
        cairo_move_to(cr, 12.0, 2.0);
        cairo_curve_to(cr, 15.0, 5.0, 16.8, 7.5, 16.5, 10.5);
        cairo_curve_to(cr, 16.3, 12.3, 15.0, 13.9, 13.8, 14.9);
        cairo_curve_to(cr, 16.3, 14.5, 18.3, 12.4, 18.6, 9.5);
        cairo_curve_to(cr, 19.0, 5.9, 16.8, 2.8, 13.2, 1.0);
        cairo_curve_to(cr, 13.0, 3.4, 11.8, 5.0, 10.3, 6.6);
        cairo_curve_to(cr, 8.1, 8.9, 6.0, 11.1, 6.0, 14.2);
        cairo_curve_to(cr, 6.0, 18.9, 9.4, 22.0, 12.0, 22.0);
        cairo_curve_to(cr, 15.8, 22.0, 18.9, 18.8, 18.9, 14.8);
        cairo_curve_to(cr, 18.9, 12.0, 17.6, 9.8, 15.7, 8.2);
        cairo_curve_to(cr, 15.9, 10.1, 15.0, 11.8, 13.5, 12.9);
        cairo_curve_to(cr, 12.8, 10.8, 11.2, 9.2, 9.6, 8.0);
        cairo_curve_to(cr, 9.3, 10.0, 7.8, 11.9, 7.8, 14.3);
        cairo_curve_to(cr, 7.8, 17.6, 10.0, 20.0, 12.0, 20.0);
        cairo_curve_to(cr, 14.4, 20.0, 16.6, 17.8, 16.6, 14.9);
        cairo_curve_to(cr, 16.6, 13.1, 15.9, 11.7, 14.6, 10.4);
        cairo_curve_to(cr, 14.0, 12.1, 12.7, 13.2, 11.3, 13.9);
        cairo_curve_to(cr, 11.0, 11.4, 11.5, 9.1, 12.8, 6.8);
        cairo_curve_to(cr, 13.7, 5.2, 13.8, 3.8, 12.0, 2.0);
        cairo_close_path(cr);
        cairo_fill(cr);
        return TRUE;
      }),
      nullptr);
  return drawing;
#else
  return nullptr;
#endif
}

GtkWidget* CreateMenuRow(const char* icon_name, const char* label_text) {
#if MOLLOTOV_LINUX_HAS_GTK
  auto* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
  auto* chip = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  auto* icon = gtk_image_new_from_icon_name(icon_name, GTK_ICON_SIZE_BUTTON);
  auto* label = gtk_label_new(label_text);

  gtk_widget_set_halign(label, GTK_ALIGN_START);
  gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
  gtk_box_pack_start(GTK_BOX(chip), icon, FALSE, FALSE, 11);
  gtk_box_pack_start(GTK_BOX(row), chip, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(row), label, TRUE, TRUE, 0);

  AddCssClass(chip, "mollotov-menu-chip");
  AddCssClass(label, "mollotov-menu-label");
  return row;
#else
  (void)icon_name;
  (void)label_text;
  return nullptr;
#endif
}

bool ApplyWindowIcon(GtkWindow* window) {
#if MOLLOTOV_LINUX_HAS_GTK
  if (window == nullptr) {
    return false;
  }
  const std::filesystem::path icon_path = AppIconPath();
  if (icon_path.empty() || !std::filesystem::exists(icon_path)) {
    return false;
  }
  gtk_window_set_icon_from_file(window, icon_path.string().c_str(), nullptr);
  return true;
#else
  (void)window;
  return false;
#endif
}

}  // namespace mollotov::linuxapp::ui
