#include "gui_shell.h"
#include "browser_chrome.h"
#include "bookmarks_view.h"
#include "gtk_browser_view.h"
#include "history_view.h"
#include "linux_app.h"
#include "network_inspector.h"
#include "settings_view.h"
#include "toast_view.h"
#include "ui_theme.h"
#include "url_bar.h"
#include "window_geometry.h"
#if KELPIE_LINUX_HAS_GTK
#include <gdk/gdkkeysyms.h>
#include <gtk/gtk.h>
#endif
namespace kelpie::linuxapp {
GUIShell::GUIShell(LinuxApp& app):app_(app) {}
int GUIShell::Run() {
#if KELPIE_LINUX_HAS_GTK
  gtk_disable_setlocale(); gtk_init(nullptr,nullptr); ui::InstallTheme();
  auto* window=GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  gtk_window_set_title(window,"Kelpie"); gtk_window_set_default_size(window,app_.config().width,app_.config().height);
  WindowGeometry geometry(window,app_.config().profile_dir);
  auto* header=gtk_box_new(GTK_ORIENTATION_VERTICAL,0);
  gtk_window_set_titlebar(window,header); // Client-side decoration keeps native resize handles.
  gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(window)),"kelpie-window");
  ui::ApplyWindowIcon(window);
  UrlBar url(app_); GtkBrowserView browser(app_); BrowserChrome chrome(app_,window);
  BookmarksView bookmarks(app_); HistoryView history(app_); NetworkInspector network(app_); SettingsView settings(app_); ToastView toast;
  gtk_box_pack_start(GTK_BOX(header),chrome.title(),TRUE,TRUE,0);
  auto* content=gtk_box_new(GTK_ORIENTATION_VERTICAL,0); gtk_container_add(GTK_CONTAINER(window),content);
  gtk_box_pack_start(GTK_BOX(content),url.widget(),FALSE,FALSE,0);
  gtk_box_pack_start(GTK_BOX(content),chrome.favorites(),FALSE,FALSE,0);
  gtk_box_pack_start(GTK_BOX(content),chrome.separator(),FALSE,FALSE,0);
  auto* overlay=gtk_overlay_new(); gtk_container_add(GTK_CONTAINER(overlay),browser.widget());
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay),toast.widget()); gtk_box_pack_start(GTK_BOX(content),overlay,TRUE,TRUE,0);
  auto dialog=[&](const char* name,GtkWidget* contents) {
    auto* value=gtk_dialog_new_with_buttons(name,window,GTK_DIALOG_DESTROY_WITH_PARENT,"Close",GTK_RESPONSE_CLOSE,nullptr);
    gtk_window_set_default_size(GTK_WINDOW(value),720,520);
    gtk_container_add(GTK_CONTAINER(gtk_dialog_get_content_area(GTK_DIALOG(value))),contents);
    g_signal_connect_swapped(value,"response",G_CALLBACK(gtk_widget_hide),value); return value;
  };
  auto* bookmark_dialog=dialog("Bookmarks",bookmarks.widget()); auto* history_dialog=dialog("History",history.widget());
  auto* network_dialog=dialog("Network inspector",network.widget());
  url.tool_action=[&](int action) {
    if(action==0) { bookmarks.Refresh(); gtk_widget_show_all(bookmark_dialog); }
    if(action==1) { network.Refresh(); gtk_widget_show_all(network_dialog); }
    if(action==2) { history.Refresh(); gtk_widget_show_all(history_dialog); }
    if(action==3)chrome.AccountMenu(url.widget());
    if(action==4) { settings.Refresh(); settings.Show(window); }
  };
  struct Context { LinuxApp& app; GtkWindow* window; UrlBar& url; GtkBrowserView& browser; BrowserChrome& chrome; ToastView& toast; unsigned tick=0; } context{app_,window,url,browser,chrome,toast};
  g_signal_connect(window,"delete-event",G_CALLBACK(+[](GtkWidget*,GdkEvent*,gpointer raw)->gboolean {
    static_cast<LinuxApp*>(raw)->RequestShutdown(); return TRUE; // Keep renderer and pump alive until drained.
  }),&app_);
  g_signal_connect(window,"key-press-event",G_CALLBACK(+[](GtkWidget*,GdkEventKey* e,gpointer raw)->gboolean {
    auto& c=*static_cast<Context*>(raw); const bool control=e->state&GDK_CONTROL_MASK; const bool shift=e->state&GDK_SHIFT_MASK;
    const auto key=gdk_keyval_to_lower(e->keyval);
    if(control&&key==GDK_KEY_l) { c.url.Focus(); return TRUE; }
    if(control&&key==GDK_KEY_t) { c.app.NewTab(); return TRUE; }
    if(control&&shift&&key==GDK_KEY_n) { c.app.NewTab(true); return TRUE; }
    if(control&&key==GDK_KEY_w) { for(auto& t:c.app.Tabs())if(t.active)c.app.CloseTab(t.id); return TRUE; }
    if(control&&(key==GDK_KEY_Tab||key==GDK_KEY_ISO_Left_Tab)) { c.app.CycleTab(shift?-1:1); return TRUE; }
    if((control&&key==GDK_KEY_r)||key==GDK_KEY_F5) { c.app.Reload(); return TRUE; }
    if(key==GDK_KEY_F11) { c.app.SetFullscreen(!c.app.IsFullscreen()); return TRUE; }
    return FALSE;
  }),&context);
  g_signal_connect(window,"window-state-event",G_CALLBACK(+[](GtkWidget*,GdkEventWindowState* event,gpointer raw)->gboolean {
    static_cast<LinuxApp*>(raw)->ReportFullscreenState(event->new_window_state&GDK_WINDOW_STATE_FULLSCREEN); return FALSE;
  }),&app_);
  const auto timer=g_timeout_add(16,+[](gpointer raw)->gboolean {
    auto& c=*static_cast<Context*>(raw); c.app.PumpBrowser();
    if(!c.app.IsRunning()) { if(c.app.FinishShutdown())gtk_main_quit(); return G_SOURCE_CONTINUE; }
    if(c.app.WantsFullscreen()!=c.app.IsFullscreen()) { if(c.app.WantsFullscreen())gtk_window_fullscreen(c.window); else gtk_window_unfullscreen(c.window); }
    auto [width,height]=c.app.TakeResizeRequest();
    if(width>0&&height>0) { int w,h; gtk_window_get_size(c.window,&w,&h); auto view=c.app.ViewFrame(); gtk_window_resize(c.window,w+width-view.width,h+height-view.height); }
    c.browser.Sync(); c.chrome.Sync();
    if(++c.tick%15==0) { c.url.Sync(); const auto title=c.app.CurrentTitle(); gtk_window_set_title(c.window,(title.empty()?"Kelpie":title+" — Kelpie").c_str()); }
    auto message=c.app.ConsumeToast(); if(!message.empty())c.toast.Show(message);
    return G_SOURCE_CONTINUE;
  },&context);
  gtk_widget_show_all(GTK_WIDGET(window)); chrome.Sync(); gtk_main();
  g_source_remove(timer); geometry.Save(); gtk_widget_destroy(GTK_WIDGET(window)); return 0;
#else
  return 1;
#endif
}
}  // namespace kelpie::linuxapp
