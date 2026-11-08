#import <Cocoa/Cocoa.h>
#include "capi/cef_app_capi.h"

int main(int argc, char* argv[]) {
    cef_main_args_t mainArgs = { .argc = argc, .argv = argv };
    int exitCode = cef_execute_process(&mainArgs, NULL, NULL);
    if (exitCode >= 0) {
        return exitCode;
    }
    // Not a subprocess — should not reach here for the helper app
    return 0;
}
