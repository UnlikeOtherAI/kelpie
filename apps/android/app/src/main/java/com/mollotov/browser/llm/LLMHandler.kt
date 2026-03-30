package com.mollotov.browser.llm

import com.mollotov.browser.handlers.HandlerContext
import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse

class LLMHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("get-accessibility-tree") { getAccessibilityTree(it) }
        router.register("get-visible-elements") { getVisibleElements(it) }
        router.register("get-page-text") { getPageText(it) }
        router.register("get-form-state") { getFormState() }
        router.register("find-element") { findElement(it) }
        router.register("find-button") { findButton(it) }
        router.register("find-link") { findLink(it) }
        router.register("find-input") { findInput(it) }
        router.register("screenshot-annotated") { screenshotAnnotated() }
        router.register("click-annotation") { clickAnnotation(it) }
        router.register("fill-annotation") { fillAnnotation(it) }
        router.register("query-shadow-dom") { queryShadowDOM(it) }
        router.register("get-shadow-roots") { getShadowRoots() }
    }

    private suspend fun getAccessibilityTree(body: Map<String, Any?>): Map<String, Any?> {
        val root = body["root"] as? String ?: "body"
        val maxDepth = (body["maxDepth"] as? Int) ?: 5
        val safe = root.replace("'", "\\'")
        val js = "(function(){function walk(el,d){if(d>$maxDepth)return null;var role=el.getAttribute('role')||el.tagName.toLowerCase();var name=el.getAttribute('aria-label')||el.textContent?.trim().substring(0,50)||'';var node={role:role,name:name};if(el.getAttribute('aria-checked'))node.checked=el.getAttribute('aria-checked')==='true';if(el.disabled)node.disabled=true;if(document.activeElement===el)node.focused=true;var ch=[];for(var c of el.children){var cn=walk(c,d+1);if(cn)ch.push(cn);}if(ch.length)node.children=ch;return node;}var r=document.querySelector('$safe');if(!r)return{tree:{role:'none'},nodeCount:0};return{tree:walk(r,0),nodeCount:r.querySelectorAll('*').length};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getVisibleElements(body: Map<String, Any?>): Map<String, Any?> {
        val interactableOnly = body["interactableOnly"] as? Boolean ?: false
        val js = "(function(){var els=document.querySelectorAll('*');var visible=[];for(var el of els){var r=el.getBoundingClientRect();if(r.width>0&&r.height>0&&r.top<window.innerHeight&&r.bottom>0&&r.left<window.innerWidth&&r.right>0){var tag=el.tagName.toLowerCase();if($interactableOnly&&!['a','button','input','select','textarea'].includes(tag)&&!el.onclick&&el.getAttribute('role')!=='button')continue;visible.push({tag:tag,text:(el.textContent||'').trim().substring(0,100),rect:{x:r.x,y:r.y,width:r.width,height:r.height},role:el.getAttribute('role')||undefined,interactable:['a','button','input','select','textarea'].includes(tag)});if(visible.length>=200)break;}}return{viewport:{width:window.innerWidth,height:window.innerHeight,scrollX:window.scrollX,scrollY:window.scrollY},elements:visible,count:visible.length};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getPageText(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: "body"
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return{title:'',content:'',wordCount:0};var t=el.innerText||el.textContent||'';return{title:document.title,content:t.trim(),wordCount:t.trim().split(/\\s+/).length,language:document.documentElement.lang||null,excerpt:t.trim().substring(0,200)};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getFormState(): Map<String, Any?> {
        val js = "(function(){var forms=document.querySelectorAll('form');if(!forms.length)return{forms:[],formCount:0};return{forms:Array.from(forms).map(function(f,i){var fields=Array.from(f.querySelectorAll('input,select,textarea')).map(function(el){return{name:el.name||'',type:el.type||'text',selector:el.tagName.toLowerCase()+(el.name?'[name=\"'+el.name+'\"]':''),value:el.value||'',required:el.required,valid:el.checkValidity(),disabled:el.disabled};});var btn=f.querySelector('button[type=submit],input[type=submit]');return{selector:'form:nth-of-type('+(i+1)+')',action:f.action||'',method:f.method||'get',fields:fields,isValid:f.checkValidity(),emptyRequired:fields.filter(function(fl){return fl.required&&!fl.value;}).map(function(fl){return fl.name;}),submitButton:btn?{selector:btn.tagName.toLowerCase(),text:btn.textContent?.trim()||btn.value||'',disabled:btn.disabled}:null};}),formCount:forms.length};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun findElement(body: Map<String, Any?>): Map<String, Any?> {
        val text = body["text"] as? String ?: return errorResponse("MISSING_PARAM", "text is required")
        return findByText(text, "true")
    }

    private suspend fun findButton(body: Map<String, Any?>): Map<String, Any?> {
        val text = body["text"] as? String ?: return errorResponse("MISSING_PARAM", "text is required")
        return findByText(text, "['BUTTON','A','INPUT'].includes(el.tagName)||el.getAttribute('role')==='button'")
    }

    private suspend fun findLink(body: Map<String, Any?>): Map<String, Any?> {
        val text = body["text"] as? String ?: return errorResponse("MISSING_PARAM", "text is required")
        return findByText(text, "el.tagName==='A'||el.getAttribute('role')==='link'")
    }

    private suspend fun findByText(text: String, filter: String): Map<String, Any?> {
        val safe = text.lowercase().replace("'", "\\'")
        val js = "(function(){var all=document.querySelectorAll('*');for(var el of all){if(!($filter))continue;var t=(el.textContent||'').trim();if(t.toLowerCase().includes('$safe')){var r=el.getBoundingClientRect();if(r.width>0&&r.height>0)return{found:true,element:{tag:el.tagName.toLowerCase(),text:t.substring(0,100),selector:el.tagName.toLowerCase()+(el.id?'#'+el.id:''),rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};}}return{found:false};})()"
        return try {
            ctx.evaluateJSReturningJSON(js)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun findInput(body: Map<String, Any?>): Map<String, Any?> {
        val label = body["label"] as? String ?: ""
        val safe = label.lowercase().replace("'", "\\'")
        val js = "(function(){var inputs=document.querySelectorAll('input,select,textarea');for(var el of inputs){var lbl=el.getAttribute('aria-label')||el.placeholder||el.name||'';if(lbl.toLowerCase().includes('$safe')){var r=el.getBoundingClientRect();return{found:true,element:{tag:el.tagName.toLowerCase(),type:el.type||'text',name:el.name||'',selector:el.tagName.toLowerCase()+(el.name?'[name=\"'+el.name+'\"]':''),rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};}}return{found:false};})()"
        return try {
            ctx.evaluateJSReturningJSON(js)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun screenshotAnnotated(): Map<String, Any?> {
        val js = "(function(){var els=document.querySelectorAll('a,button,input,select,textarea,[role=button]');return Array.from(els).slice(0,50).map(function(el,i){var r=el.getBoundingClientRect();if(r.width<=0||r.height<=0)return null;return{index:i,role:el.getAttribute('role')||el.tagName.toLowerCase(),name:(el.textContent||el.value||el.placeholder||'').trim().substring(0,50),selector:el.tagName.toLowerCase()+(el.id?'#'+el.id:''),rect:{x:r.x,y:r.y,width:r.width,height:r.height}};}).filter(Boolean);})()"
        return try {
            val annotations = ctx.evaluateJSReturningArray(js)
            successResponse(mapOf("annotations" to annotations, "count" to annotations.size))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun clickAnnotation(body: Map<String, Any?>): Map<String, Any?> {
        val index = (body["index"] as? Int) ?: return errorResponse("MISSING_PARAM", "index is required")
        val js = "(function(){var els=document.querySelectorAll('a,button,input,select,textarea,[role=button]');var el=Array.from(els).filter(function(e){var r=e.getBoundingClientRect();return r.width>0&&r.height>0;})[$index];if(!el)return null;el.scrollIntoView({block:'center'});el.click();return{role:el.getAttribute('role')||el.tagName.toLowerCase(),name:(el.textContent||'').trim().substring(0,50)};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "Annotation index $index not found") else successResponse(mapOf("element" to result))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun fillAnnotation(body: Map<String, Any?>): Map<String, Any?> {
        val index = (body["index"] as? Int) ?: return errorResponse("MISSING_PARAM", "index is required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value is required")
        val safeVal = value.replace("'", "\\'")
        val js = "(function(){var els=document.querySelectorAll('input,select,textarea');var el=Array.from(els).filter(function(e){var r=e.getBoundingClientRect();return r.width>0&&r.height>0;})[$index];if(!el)return null;el.focus();el.value='$safeVal';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return{role:el.getAttribute('role')||el.tagName.toLowerCase(),name:(el.placeholder||el.name||'').trim()};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "Annotation index $index not found") else successResponse(mapOf("element" to result, "value" to value))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun queryShadowDOM(body: Map<String, Any?>): Map<String, Any?> {
        val hostSelector = body["hostSelector"] as? String ?: return errorResponse("MISSING_PARAM", "hostSelector is required")
        val shadowSelector = body["shadowSelector"] as? String ?: "*"
        val pierce = body["pierce"] as? Boolean ?: true
        val safeHost = hostSelector.replace("'", "\\'")
        val safeShadow = shadowSelector.replace("'", "\\'")
        val js = "(function(){function f(h,s,r){if(!h||!h.shadowRoot)return null;var el=h.shadowRoot.querySelector(s);if(el)return el;if(r){var a=h.shadowRoot.querySelectorAll('*');for(var i=0;i<a.length;i++){if(a[i].shadowRoot){var found=f(a[i],s,true);if(found)return found;}}}return null;}var host=document.querySelector('$safeHost');if(!host)return{found:false,error:'Host not found'};var el=f(host,'$safeShadow',$pierce);if(!el)return{found:false};var r=el.getBoundingClientRect();var tag=el.tagName.toLowerCase();return{found:true,element:{tag:tag,text:(el.textContent||'').trim().substring(0,100),shadowHost:'$safeHost',rect:{x:r.x,y:r.y,width:r.width,height:r.height},visible:r.width>0&&r.height>0,interactable:['a','button','input','select','textarea'].includes(tag)}};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getShadowRoots(): Map<String, Any?> {
        val js = "(function(){var hosts=[];var all=document.querySelectorAll('*');for(var i=0;i<all.length;i++){var el=all[i];if(el.shadowRoot){var tag=el.tagName.toLowerCase();hosts.push({selector:tag+(el.id?'#'+el.id:''),tag:tag,mode:'open',childCount:el.shadowRoot.childElementCount});}}return{hosts:hosts,count:hosts.length};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}
