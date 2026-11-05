#import <AppKit/AppKit.h>
struct cef_base_ref_counted_t {
 size_t size;
 void (*add_ref)(cef_base_ref_counted_t *);
 int (*release)(cef_base_ref_counted_t *);
 int (*has_one_ref)(cef_base_ref_counted_t *);
 int (*has_at_least_one_ref)(cef_base_ref_counted_t *);
};
struct cef_browser_t { cef_base_ref_counted_t base; };
struct cef_registration_t { cef_base_ref_counted_t base; };
struct cef_string_t { const char16_t *str; size_t length; };
struct cef_dev_tools_message_observer_t {
 cef_base_ref_counted_t base;
 int (*on_dev_tools_message)(cef_dev_tools_message_observer_t *, cef_browser_t *, const void *, size_t);
 void (*on_dev_tools_method_result)(cef_dev_tools_message_observer_t *, cef_browser_t *, int, int, const void *, size_t);
 void (*on_dev_tools_event)(cef_dev_tools_message_observer_t *, cef_browser_t *, const cef_string_t *, const void *, size_t);
 void (*on_dev_tools_agent_attached)(cef_dev_tools_message_observer_t *, cef_browser_t *);
 void (*on_dev_tools_agent_detached)(cef_dev_tools_message_observer_t *, cef_browser_t *);
};
struct cef_browser_host_t {
 cef_base_ref_counted_t base;
 cef_registration_t *(*add_dev_tools_message_observer)(cef_browser_host_t *, cef_dev_tools_message_observer_t *);
};
@interface CEFBridge : NSObject
- (cef_browser_t *)activeBrowser;
@end
int CEFBridgeBrowserIdentifier(cef_browser_t *);
cef_browser_host_t *CEFBridgeCopyBrowserHost(cef_browser_t *);
void CEFBridgeSendBrowserControlCommand(cef_browser_host_t *, NSString *, NSDictionary *, void (^)(BOOL, NSDictionary *));
