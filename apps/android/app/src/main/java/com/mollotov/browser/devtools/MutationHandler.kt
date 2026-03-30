package com.mollotov.browser.devtools

import com.mollotov.browser.handlers.HandlerContext
import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse

class MutationHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("watch-mutations") { watchMutations(it) }
        router.register("get-mutations") { getMutations(it) }
        router.register("stop-watching") { stopWatching(it) }
    }

    private suspend fun watchMutations(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: "body"
        val attributes = body["attributes"] as? Boolean ?: true
        val childList = body["childList"] as? Boolean ?: true
        val subtree = body["subtree"] as? Boolean ?: true
        val characterData = body["characterData"] as? Boolean ?: false
        val safe = selector.replace("'", "\\'")

        val js = """
(function(){
    if(!window.__mollotovMutations)window.__mollotovMutations={};
    var id='mut_'+Date.now();
    var buffer=[];
    var target=document.querySelector('$safe');
    if(!target)return null;
    var observer=new MutationObserver(function(mutations){
        mutations.forEach(function(m){
            var entry={type:m.type,target:m.target.tagName?m.target.tagName.toLowerCase():'text',timestamp:new Date().toISOString()};
            if(m.type==='childList'){
                entry.added=Array.from(m.addedNodes).filter(function(n){return n.nodeType===1;}).map(function(n){return{tag:n.tagName.toLowerCase(),text:(n.textContent||'').trim().substring(0,50)};});
                entry.removed=Array.from(m.removedNodes).filter(function(n){return n.nodeType===1;}).map(function(n){return{tag:n.tagName.toLowerCase()};});
            }else if(m.type==='attributes'){entry.attribute=m.attributeName;entry.oldValue=m.oldValue;entry.newValue=m.target.getAttribute(m.attributeName);}
            buffer.push(entry);if(buffer.length>1000)buffer.shift();
        });
    });
    observer.observe(target,{attributes:$attributes,childList:$childList,subtree:$subtree,characterData:$characterData,attributeOldValue:$attributes});
    window.__mollotovMutations[id]={observer:observer,buffer:buffer};
    return{watchId:id,watching:true};
})()
""".replace("\n", " ")
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "Target not found: $selector") else successResponse(result)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getMutations(body: Map<String, Any?>): Map<String, Any?> {
        val watchId = body["watchId"] as? String ?: return errorResponse("MISSING_PARAM", "watchId is required")
        val clear = body["clear"] as? Boolean ?: true
        val safe = watchId.replace("'", "\\'")
        val js = "(function(){var w=(window.__mollotovMutations||{})['$safe'];if(!w)return null;var m=w.buffer.slice();if($clear)w.buffer.length=0;return{mutations:m,count:m.length,hasMore:false};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("WATCH_NOT_FOUND", "Watch $watchId not found") else successResponse(result)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun stopWatching(body: Map<String, Any?>): Map<String, Any?> {
        val watchId = body["watchId"] as? String ?: return errorResponse("MISSING_PARAM", "watchId is required")
        val safe = watchId.replace("'", "\\'")
        val js = "(function(){var w=(window.__mollotovMutations||{})['$safe'];if(!w)return null;w.observer.disconnect();var t=w.buffer.length;delete window.__mollotovMutations['$safe'];return{totalMutations:t};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("WATCH_NOT_FOUND", "Watch $watchId not found") else successResponse(result)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}
