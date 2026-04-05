package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class DOMHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("get-dom") { getDOM(it) }
        router.register("query-selector") { querySelector(it) }
        router.register("query-selector-all") { querySelectorAll(it) }
        router.register("get-element-text") { getElementText(it) }
        router.register("get-attributes") { getAttributes(it) }
    }

    private suspend fun getDOM(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: "html"
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');return el?{html:el.outerHTML.substring(0,50000),length:el.outerHTML.length}:{html:'',length:0};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun querySelector(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return{found:false};var r=el.getBoundingClientRect();return{found:true,element:{tag:el.tagName.toLowerCase(),text:(el.textContent||'').trim().substring(0,200),classes:Array.from(el.classList),id:el.id||null,rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result["found"] == true) successResponse(result) else errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector")
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun querySelectorAll(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val limit = (body["limit"] as? Int) ?: 50
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var els=document.querySelectorAll('$safe');return{elements:Array.from(els).slice(0,$limit).map(function(el){var r=el.getBoundingClientRect();return{tag:el.tagName.toLowerCase(),text:(el.textContent||'').trim().substring(0,200),classes:Array.from(el.classList),id:el.id||null,rect:{x:r.x,y:r.y,width:r.width,height:r.height}};}),total:els.length};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getElementText(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;return{text:(el.innerText||el.textContent||'').trim(),html:el.innerHTML.substring(0,5000)};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector") else successResponse(result)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getAttributes(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;var attrs={};for(var a of el.attributes){attrs[a.name]=a.value;}return{attributes:attrs,count:el.attributes.length};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector") else successResponse(result)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}
