#include "url_bar.h"

#include <string_view>
#include "linux_app.h"
#include "ui_theme.h"
#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#endif
namespace kelpie::linuxapp {
UrlBar::UrlBar(LinuxApp& app):app_(app) {
#if KELPIE_LINUX_HAS_GTK
  root_=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,8);
  gtk_style_context_add_class(gtk_widget_get_style_context(root_),"chrome-nav");
  gtk_widget_set_size_request(root_,-1,72);
  auto button=[&](const char* icon,const char* title) {
    auto* value=ui::CreateSymbolButton(icon,title);
    gtk_style_context_add_class(gtk_widget_get_style_context(value),"chrome-button");
    gtk_widget_set_valign(value,GTK_ALIGN_CENTER); gtk_widget_set_size_request(value,40,40);
    gtk_box_pack_start(GTK_BOX(root_),value,FALSE,FALSE,0); return value;
  };
  back_button_=button("go-previous-symbolic","Back");
  forward_button_=button("go-next-symbolic","Forward");
  reload_button_=button("view-refresh-symbolic","Reload");
  auto* home=button("go-home-symbolic","Home");
  entry_shell_=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,8);
  gtk_style_context_add_class(gtk_widget_get_style_context(entry_shell_),"chrome-address");
  gtk_widget_set_hexpand(entry_shell_,TRUE); gtk_widget_set_valign(entry_shell_,GTK_ALIGN_CENTER);
  gtk_widget_set_size_request(entry_shell_,-1,44);
  brand_badge_=ui::CreateChromeIcon("channel-secure-symbolic");
  gtk_box_pack_start(GTK_BOX(entry_shell_),brand_badge_,FALSE,FALSE,0);
  entry_=gtk_entry_new(); gtk_entry_set_has_frame(GTK_ENTRY(entry_),FALSE);
  gtk_entry_set_placeholder_text(GTK_ENTRY(entry_),"Search or enter website name");
  gtk_box_pack_start(GTK_BOX(entry_shell_),entry_,TRUE,TRUE,0);
  auto* star=ui::CreateSymbolButton("non-starred-symbolic","Add favorite");
  gtk_style_context_add_class(gtk_widget_get_style_context(star),"chrome-button");
  gtk_box_pack_start(GTK_BOX(entry_shell_),star,FALSE,FALSE,0);
  gtk_box_pack_start(GTK_BOX(root_),entry_shell_,TRUE,TRUE,0);
  g_signal_connect_after(entry_shell_, "draw", G_CALLBACK(+[](GtkWidget* widget, cairo_t* cr, gpointer raw) -> gboolean {
    const auto frame = static_cast<UrlBar*>(raw)->load_frame_;
    if (frame.opacity <= 0) return FALSE;
    cairo_new_path(cr);
    const int width = gtk_widget_get_allocated_width(widget);
    const int height = gtk_widget_get_allocated_height(widget);
    bool first = true;
    TraceAddressLoadOutline(width, height, 3, frame.extent, [&](double x, double y) {
      if (first) cairo_move_to(cr, x, y);
      else cairo_line_to(cr, x, y);
      first = false;
    });
    cairo_set_source_rgba(cr, 0, 122.0 / 255, 1, frame.opacity);
    cairo_set_line_width(cr, 3);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    cairo_stroke(cr);
    return FALSE;
  }), this);
  for(auto [icon,title,index]:{std::tuple{"view-grid-symbolic","Bookmarks",0},
      {"network-workgroup-symbolic","Network inspector",1},{"document-open-recent-symbolic","History",2},
      {"avatar-default-symbolic","Login/register",3},{"view-more-symbolic","Settings",4}}) {
    if (index == 4) {
      inspector_3d_button_ = gtk_toggle_button_new();
      gtk_button_set_image(GTK_BUTTON(inspector_3d_button_), ui::CreateChromeIcon("inspector-cube"));
      gtk_widget_set_tooltip_text(inspector_3d_button_, "3D inspector");
      atk_object_set_name(gtk_widget_get_accessible(inspector_3d_button_), "3D inspector");
      gtk_style_context_add_class(gtk_widget_get_style_context(inspector_3d_button_), "chrome-button");
      gtk_widget_set_valign(inspector_3d_button_, GTK_ALIGN_CENTER);
      gtk_widget_set_size_request(inspector_3d_button_, 40, 40);
      gtk_widget_set_sensitive(inspector_3d_button_, FALSE);
      gtk_box_pack_start(GTK_BOX(root_), inspector_3d_button_, FALSE, FALSE, 0);
      inspector_toggle_handler_ = g_signal_connect(inspector_3d_button_, "toggled", G_CALLBACK(+[](GtkToggleButton*, gpointer raw) {
        auto* self = static_cast<UrlBar*>(raw);
        self->app_.Toggle3DInspector();
        self->Sync();
      }), this);
    }
    auto* item=button(icon,title); if(index==3) account_button_=item;
    g_object_set_data(G_OBJECT(item),"tool",GINT_TO_POINTER(index));
    g_signal_connect(item,"clicked",G_CALLBACK(+[](GtkButton* item,gpointer raw) {
      auto* self=static_cast<UrlBar*>(raw); if(self->tool_action) self->tool_action(GPOINTER_TO_INT(g_object_get_data(G_OBJECT(item),"tool")));
    }),this);
  }
  g_signal_connect_swapped(back_button_,"clicked",G_CALLBACK(+[](LinuxApp* a){a->GoBack();}),&app_);
  g_signal_connect_swapped(forward_button_,"clicked",G_CALLBACK(+[](LinuxApp* a){a->GoForward();}),&app_);
  g_signal_connect_swapped(reload_button_,"clicked",G_CALLBACK(+[](LinuxApp* a){a->Reload();}),&app_);
  g_signal_connect_swapped(home,"clicked",G_CALLBACK(+[](LinuxApp* a){a->Navigate(a->HomeUrl());}),&app_);
  g_signal_connect_swapped(star,"clicked",G_CALLBACK(+[](LinuxApp* a){a->AddBookmark(a->CurrentTitle(),a->CurrentUrl());}),&app_);
  g_signal_connect(entry_,"focus-in-event",G_CALLBACK(+[](GtkWidget*,GdkEventFocus*,gpointer raw)->gboolean {
    static_cast<UrlBar*>(raw)->editing_=true; return FALSE;
  }),this);
  g_signal_connect(entry_,"focus-out-event",G_CALLBACK(+[](GtkWidget*,GdkEventFocus*,gpointer raw)->gboolean {
    auto* self=static_cast<UrlBar*>(raw); self->editing_=false; self->Sync(); return FALSE;
  }),this);
  g_signal_connect(entry_,"activate",G_CALLBACK(+[](GtkEntry* entry,gpointer raw) {
    auto* self=static_cast<UrlBar*>(raw); self->editing_=false; self->app_.Navigate(gtk_entry_get_text(entry));
  }),this);
  completion_=gtk_list_store_new(1,G_TYPE_STRING);
  auto* completion=gtk_entry_completion_new(); gtk_entry_completion_set_model(completion,GTK_TREE_MODEL(completion_));
  gtk_entry_completion_set_text_column(completion,0); gtk_entry_completion_set_inline_completion(completion,TRUE);
  gtk_entry_set_completion(GTK_ENTRY(entry_),completion); g_object_unref(completion); g_object_unref(completion_);
#endif
}
GtkWidget* UrlBar::widget() const { return root_; }
void UrlBar::Focus() {
#if KELPIE_LINUX_HAS_GTK
  gtk_widget_grab_focus(entry_); gtk_editable_select_region(GTK_EDITABLE(entry_),0,-1);
#endif
}
void UrlBar::SyncLoadProgress(const TabSnapshot* tab) {
#if KELPIE_LINUX_HAS_GTK
  const auto now = AddressLoadProgress::Clock::now();
  const std::string_view id = tab ? std::string_view(tab->id) : std::string_view{};
  gboolean animate = TRUE;
  g_object_get(gtk_widget_get_settings(entry_shell_), "gtk-enable-animations", &animate, nullptr);
  const bool tab_changed = id != load_tab_;
  load_progress_.Update(tab && tab->is_loading, tab ? tab->load_progress : 0,
                        tab_changed, animate, now);
  if (tab_changed) load_tab_ = id;
  const auto frame = load_progress_.Frame(now);
  if (!(frame == load_frame_)) {
    load_frame_ = frame;
    gtk_widget_queue_draw(entry_shell_);
  }
#else
  (void)tab;
#endif
}

void UrlBar::Sync() {
#if KELPIE_LINUX_HAS_GTK
  const auto url=app_.CurrentUrl();
  if(!editing_ && url!=gtk_entry_get_text(GTK_ENTRY(entry_))) gtk_entry_set_text(GTK_ENTRY(entry_),url.c_str());
  gtk_widget_set_opacity(brand_badge_,url.starts_with("https:")?1:0);
  gtk_widget_set_sensitive(back_button_,app_.CanGoBack()); gtk_widget_set_sensitive(forward_button_,app_.CanGoForward());
  const auto inspector = app_.Active3DInspector();
  gtk_widget_set_sensitive(inspector_3d_button_, inspector.enabled);
  g_signal_handler_block(inspector_3d_button_, inspector_toggle_handler_);
  gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(inspector_3d_button_), inspector.active);
  g_signal_handler_unblock(inspector_3d_button_, inspector_toggle_handler_);
  if(!editing_) {
    gtk_list_store_clear(completion_);
    auto history=nlohmann::json::parse(app_.HistoryJson(),nullptr,false);
    if(history.is_array()) for(const auto& item:history) {
      auto address=item.value("url",""); if(address.empty())continue;
      GtkTreeIter iter; gtk_list_store_append(completion_,&iter); gtk_list_store_set(completion_,&iter,0,address.c_str(),-1);
    }
  }
  const auto account=app_.AccountState();
  if(account.avatar!=avatar_) {
    avatar_=account.avatar;
    GtkWidget* image=nullptr;
    if(!avatar_.empty() && avatar_.size()<=2*1024*1024) {
      auto* loader=gdk_pixbuf_loader_new();
      if(gdk_pixbuf_loader_write(loader,reinterpret_cast<const guchar*>(avatar_.data()),avatar_.size(),nullptr) && gdk_pixbuf_loader_close(loader,nullptr)) {
        auto* source=gdk_pixbuf_loader_get_pixbuf(loader);
        if(source && gdk_pixbuf_get_width(source)<=2048 && gdk_pixbuf_get_height(source)<=2048) {
          auto* scaled=gdk_pixbuf_scale_simple(source,34,34,GDK_INTERP_BILINEAR);
          auto* rounded=gdk_pixbuf_add_alpha(scaled,FALSE,0,0,0); g_object_unref(scaled);
          auto* pixels=gdk_pixbuf_get_pixels(rounded); const auto stride=gdk_pixbuf_get_rowstride(rounded);
          for(int y=0;y<34;++y)for(int x=0;x<34;++x)if((x-16.5)*(x-16.5)+(y-16.5)*(y-16.5)>17*17)pixels[y*stride+x*4+3]=0;
          image=gtk_image_new_from_pixbuf(rounded); g_object_unref(rounded);
        }
      }
      g_object_unref(loader);
    }
    if(!image)image=gtk_image_new_from_icon_name("avatar-default-symbolic",GTK_ICON_SIZE_LARGE_TOOLBAR);
    gtk_button_set_image(GTK_BUTTON(account_button_),image);
  }
  gtk_widget_set_tooltip_text(account_button_,account::AccountLabel(account).c_str());
#endif
}
}  // namespace kelpie::linuxapp
