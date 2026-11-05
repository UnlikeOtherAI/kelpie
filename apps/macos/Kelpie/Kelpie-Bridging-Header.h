#ifndef Kelpie_Bridging_Header_h
#define Kelpie_Bridging_Header_h

#import "CEFBridge.h"
#import "CEFBridge+Cookies.h"
#import "CEFBridge+Screenshot.h"
#import "kelpie/state_c_api.h"
#import "kelpie/connect.h"
#import "kelpie/address_input.h"
#import "kelpie/ai_c_api.h"
#import "kelpie/viewport_presets_c_api.h"

#include "kelpie/script_presentation.h"
#include "kelpie/script_redaction.h"
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/mcp_c_api.h"

#endif

#import "CEFBridge+ScriptCapture.h"

#if defined(DEBUG) && defined(KELPIE_HOSTED_STREAM_TEST)
#import "CEFHostedStreamProbe.h"
#endif
