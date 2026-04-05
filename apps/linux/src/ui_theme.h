#pragma once

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#else
typedef struct _GtkWidget GtkWidget;
typedef struct _GtkWindow GtkWindow;
#endif

namespace kelpie::linuxapp::ui {

constexpr const char* kFontAwesomeChrome = "\uf268";
constexpr const char* kFontAwesomeSafari = "\uf267";

void InstallTheme();

GtkWidget* CreateSymbolButton(const char* icon_name, const char* tooltip_text);
GtkWidget* CreateBrandBadge(const char* icon_text, const char* tooltip_text);
GtkWidget* CreateFabChild();
GtkWidget* CreateMenuRow(const char* icon_name, const char* label_text);
bool ApplyWindowIcon(GtkWindow* window);

}  // namespace kelpie::linuxapp::ui
