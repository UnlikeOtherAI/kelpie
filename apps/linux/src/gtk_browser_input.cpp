#include "gtk_browser_view.h"
#include "linux_app.h"
#if KELPIE_LINUX_HAS_GTK
#include <gdk/gdkkeysyms.h>
namespace kelpie::linuxapp {
namespace {
unsigned Modifiers(guint value) {
  unsigned result=0;
  if(value&GDK_SHIFT_MASK)result|=1<<1;
  if(value&GDK_CONTROL_MASK)result|=1<<2;
  if(value&GDK_MOD1_MASK)result|=1<<3;
  if(value&GDK_BUTTON1_MASK)result|=1<<4;
  if(value&GDK_BUTTON2_MASK)result|=1<<5;
  if(value&GDK_BUTTON3_MASK)result|=1<<6;
  if(value&GDK_LOCK_MASK)result|=1;
  return result;
}
bool ChromeKey(GdkEventKey* e) {
  const auto key=gdk_keyval_to_lower(e->keyval);
  return key==GDK_KEY_F11 || key==GDK_KEY_F5 || ((e->state&GDK_CONTROL_MASK) &&
      (key==GDK_KEY_l||key==GDK_KEY_t||key==GDK_KEY_w||key==GDK_KEY_r||
       key==GDK_KEY_Tab||key==GDK_KEY_ISO_Left_Tab||((e->state&GDK_SHIFT_MASK)&&key==GDK_KEY_n)));
}
int KeyCode(guint key) {
  if(key>=GDK_KEY_a&&key<=GDK_KEY_z)return key-'a'+'A';
  if(key<128)return key;
  if(key>=GDK_KEY_F1&&key<=GDK_KEY_F12)return 112+key-GDK_KEY_F1;
  switch(key) {
    case GDK_KEY_BackSpace:return 8; case GDK_KEY_Tab:case GDK_KEY_ISO_Left_Tab:return 9;
    case GDK_KEY_Return:case GDK_KEY_KP_Enter:return 13; case GDK_KEY_Escape:return 27;
    case GDK_KEY_Delete:return 46; case GDK_KEY_Insert:return 45; case GDK_KEY_Home:return 36;
    case GDK_KEY_End:return 35; case GDK_KEY_Page_Up:return 33; case GDK_KEY_Page_Down:return 34;
    case GDK_KEY_Left:return 37; case GDK_KEY_Up:return 38; case GDK_KEY_Right:return 39; case GDK_KEY_Down:return 40;
    case GDK_KEY_Shift_L:case GDK_KEY_Shift_R:return 16; case GDK_KEY_Control_L:case GDK_KEY_Control_R:return 17;
    case GDK_KEY_Alt_L:case GDK_KEY_Alt_R:return 18; default:return 0;
  }
}
}
void GtkBrowserView::ConnectKeyboard() {
  input_=gtk_im_multicontext_new(); gtk_im_context_set_use_preedit(input_,FALSE);
  g_object_set_data_full(G_OBJECT(canvas_),"ime",input_,g_object_unref);
  gtk_widget_add_events(canvas_,GDK_KEY_PRESS_MASK|GDK_KEY_RELEASE_MASK|GDK_SMOOTH_SCROLL_MASK);
  g_signal_connect(canvas_,"realize",G_CALLBACK(+[](GtkWidget* canvas,gpointer raw) {
    auto* self=static_cast<GtkBrowserView*>(raw); gtk_im_context_set_client_window(self->input_,gtk_widget_get_window(canvas));
  }),this);
  g_signal_connect(input_,"commit",G_CALLBACK(+[](GtkIMContext*,const char* text,gpointer raw) {
    static_cast<GtkBrowserView*>(raw)->app_.CommitText(text);
  }),this);
  g_signal_connect(canvas_,"event",G_CALLBACK(+[](GtkWidget*,GdkEvent* event,gpointer raw)->gboolean {
    auto* self=static_cast<GtkBrowserView*>(raw); GdkModifierType state{};
    if(gdk_event_get_state(event,&state))self->app_.InputModifiers(Modifiers(state));
    return FALSE;
  }),this);
  auto key=+[](GtkWidget*,GdkEventKey* event,gpointer raw)->gboolean {
    auto* self=static_cast<GtkBrowserView*>(raw); if(ChromeKey(event))return FALSE;
    const bool up=event->type==GDK_KEY_RELEASE;
    self->app_.Key(KeyCode(event->keyval),event->hardware_keycode,Modifiers(event->state),up);
    if(gtk_im_context_filter_keypress(self->input_,event))return TRUE;
    if(!up && !(event->state&(GDK_CONTROL_MASK|GDK_MOD1_MASK))) {
      const auto character=gdk_keyval_to_unicode(event->keyval);
      if(character>=32) { char text[8]{}; g_unichar_to_utf8(character,text); self->app_.CommitText(text); }
    }
    return TRUE;
  };
  g_signal_connect(canvas_,"key-press-event",G_CALLBACK(key),this);
  g_signal_connect(canvas_,"key-release-event",G_CALLBACK(key),this);
  g_signal_connect(canvas_,"scroll-event",G_CALLBACK(+[](GtkWidget*,GdkEventScroll* event,gpointer raw)->gboolean {
    if(event->direction!=GDK_SCROLL_SMOOTH)return FALSE;
    auto* self=static_cast<GtkBrowserView*>(raw);
    self->app_.SendBrowserMouseWheel(event->x,event->y,-event->delta_x*120,-event->delta_y*120); return TRUE;
  }),this);
}
}  // namespace kelpie::linuxapp
#endif
