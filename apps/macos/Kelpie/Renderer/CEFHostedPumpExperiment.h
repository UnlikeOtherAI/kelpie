#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <algorithm>
#include <atomic>
#include <limits>
#include <mutex>

// This scheduler is compiled only for the explicitly requested hosted comparison.
namespace {
std::mutex pumpLock;
bool pumpEnabled = false;
bool pumpHandoffPending = false;
bool pumpRunning = false; // Main thread only.
dispatch_time_t pumpLatestDeadline = DISPATCH_TIME_NOW;
std::atomic<bool> pumpOptIn{false};
uint64_t pumpGeneration = 0;
dispatch_source_t pumpTimer = nil; // Main thread only.

void SchedulePump(int64_t delay);

void RunPump() {
    if (![NSThread isMainThread]) { SchedulePump(0); return; }
    if (!gCEFInitialized) { return; }
    if (pumpRunning) { SchedulePump(1); return; }
    pumpRunning = true;
    cef_do_message_loop_work();
    pumpRunning = false;
}

void SchedulePump(int64_t delay) {
    const int64_t maxDelay = std::numeric_limits<int64_t>::max() / NSEC_PER_MSEC;
    // A 4 ms minimum bounds callback storms while servicing immediate work promptly.
    const int64_t bounded = delay <= 4 ? 4 : std::min(delay, maxDelay);
    const dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, bounded * NSEC_PER_MSEC);
    uint64_t generation;
    {
        std::lock_guard<std::mutex> guard(pumpLock);
        if (!pumpEnabled) { return; }
        pumpLatestDeadline = deadline;
        if (pumpHandoffPending) { return; }
        pumpHandoffPending = true;
        generation = pumpGeneration;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_time_t requestedDeadline;
        {
            std::lock_guard<std::mutex> guard(pumpLock);
            if (!pumpEnabled || pumpGeneration != generation) { return; }
            pumpHandoffPending = false;
            requestedDeadline = pumpLatestDeadline;
        }
        if (pumpTimer == nil) {
            pumpTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_event_handler(pumpTimer, ^{
                bool enabled;
                { std::lock_guard<std::mutex> guard(pumpLock);
                  enabled = pumpEnabled && pumpGeneration == generation && !pumpHandoffPending; }
                if (enabled) { RunPump(); }
            });
            dispatch_resume(pumpTimer);
        }
        dispatch_source_set_timer(pumpTimer, requestedDeadline, DISPATCH_TIME_FOREVER, 0);
    });
}

bool HostedPumpRequested() {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    return [env[@"GITHUB_ACTIONS"] isEqualToString:@"true"] &&
        [env[@"RUNNER_OS"] isEqualToString:@"macOS"] &&
        [env[@"KELPIE_HOSTED_RUNTIME"] isEqualToString:@"1"] &&
        [env[@"KELPIE_CEF_PUMP_TEST"] isEqualToString:@"scheduled"];
}

bool PumpExperimentEnabled() { return pumpOptIn.load(std::memory_order_relaxed); }

void StartPumpExperiment() {
    NSCAssert([NSThread isMainThread], @"CEF pump must start on the main thread");
    std::lock_guard<std::mutex> guard(pumpLock);
    pumpEnabled = HostedPumpRequested();
    pumpOptIn.store(pumpEnabled, std::memory_order_relaxed);
    pumpHandoffPending = false;
    ++pumpGeneration;
    fprintf(stdout, "[WorkflowCEFPump] mode=%s\n", pumpEnabled ? "scheduled" : "legacy");
}

void StopPumpExperiment() {
    NSCAssert([NSThread isMainThread], @"CEF pump must stop on the main thread");
    {
        std::lock_guard<std::mutex> guard(pumpLock);
        pumpEnabled = false;
        pumpOptIn.store(false, std::memory_order_relaxed);
        pumpHandoffPending = false;
        ++pumpGeneration;
    }
    if (pumpTimer != nil) { dispatch_source_cancel(pumpTimer); pumpTimer = nil; }
}
}
