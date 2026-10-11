#pragma once
#ifdef __cplusplus
extern "C" {
#endif
typedef struct KelpieBrowserGateway* KelpieBrowserGatewayRef;
// config: {nativeMethods:[HTTP kebab-case endpoints],targeting:'direct'|'selected',
// fixedReader:bool,requireAuthorization:bool(default true),allowActions:bool(default true),
// extensions:[{name,method,description,inputSchema,mutates}]}.
// No transport, authentication, endpoint attachment or implicit pairing occurs here.
KelpieBrowserGatewayRef kelpie_browser_gateway_create(const char* config_json);
void kelpie_browser_gateway_destroy(KelpieBrowserGatewayRef gateway);
// Returned JSON: {kind:'authorize',request,mutates}, {kind:'dispatch',method,params,mutates},
// or {kind:'complete',response}. Authorization completion is {success:true|false}.
// Dispatch native result: existing {success:true,...} shape; fixed reader returns {success:true,result}.
// 'browser-control-evaluate' executes only this generated fixed expression, preferably in a private realm.
// begin rejects busy without disturbing the pending operation. Call next after executing a step;
// advance consumes that step exactly once. cancel returns an uncertain failure after mutation dispatch.
char* kelpie_browser_gateway_begin(KelpieBrowserGatewayRef gateway, const char* request_json);
char* kelpie_browser_gateway_begin_mcp(KelpieBrowserGatewayRef gateway, const char* jsonrpc_json);
char* kelpie_browser_gateway_next(KelpieBrowserGatewayRef gateway);
char* kelpie_browser_gateway_advance(KelpieBrowserGatewayRef gateway, const char* result_json);
char* kelpie_browser_gateway_cancel(KelpieBrowserGatewayRef gateway);
// Every returned string is caller-owned; free with existing kelpie_mcp_free_string.
#ifdef __cplusplus
}
#endif
