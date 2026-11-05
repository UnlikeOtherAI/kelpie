#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <algorithm>

static BOOL gCEFInitialized = YES;
static int pumpCalls = 0;
static int pumpDepth = 0;
static int maxDepth = 0;
namespace { void RunPump(); }
static void cef_do_message_loop_work() {
    ++pumpDepth;
    maxDepth = std::max(maxDepth, pumpDepth);
    ++pumpCalls;
    if (pumpCalls == 1) { RunPump(); }
    --pumpDepth;
}
#include "../../apps/macos/Kelpie/Renderer/CEFHostedPumpExperiment.h"

int main() {
    @autoreleasepool {
        setenv("GITHUB_ACTIONS", "true", 1);
        setenv("RUNNER_OS", "macOS", 1);
        setenv("KELPIE_HOSTED_RUNTIME", "1", 1);
        setenv("KELPIE_CEF_PUMP_TEST", "scheduled", 1);
        StartPumpExperiment();
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            SchedulePump(200);
            SchedulePump(20);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (pumpCalls != 2 || maxDepth != 1) {
                fprintf(stderr, "coalescing or reentry failed: %d depth %d\n", pumpCalls, maxDepth);
                exit(1);
            }
            SchedulePump(20);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                SchedulePump(180);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 75 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                if (pumpCalls != 2) { fprintf(stderr, "positive replacement failed\n"); exit(1); }
                StopPumpExperiment();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    if (pumpCalls != 2) { fprintf(stderr, "callback escaped shutdown\n"); exit(1); }
                    StartPumpExperiment();
                    SchedulePump(20);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                        if (pumpCalls != 3) { fprintf(stderr, "restart generation failed\n"); exit(1); }
                        StopPumpExperiment();
                        fprintf(stdout, "PASS: coalescing, replacement, no reentry, shutdown and restart fences\n");
                        exit(0);
                    });
                });
            });
        });
        dispatch_main();
    }
}
