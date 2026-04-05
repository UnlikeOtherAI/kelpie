package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class InteractionHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("click") { click(it) }
        router.register("tap") { tap(it) }
        router.register("fill") { fill(it) }
        router.register("type") { type(it) }
        router.register("select-option") { selectOption(it) }
        router.register("check") { check(it) }
        router.register("uncheck") { uncheck(it) }
    }

    private suspend fun click(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;el.scrollIntoView({block:'center'});el.click();var r=el.getBoundingClientRect();return{tag:el.tagName.toLowerCase(),text:(el.textContent||'').trim().substring(0,100),rect:{x:r.x,y:r.y,width:r.width,height:r.height}};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) {
                errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector")
            } else {
                ctx.showTouchIndicatorForElement(selector)
                successResponse(mapOf("element" to result))
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun tap(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val safe = selector.replace("'", "\\'")
        // Show touch indicator before performing the tap
        ctx.showTouchIndicatorForElement(selector)
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;el.scrollIntoView({block:'center'});el.click();var r=el.getBoundingClientRect();return{tag:el.tagName.toLowerCase(),text:(el.textContent||'').trim().substring(0,100),rect:{x:r.x,y:r.y,width:r.width,height:r.height}};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector") else successResponse(mapOf("element" to result))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun fill(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value is required")
        val safe = selector.replace("'", "\\'")
        val safeVal = value.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;el.focus();var nativeSetter=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value')||Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value');if(nativeSetter&&nativeSetter.set){nativeSetter.set.call(el,'$safeVal');}else{el.value='$safeVal';}el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return{tag:el.tagName.toLowerCase(),name:el.name||'',value:el.value};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) {
                errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector")
            } else {
                ctx.showTouchIndicatorForElement(selector)
                successResponse(mapOf("element" to result))
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun type(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val text = body["text"] as? String ?: return errorResponse("MISSING_PARAM", "text is required")
        val safe = selector.replace("'", "\\'")
        val safeText = text.replace("'", "\\'").replace("\\", "\\\\")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;el.focus();var text='$safeText';for(var i=0;i<text.length;i++){var c=text[i];el.dispatchEvent(new KeyboardEvent('keydown',{key:c,bubbles:true}));el.dispatchEvent(new KeyboardEvent('keypress',{key:c,bubbles:true}));el.value+=c;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new KeyboardEvent('keyup',{key:c,bubbles:true}));}el.dispatchEvent(new Event('change',{bubbles:true}));return{tag:el.tagName.toLowerCase(),value:el.value};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector") else successResponse(mapOf("element" to result))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun selectOption(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value is required")
        val safe = selector.replace("'", "\\'")
        val safeVal = value.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;el.value='$safeVal';el.dispatchEvent(new Event('change',{bubbles:true}));return{tag:'select',value:el.value};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector") else successResponse(mapOf("element" to result))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun check(body: Map<String, Any?>): Map<String, Any?> = setChecked(body, true)
    private suspend fun uncheck(body: Map<String, Any?>): Map<String, Any?> = setChecked(body, false)

    private suspend fun setChecked(body: Map<String, Any?>, checked: Boolean): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;el.checked=$checked;el.dispatchEvent(new Event('change',{bubbles:true}));return{tag:el.tagName.toLowerCase(),checked:el.checked};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector") else successResponse(mapOf("element" to result))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}
