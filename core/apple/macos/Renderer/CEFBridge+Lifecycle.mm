#import "CEFBridgeSupport.h"
#import <objc/runtime.h>
#include <atomic>

namespace {
template <typename Owner>
void AddReference(cef_base_ref_counted_t* base) {
    reinterpret_cast<Owner*>(base)->references.fetch_add(1);
}
template <typename Owner>
int ReleaseReference(cef_base_ref_counted_t* base) {
    reinterpret_cast<Owner*>(base)->references.fetch_sub(1);
    // The process owns one permanent reference; CEF borrows balanced refs.
    return 0;
}
template <typename Owner>
int HasOneReference(cef_base_ref_counted_t* base) {
    return reinterpret_cast<Owner*>(base)->references.load() == 1;
}
template <typename Owner>
int HasReference(cef_base_ref_counted_t* base) {
    return reinterpret_cast<Owner*>(base)->references.load() > 0;
}
template <typename Owner>
void ConfigureReferences(Owner& owner) {
    auto& base = owner.api.base;
    base.size = sizeof(owner.api);
    base.add_ref = AddReference<Owner>;
    base.release = ReleaseReference<Owner>;
    base.has_one_ref = HasOneReference<Owner>;
    base.has_at_least_one_ref = HasReference<Owner>;
}
struct PumpApplication { cef_app_t api{}; std::atomic<int> references{1}; };
struct PumpHandler { cef_browser_process_handler_t api{}; std::atomic<int> references{1}; };
PumpApplication application;
PumpHandler handler;
cef_app_t* MessagePumpApplication() {
    static const bool configured = [] {
        ConfigureReferences(application);
        ConfigureReferences(handler);
        application.api.get_browser_process_handler = [](cef_app_t*) {
            AddReference<PumpHandler>(&handler.api.base);
            return &handler.api;
        };
        // CEF requires a handler to choose MessagePumpExternal. The existing
        // owner-thread 60Hz timer supplies bounded polling, including delayed work.
        handler.api.on_schedule_message_pump_work = [](cef_browser_process_handler_t*, int64_t) {};
        return true;
    }();
    (void)configured;
    return &application.api;
}
}

static BOOL gCEFInitialized = NO;
static BOOL gAccountScoped = NO;
static NSString *gProfile;
static cef_request_context_t *gProfileContext = nullptr;

static NSString *EmbeddedCacheRoot(void) {
    NSString *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask].firstObject.path;
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier ?: @"kelpie-host";
    return [[support stringByAppendingPathComponent:identifier] stringByAppendingPathComponent:@"kelpie-cef-cache"];
}

cef_request_context_t *CEFBridgeCopyActiveContext(void) {
    if (!gCEFInitialized) return nullptr;
    if (!gAccountScoped) return cef_request_context_get_global_context();
    if (!gProfile) return nullptr;
    if (!gProfileContext) {
        cef_request_context_settings_t settings = {};
        settings.size = sizeof(settings);
        settings.cache_path = CEFBridgeStringCreate([EmbeddedCacheRoot() stringByAppendingPathComponent:gProfile]);
        gProfileContext = cef_request_context_create_context(&settings, nullptr);
        CEFBridgeStringClear(&settings.cache_path);
    }
    if (gProfileContext) gProfileContext->base.base.add_ref(&gProfileContext->base.base);
    return gProfileContext;
}

BOOL CEFBridgeIsCEFInitialized(void) {
    return gCEFInitialized;
}
static const void *kCEFHandlingSendEventKey = &kCEFHandlingSendEventKey;

@protocol CrAppProtocol
- (BOOL)isHandlingSendEvent;
@end

@protocol CrAppControlProtocol <CrAppProtocol>
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent;
@end

@protocol CefAppProtocol <CrAppControlProtocol>
@end

@interface NSApplication (KelpieCEFAppProtocol) <CefAppProtocol>
@end

@implementation NSApplication (KelpieCEFAppProtocol)

- (BOOL)isHandlingSendEvent {
    return [objc_getAssociatedObject(self, kCEFHandlingSendEventKey) boolValue];
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    objc_setAssociatedObject(
        self,
        kCEFHandlingSendEventKey,
        @(handlingSendEvent),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

@end

@implementation CEFBridge (Lifecycle)

+ (void)selectEmbeddedProfile:(NSString *)profile {
    gAccountScoped = YES;
    if (profile && [gProfile isEqualToString:profile]) return;
    if (gProfileContext) gProfileContext->base.base.release(&gProfileContext->base.base);
    gProfileContext = nullptr;
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet;
    gProfile = profile.length == 64 && [profile rangeOfCharacterFromSet:invalid].location == NSNotFound ? [profile copy] : nil;
}

+ (BOOL)initializeCEF {
    if (gCEFInitialized) {
        return YES;
    }

    const char *apiHash = cef_api_hash(CEF_API_VERSION, 0);
    NSLog(@"[CEF] Configured API version=%d hash=%s", cef_api_version(), apiHash != nullptr ? apiHash : "");

    NSString *helperExecutable = [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"Kelpie Helper.app/Contents/MacOS/Kelpie Helper"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:helperExecutable]) {
        NSLog(@"[CEF] FATAL: Kelpie Helper.app not found at expected path: %@", helperExecutable);
        return NO;
    }

    cef_main_args_t mainArgs = CEFBridgeMainArgs();
    int exitCode = cef_execute_process(&mainArgs, nullptr, nullptr);
    if (exitCode >= 0) {
        return NO;
    }

    cef_settings_t settings = {};
    settings.size = sizeof(settings);
    settings.no_sandbox = 1;
    settings.multi_threaded_message_loop = 0;
    // SwiftUI owns an already-running NSApplication loop. Use the independent
    // CEF external pump instead of Apple observers that missed loop entry.
    settings.external_message_pump = 1;

    cef_string_t subprocessPath = CEFBridgeStringCreate(helperExecutable);
    settings.browser_subprocess_path = subprocessPath;

    NSString *frameworkPath = [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
    cef_string_t frameworkPathCEF = CEFBridgeStringCreate(frameworkPath);
    settings.framework_dir_path = frameworkPathCEF;

    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    cef_string_t bundlePathCEF = CEFBridgeStringCreate(bundlePath);
    settings.main_bundle_path = bundlePathCEF;

    NSString *identifier = [NSBundle mainBundle].bundleIdentifier ?: @"kelpie-host";
    BOOL standalone = [identifier isEqualToString:@"com.kelpie.browser.macos"];
    NSString *cachePath = standalone ? [NSTemporaryDirectory() stringByAppendingPathComponent:@"kelpie-cef-cache"] : EmbeddedCacheRoot();
    [[NSFileManager defaultManager] createDirectoryAtPath:cachePath withIntermediateDirectories:YES attributes:nil error:nil];
    cef_string_t cachePathCEF = CEFBridgeStringCreate(cachePath);
    settings.cache_path = cachePathCEF;
    settings.root_cache_path = CEFBridgeStringCreate(cachePath);

    const int ok = cef_initialize(&mainArgs, &settings, MessagePumpApplication(), nullptr);
    CEFBridgeStringClear(&settings.browser_subprocess_path);
    CEFBridgeStringClear(&settings.framework_dir_path);
    CEFBridgeStringClear(&settings.main_bundle_path);
    CEFBridgeStringClear(&settings.cache_path);
    CEFBridgeStringClear(&settings.root_cache_path);
    gCEFInitialized = ok != 0;
    return gCEFInitialized;
}

+ (void)shutdownCEF {
    if (!gCEFInitialized) {
        return;
    }
    if (gProfileContext) gProfileContext->base.base.release(&gProfileContext->base.base);
    gProfileContext = nullptr;
    cef_shutdown();
    gCEFInitialized = NO;
}

+ (void)doMessageLoopWork {
    if (gCEFInitialized) {
        cef_do_message_loop_work();
    }
}

@end
