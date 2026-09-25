#include "browser_chrome.h"
#include "ui_theme.h"
#include "kelpie/base64.h"
#include <algorithm>
#include <cmath>
#include <sstream>
#if KELPIE_LINUX_HAS_GTK
namespace kelpie::linuxapp {
namespace {
void Class(GtkWidget* widget,const char* name) { gtk_style_context_add_class(gtk_widget_get_style_context(widget),name); }
void Clear(GtkWidget* box) { auto* children=gtk_container_get_children(GTK_CONTAINER(box)); for(auto* p=children;p;p=p->next)gtk_widget_destroy(GTK_WIDGET(p->data)); g_list_free(children); }
GtkWidget* Symbol(const char* icon,const char* label,int width) {
  auto* button=ui::CreateSymbolButton(icon,label); Class(button,"chrome-button");
  gtk_widget_set_size_request(button,width,40); return button;
}
void OpenFavorite(GtkButton* button,gpointer raw) {
  static_cast<LinuxApp*>(raw)->Navigate(static_cast<const char*>(g_object_get_data(G_OBJECT(button),"url")));
}
}
BrowserChrome::BrowserChrome(LinuxApp& app,GtkWindow* window):app_(app),window_(window) {
  css_=gtk_css_provider_new();
  gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),GTK_STYLE_PROVIDER(css_),GTK_STYLE_PROVIDER_PRIORITY_APPLICATION+10);
  title_=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,0); Class(title_,"chrome-title"); gtk_widget_set_size_request(title_,-1,52);
  auto* plus=Symbol("list-add-symbolic","New tab",56);
  gtk_box_pack_start(GTK_BOX(title_),plus,FALSE,FALSE,0);
  g_signal_connect_swapped(plus,"clicked",G_CALLBACK(+[](LinuxApp* a){a->NewTab();}),&app_);
  g_signal_connect(plus,"button-press-event",G_CALLBACK(+[](GtkWidget*,GdkEventButton* event,gpointer raw)->gboolean {
    if(event->button==3) { static_cast<LinuxApp*>(raw)->NewTab(true); return TRUE; } return FALSE;
  }),&app_);
  auto* scroll=gtk_scrolled_window_new(nullptr,nullptr);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),GTK_POLICY_EXTERNAL,GTK_POLICY_NEVER);
  gtk_scrolled_window_set_overlay_scrolling(GTK_SCROLLED_WINDOW(scroll),FALSE);
  tabs_=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,0); gtk_container_add(GTK_CONTAINER(scroll),tabs_);
  gtk_box_pack_start(GTK_BOX(title_),scroll,TRUE,TRUE,0);
  auto* drag=gtk_event_box_new(); gtk_widget_set_size_request(drag,40,52); gtk_box_pack_start(GTK_BOX(title_),drag,FALSE,FALSE,0);
  g_signal_connect(drag,"button-press-event",G_CALLBACK(+[](GtkWidget*,GdkEventButton* event,gpointer raw)->gboolean {
    auto* window=GTK_WINDOW(raw);
    if(event->type==GDK_2BUTTON_PRESS) { if(gtk_window_is_maximized(window))gtk_window_unmaximize(window); else gtk_window_maximize(window); }
    else if(event->button==1)gtk_window_begin_move_drag(window,1,event->x_root,event->y_root,event->time);
    return TRUE;
  }),window_);
  for(auto [icon,label,action]:{std::tuple{"window-minimize-symbolic","Minimize",0},{"window-maximize-symbolic","Maximize",1},{"window-close-symbolic","Close",2}}) {
    auto* button=Symbol(icon,label,50); Class(button,"chrome-caption"); if(action==2)Class(button,"chrome-close");
    g_object_set_data(G_OBJECT(button),"action",GINT_TO_POINTER(action));
    gtk_box_pack_start(GTK_BOX(title_),button,FALSE,FALSE,0);
    g_signal_connect(button,"clicked",G_CALLBACK(+[](GtkButton* button,gpointer raw) {
      auto* window=GTK_WINDOW(raw); auto action=GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button),"action"));
      if(action==0)gtk_window_iconify(window);
      if(action==1) { if(gtk_window_is_maximized(window))gtk_window_unmaximize(window); else gtk_window_maximize(window); }
      if(action==2)gtk_window_close(window);
    }),window_);
  }
  favorites_=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,14); Class(favorites_,"chrome-favorites");
  gtk_widget_set_no_show_all(favorites_,TRUE); gtk_widget_set_size_request(favorites_,-1,44);
  separator_=gtk_drawing_area_new(); gtk_widget_set_size_request(separator_,-1,1); Class(separator_,"chrome-separator");
  Palette();
}
BrowserChrome::~BrowserChrome() {
  gtk_style_context_remove_provider_for_screen(gdk_screen_get_default(),GTK_STYLE_PROVIDER(css_)); g_object_unref(css_);
}
void BrowserChrome::Tabs() {
  auto tabs=app_.Tabs(); std::string key;
  for(auto& tab:tabs)key+=tab.id+tab.title+(tab.active?"1":"0")+(tab.favicon_png_base64?*tab.favicon_png_base64:"");
  if(key==tabs_key_)return; tabs_key_=key; Clear(tabs_);
  for(const auto& tab:tabs) {
    auto* item=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,0); Class(item,"chrome-tab");
    if(tab.active)Class(item,"active");
    if(tab.active) g_signal_connect(item,"size-allocate",G_CALLBACK(+[](GtkWidget* widget,GtkAllocation* bounds,gpointer raw) {
      auto* scroll=gtk_widget_get_ancestor(widget,GTK_TYPE_SCROLLED_WINDOW);
      if(!scroll) return;
      auto* adjustment=gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(scroll));
      const auto left=gtk_adjustment_get_value(adjustment); const auto page=gtk_adjustment_get_page_size(adjustment);
      if(bounds->x<left)gtk_adjustment_set_value(adjustment,bounds->x);
      else if(bounds->x+bounds->width>left+page)gtk_adjustment_set_value(adjustment,bounds->x+bounds->width-page);
      (void)raw;
    }),nullptr);
    g_object_set_data(G_OBJECT(item),"active",GINT_TO_POINTER(tab.active));
    g_signal_connect(item,"draw",G_CALLBACK(+[](GtkWidget* widget,cairo_t* cr,gpointer raw)->gboolean {
      auto* self=static_cast<BrowserChrome*>(raw);
      const double w=gtk_widget_get_allocated_width(widget); const double h=gtk_widget_get_allocated_height(widget);
      if(GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget),"active"))) {
        cairo_set_source_rgb(cr,self->color_[0]/255,self->color_[1]/255,self->color_[2]/255);
        cairo_move_to(cr,0,h); cairo_curve_to(cr,8,h,8,h-3,8,h-8); cairo_line_to(cr,8,10);
        cairo_curve_to(cr,8,3,11,0,18,0); cairo_line_to(cr,w-18,0);
        cairo_curve_to(cr,w-11,0,w-8,3,w-8,10); cairo_line_to(cr,w-8,h-8);
        cairo_curve_to(cr,w-8,h-3,w-8,h,w,h); cairo_close_path(cr); cairo_fill(cr);
      } else {
        cairo_set_source_rgba(cr,.05,.09,.19,.15); cairo_set_line_width(cr,1);
        cairo_move_to(cr,w-.5,10); cairo_line_to(cr,w-.5,h-10); cairo_stroke(cr);
      }
      return FALSE;
    }),this);
    gtk_widget_set_size_request(item,190,44); gtk_widget_set_margin_top(item,8);
    auto* select=gtk_button_new(); Class(select,"chrome-button"); gtk_widget_set_hexpand(select,TRUE);
    auto* row=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,8);
    GtkWidget* icon=nullptr;
    if(tab.favicon_png_base64 && !tab.favicon_png_base64->empty()) {
      gsize length=0; auto* decoded=g_base64_decode(tab.favicon_png_base64->c_str(),&length); std::vector<unsigned char> bytes(decoded,decoded+length); g_free(decoded);
      auto* loader=gdk_pixbuf_loader_new();
      if(gdk_pixbuf_loader_write(loader,bytes.data(),bytes.size(),nullptr) && gdk_pixbuf_loader_close(loader,nullptr)) {
        auto* pixels=gdk_pixbuf_loader_get_pixbuf(loader);
        if(pixels) { auto* scaled=gdk_pixbuf_scale_simple(pixels,18,18,GDK_INTERP_BILINEAR); icon=gtk_image_new_from_pixbuf(scaled); g_object_unref(scaled); }
      }
      g_object_unref(loader);
    }
    if(!icon)icon=gtk_image_new_from_icon_name("web-browser-symbolic",GTK_ICON_SIZE_MENU);
    gtk_box_pack_start(GTK_BOX(row),icon,FALSE,FALSE,0);
    auto* label=gtk_label_new((tab.title.empty()?"New tab":tab.title).c_str()); gtk_label_set_ellipsize(GTK_LABEL(label),PANGO_ELLIPSIZE_END);
    gtk_label_set_max_width_chars(GTK_LABEL(label),21); gtk_label_set_xalign(GTK_LABEL(label),0);
    gtk_box_pack_start(GTK_BOX(row),label,TRUE,TRUE,0); gtk_container_add(GTK_CONTAINER(select),row);
    gtk_box_pack_start(GTK_BOX(item),select,TRUE,TRUE,0);
    auto* close=Symbol("window-close-symbolic","Close tab",24); gtk_box_pack_start(GTK_BOX(item),close,FALSE,FALSE,0);
    for(auto* button:{select,close})g_object_set_data_full(G_OBJECT(button),"tab",g_strdup(tab.id.c_str()),g_free);
    g_signal_connect(select,"clicked",G_CALLBACK(+[](GtkButton* b,gpointer raw){static_cast<LinuxApp*>(raw)->ActivateTab(static_cast<const char*>(g_object_get_data(G_OBJECT(b),"tab")));}),&app_);
    g_signal_connect(close,"clicked",G_CALLBACK(+[](GtkButton* b,gpointer raw){static_cast<LinuxApp*>(raw)->CloseTab(static_cast<const char*>(g_object_get_data(G_OBJECT(b),"tab")));}),&app_);
    gtk_box_pack_start(GTK_BOX(tabs_),item,FALSE,FALSE,0);
  }
  gtk_widget_show_all(tabs_);
}
void BrowserChrome::Favorites() {
  auto key=app_.BookmarksJson();
  key+=std::to_string(gtk_widget_get_allocated_width(GTK_WIDGET(window_)));
  if(key==favorites_key_)return; favorites_key_=key; Clear(favorites_);
  auto items=nlohmann::json::parse(app_.BookmarksJson(),nullptr,false);
  if(!items.is_array()||items.empty()) { gtk_widget_hide(favorites_); return; }
  int room=std::max(1,(gtk_widget_get_allocated_width(GTK_WIDGET(window_))-60)/140),index=0;
  auto* overflow=gtk_menu_new(); bool has_overflow=false;
  for(const auto& item:items) {
    auto name=item.value("title",item.value("url","")); auto url=item.value("url","");
    if(index++<room) {
      auto* button=gtk_button_new_with_label(name.c_str()); Class(button,"chrome-button");
      auto* label=gtk_bin_get_child(GTK_BIN(button)); gtk_label_set_ellipsize(GTK_LABEL(label),PANGO_ELLIPSIZE_END); gtk_label_set_max_width_chars(GTK_LABEL(label),18);
      gtk_widget_set_tooltip_text(button,url.c_str()); g_object_set_data_full(G_OBJECT(button),"url",g_strdup(url.c_str()),g_free);
      g_signal_connect(button,"clicked",G_CALLBACK(OpenFavorite),&app_); gtk_box_pack_start(GTK_BOX(favorites_),button,FALSE,FALSE,0);
    } else {
      auto* button=gtk_menu_item_new_with_label(name.c_str()); g_object_set_data_full(G_OBJECT(button),"url",g_strdup(url.c_str()),g_free);
      g_signal_connect(button,"activate",G_CALLBACK(OpenFavorite),&app_); gtk_menu_shell_append(GTK_MENU_SHELL(overflow),button); has_overflow=true;
    }
  }
  if(has_overflow) { auto* button=gtk_menu_button_new(); gtk_button_set_label(GTK_BUTTON(button),"…"); Class(button,"chrome-button"); gtk_menu_button_set_popup(GTK_MENU_BUTTON(button),overflow); gtk_widget_show_all(overflow); gtk_box_pack_end(GTK_BOX(favorites_),button,FALSE,FALSE,0); }
  else gtk_widget_destroy(overflow);
  gtk_widget_show_all(favorites_); gtk_widget_show(favorites_);
}
void BrowserChrome::Palette() {
  auto now=g_get_monotonic_time();
  if(now-last_sample_>500000) {
    last_sample_=now; auto frame=app_.ViewFrame();
    if(frame.valid()) {
      std::array<double,3> sample{}; int count=0;
      for(int y=0;y<std::min(frame.height,24);y+=3)for(int x=0;x<frame.width;x+=std::max(1,frame.width/256)) {
        auto offset=(static_cast<std::size_t>(y)*frame.width+x)*4;
        for(int c=0;c<3;++c)sample[c]+=frame.pixels[offset+2-c]; ++count;
      }
      for(auto& c:sample)c/=std::max(1,count);
      if(sample!=target_) { from_=color_; target_=sample; transition_=now; }
    }
  }
  double p=std::clamp((now-transition_)/220000.0,0.0,1.0); p=p*p*(3-2*p);
  for(int c=0;c<3;++c)color_[c]=from_[c]+(target_[c]-from_[c])*p;
  bool dark=color_[0]*.2126+color_[1]*.7152+color_[2]*.0722<130;
  auto rgb=[&](double wash) { std::ostringstream s; s<<"rgb("; for(int c=0;c<3;++c){if(c)s<<',';s<<int(color_[c]*(1-wash)+(dark?255:0)*wash);}s<<')';return s.str(); };
  const auto ink=dark?"#f7f8fc":"#0d1731";
  std::string css=R"CSS(
.kelpie-window { background:white; }
.chrome-title { background:#e5eaf3; color:#0d1731; padding:0; }
.chrome-button { background:transparent; background-image:none; border:0; box-shadow:none; padding:0 8px; border-radius:6px; min-height:24px; min-width:0; color:inherit; }
.chrome-button:hover { background:rgba(128,128,128,.13); }
.chrome-button:disabled { opacity:.35; }
.chrome-caption { color:#0d1731; border-radius:0; }
.chrome-close:hover { background:#e81123; color:white; }
.chrome-tab { background:transparent; color:#0d1731; padding:0 8px; }
.chrome-tab label { font-size:13px; }
.chrome-nav { padding:0 14px; }
.chrome-address { border-radius:24px; padding:0 12px; border:1px solid rgba(128,128,128,.13); }
.chrome-address entry { background:transparent; color:inherit; box-shadow:none; border:0; font-size:16px; padding:0; }
.chrome-favorites { padding:0 14px; font-size:13px; }
)CSS";
  css+=".chrome-nav,.chrome-favorites { background:"+rgb(0)+"; color:"+ink+"; }.chrome-tab.active { color:"+ink+"; }";
  css+=".chrome-address { background:"+rgb(.09)+"; }.chrome-separator { background:"+rgb(.10)+"; }";
  gtk_css_provider_load_from_data(css_,css.c_str(),-1,nullptr);
}
void BrowserChrome::Sync() { Tabs(); Favorites(); Palette(); }
void BrowserChrome::AccountMenu(GtkWidget* anchor) {
  auto state=app_.AccountState(); auto* menu=gtk_menu_new();
  auto item=[&](const std::string& title,int action) {
    auto* value=gtk_menu_item_new_with_label(title.c_str()); gtk_menu_shell_append(GTK_MENU_SHELL(menu),value);
    if(action==0)gtk_widget_set_sensitive(value,FALSE);
    else { g_object_set_data(G_OBJECT(value),"action",GINT_TO_POINTER(action));
      g_signal_connect(value,"activate",G_CALLBACK(+[](GtkMenuItem* item,gpointer raw) {
        auto* app=static_cast<LinuxApp*>(raw); int action=GPOINTER_TO_INT(g_object_get_data(G_OBJECT(item),"action"));
        if(action==1)app->AccountSignIn(); if(action==2)app->AccountSignOut(); if(action==3)app->AccountRefresh();
      }),&app_);
    }
  };
  item("UnlikeOtherAI account",0);
  if(state.signed_in) { item(state.name.empty()?state.email:state.name,0); item(state.busy?"Syncing favorites…":"Refresh favorites",state.busy?0:3); item("Sign out and show local favorites",2); }
  else if(state.signing_in) { item("Complete sign-in in your browser",0); item("Cancel sign-in",2); }
  else item("Sign in with UOA",state.busy?0:1);
  if(!state.error.empty())item(state.error,0);
  g_signal_connect_swapped(menu,"selection-done",G_CALLBACK(gtk_widget_destroy),menu);
  gtk_widget_show_all(menu); gtk_menu_popup_at_widget(GTK_MENU(menu),anchor,GDK_GRAVITY_SOUTH_EAST,GDK_GRAVITY_NORTH_EAST,nullptr);
}
}  // namespace kelpie::linuxapp
#endif
