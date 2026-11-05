#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <algorithm>
#include <limits>
#include <mutex>

// This scheduler is compiled only for the explicitly requested hosted comparison.
namespace {
std::mutex pumpLock;
bool pumpEnabled = false;
bool pumpHandoffPending = false;
bool pumpRunning = false; // Main thread only.
int64_t pumpLatestDelay = 0;
uint64_t pumpGeneration = 0;
dispatch_source_t pumpTimer = nil; // Main thread only.

void SchedulePump(int64_t delay);

void RunPump() {
    if (!gCEFInitialized) { return; }
    if (pumpRunning) { SchedulePump(1); return; }
    pumpRunning = true;
    cef_do_message_loop_work();
    pumpRunning = false;
}

void SchedulePump(int64_t delay) {
    uint64_t generation;
    {
        std::lock_guard<std::mutex> guard(pumpLock);
        if (!pumpEnabled) { return; }
        pumpLatestDelay = delay;
        if (pumpHandoffPending) { return; }
        pumpHandoffPending = true;
        generation = pumpGeneration;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        int64_t requested;
        {
            std::lock_guard<std::mutex> guard(pumpLock);
            if (!pumpEnabled || pumpGeneration != generation) { return; }
            pumpHandoffPending = false;
            requested = pumpLatestDelay;
        }
        if (pumpTimer == nil) {
            pumpTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_event_handler(pumpTimer, ^{
                bool enabled;
                { std::lock_guard<std::mutex> guard(pumpLock); enabled = pumpEnabled && !pumpHandoffPending; }
                if (enabled) { RunPump(); }
            });
            dispatch_resume(pumpTimer);
        }
        const int64_t maxDelay = std::numeric_limits<int64_t>::max() / NSEC_PER_MSEC;
        // Bound a callback storm to one scheduled pump per 4 ms; fallback polling remains active.
        const int64_t bounded = requested <= 4 ? 4 : std::min(requested, maxDelay);
        dispatch_source_set_timer(pumpTimer, dispatch_time(DISPATCH_TIME_NOW, bounded * NSEC_PER_MSEC),
                                  DISPATCH_TIME_FOREVER, 0);
    });
}

bool HostedPumpRequested() {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    return [env[@"GITHUB_ACTIONS"] isEqualToString:@"true"] &&
        [env[@"RUNNER_OS"] isEqualToString:@"macOS"] &&
        [env[@"KELPIE_HOSTED_RUNTIME"] isEqualToString:@"1"] &&
        [env[@"KELPIE_CEF_PUMP_TEST"] isEqualToString:@"scheduled"];
}

void StartPumpExperiment() {
    std::lock_guard<std::mutex> guard(pumpLock);
    pumpEnabled = HostedPumpRequested();
    pumpHandoffPending = false;
    ++pumpGeneration;
    fprintf(stdout, "[WorkflowCEFPump] mode=%s\n", pumpEnabled ? "scheduled" : "legacy");
}

void StopPumpExperiment() {
    {
        std::lock_guard<std::mutex> guard(pumpLock);
        pumpEnabled = false;
        pumpHandoffPending = false;
        ++pumpGeneration;
    }
    if (pumpTimer != nil) { dispatch_source_cancel(pumpTimer); pumpTimer = nil; }
}
}
