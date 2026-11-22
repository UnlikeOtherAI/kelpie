#import "CEFBridgeSupport.h"

#include <atomic>
#include <cstdlib>

extern "C" char *KelpieBeginChromiumDownload(int32_t, uint32_t, const char *, const char *);
extern "C" void KelpieUpdateChromiumDownload(int32_t, uint32_t, int64_t, int64_t, int32_t, int32_t);

namespace {
struct Handler {
    cef_download_handler_t api{};
    std::atomic<int> refs{1};
};

int Begin(cef_download_handler_t *, cef_browser_t *browser, cef_download_item_t *item,
          const cef_string_t *name, cef_before_download_callback_t *callback) {
    NSString *url = CEFBridgeStringFromUserFree(item->get_url(item));
    NSString *suggested = name && name->str
        ? [[NSString alloc] initWithCharacters:(const unichar *)name->str length:name->length] : @"download";
    char *file = KelpieBeginChromiumDownload(browser->get_identifier(browser), item->get_id(item),
                                             url.UTF8String, suggested.UTF8String);
    if (file) {
        cef_string_t path = CEFBridgeStringCreate([NSString stringWithUTF8String:file]);
        free(file);
        callback->cont(callback, &path, 0);
        CEFBridgeStringClear(&path);
    }
    return 1;
}

void Updated(cef_download_handler_t *, cef_browser_t *browser, cef_download_item_t *item,
             cef_download_item_callback_t *) {
    if (!item->is_valid(item)) return;
    const int complete = item->is_complete(item);
    KelpieUpdateChromiumDownload(browser->get_identifier(browser), item->get_id(item),
                                 item->get_received_bytes(item), item->get_total_bytes(item),
                                 complete, !complete && !item->is_in_progress(item));
}
}  // namespace

cef_download_handler_t *CEFBridgeDownloadHandler(cef_client_t *) {
    auto *h = new Handler;
    h->api.base.size = sizeof(h->api);
    h->api.base.add_ref = [](cef_base_ref_counted_t *p) { ++reinterpret_cast<Handler *>(p)->refs; };
    h->api.base.release = [](cef_base_ref_counted_t *p) -> int {
        auto *handler = reinterpret_cast<Handler *>(p);
        if (--handler->refs) return 0;
        delete handler;
        return 1;
    };
    h->api.base.has_one_ref = [](cef_base_ref_counted_t *p) -> int { return reinterpret_cast<Handler *>(p)->refs == 1; };
    h->api.base.has_at_least_one_ref = [](cef_base_ref_counted_t *p) -> int { return reinterpret_cast<Handler *>(p)->refs > 0; };
    h->api.can_download = [](cef_download_handler_t *, cef_browser_t *, const cef_string_t *, const cef_string_t *) { return 1; };
    h->api.on_before_download = Begin;
    h->api.on_download_updated = Updated;
    return &h->api;
}
