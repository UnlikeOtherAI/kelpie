package com.kelpie.browser.llm

import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.JSEscape
import com.kelpie.browser.handlers.ScreenshotResolution
import com.kelpie.browser.handlers.annotationActivationScript
import com.kelpie.browser.handlers.annotationElementsScript
import com.kelpie.browser.handlers.elementSelectorBuilderScript
import com.kelpie.browser.handlers.fillAnnotationScript
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import java.util.UUID

class LLMHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("get-accessibility-tree") { getAccessibilityTree(it) }
        router.register("get-visible-elements") { getVisibleElements(it) }
        router.register("get-page-text") { getPageText(it) }
        router.register("get-form-state") { getFormState() }
        router.register("find-element") { findElement(it) }
        router.register("find-button") { findButton(it) }
        router.register("find-link") { findLink(it) }
        router.register("find-input") { findInput(it) }
        router.register("screenshot-annotated") { screenshotAnnotated(it) }
        router.register("click-annotation") { clickAnnotation(it) }
        router.register("fill-annotation") { fillAnnotation(it) }
    }

    private suspend fun getAccessibilityTree(body: Map<String, Any?>): Map<String, Any?> {
        val root = body["root"] as? String ?: "body"
        val maxDepth = (body["maxDepth"] as? Int) ?: 5
        val safe = JSEscape.string(root)
        val js =
            "(function(){function walk(el,d){if(d>$maxDepth)return null;" +
                "var role=el.getAttribute('role')||el.tagName.toLowerCase();" +
                "var name=el.getAttribute('aria-label')||" +
                "el.textContent?.trim().substring(0,50)||'';" +
                "var node={role:role,name:name};" +
                "if(el.getAttribute('aria-checked'))" +
                "node.checked=el.getAttribute('aria-checked')==='true';" +
                "if(el.disabled)node.disabled=true;" +
                "if(document.activeElement===el)node.focused=true;" +
                "var ch=[];for(var c of el.children)" +
                "{var cn=walk(c,d+1);if(cn)ch.push(cn);}" +
                "if(ch.length)node.children=ch;return node;}" +
                "var r=document.querySelector('$safe');" +
                "if(!r)return{tree:{role:'none'},nodeCount:0};" +
                "return{tree:walk(r,0),nodeCount:r.querySelectorAll('*').length};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getVisibleElements(body: Map<String, Any?>): Map<String, Any?> {
        val interactableOnly = body["interactableOnly"] as? Boolean ?: false
        val js =
            "(function(){var els=document.querySelectorAll('*');var visible=[];" +
                "for(var el of els){var r=el.getBoundingClientRect();" +
                "if(r.width>0&&r.height>0&&r.top<window.innerHeight&&" +
                "r.bottom>0&&r.left<window.innerWidth&&r.right>0){" +
                "var tag=el.tagName.toLowerCase();" +
                "if($interactableOnly&&" +
                "!['a','button','input','select','textarea'].includes(tag)&&" +
                "!el.onclick&&el.getAttribute('role')!=='button')continue;" +
                "visible.push({tag:tag," +
                "text:(el.textContent||'').trim().substring(0,100)," +
                "rect:{x:r.x,y:r.y,width:r.width,height:r.height}," +
                "role:el.getAttribute('role')||undefined," +
                "interactable:['a','button','input','select','textarea']" +
                ".includes(tag)});if(visible.length>=200)break;}}" +
                "return{viewport:{width:window.innerWidth," +
                "height:window.innerHeight,scrollX:window.scrollX," +
                "scrollY:window.scrollY},elements:visible,count:visible.length};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getPageText(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: "body"
        val safe = JSEscape.string(selector)
        val js =
            "(function(){var el=document.querySelector('$safe');" +
                "if(!el)return{title:'',content:'',wordCount:0};" +
                "var t=el.innerText||el.textContent||'';" +
                "return{title:document.title,content:t.trim()," +
                "wordCount:t.trim().split(/\\s+/).length," +
                "language:document.documentElement.lang||null," +
                "excerpt:t.trim().substring(0,200)};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getFormState(): Map<String, Any?> {
        val js =
            "(function(){" + elementSelectorBuilderScript() + "var forms=document.querySelectorAll('form');" +
                "if(!forms.length)return{forms:[],formCount:0};" +
                "return{forms:Array.from(forms).map(function(f){" +
                "var fields=Array.from(f.querySelectorAll('input,select,textarea'))" +
                ".map(function(el){return{name:el.name||'',type:el.type||'text'," +
                "selector:kelpieBuildSelector(el)," +
                "value:el.value||'',required:el.required," +
                "valid:el.checkValidity(),disabled:el.disabled};});" +
                "var btn=f.querySelector('button[type=submit],input[type=submit]');" +
                "return{selector:kelpieBuildSelector(f)," +
                "action:f.action||'',method:f.method||'get',fields:fields," +
                "isValid:f.checkValidity()," +
                "emptyRequired:fields.filter(function(fl){" +
                "return fl.required&&!fl.value;}).map(function(fl){return fl.name;})," +
                "submitButton:btn?{selector:kelpieBuildSelector(btn)," +
                "text:btn.textContent?.trim()||btn.value||''," +
                "disabled:btn.disabled}:null};}),formCount:forms.length};})()"
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

    private suspend fun findByText(
        text: String,
        filter: String,
    ): Map<String, Any?> {
        val safe = JSEscape.string(text.lowercase())
        val js =
            "(function(){" + elementSelectorBuilderScript() + "var all=document.querySelectorAll('*');" +
                "for(var el of all){if(!($filter))continue;" +
                "var t=(el.textContent||'').trim();" +
                "if(t.toLowerCase().includes('$safe')){" +
                "var r=el.getBoundingClientRect();" +
                "if(r.width>0&&r.height>0)return{found:true,element:{" +
                "tag:el.tagName.toLowerCase(),text:t.substring(0,100)," +
                "selector:kelpieBuildSelector(el)," +
                "rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};}}return{found:false};})()"
        return try {
            ctx.evaluateJSReturningJSON(js)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun findInput(body: Map<String, Any?>): Map<String, Any?> {
        val label = body["label"] as? String ?: ""
        val safe = JSEscape.string(label.lowercase())
        val js =
            "(function(){" + elementSelectorBuilderScript() + "var inputs=document.querySelectorAll('input,select,textarea');" +
                "for(var el of inputs){" +
                "var lbl=el.getAttribute('aria-label')||el.placeholder||el.name||'';" +
                "if(lbl.toLowerCase().includes('$safe')){" +
                "var r=el.getBoundingClientRect();" +
                "return{found:true,element:{tag:el.tagName.toLowerCase()," +
                "type:el.type||'text',name:el.name||''," +
                "selector:kelpieBuildSelector(el)," +
                "rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};}}return{found:false};})()"
        return try {
            ctx.evaluateJSReturningJSON(js)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun screenshotAnnotated(body: Map<String, Any?>): Map<String, Any?> {
        val format = body["format"] as? String ?: "png"
        val resolution =
            ScreenshotResolution.parse(body["resolution"] ?: "viewport")
                ?: return errorResponse("INVALID_PARAMS", "resolution must be 'native' or 'viewport'")
        return try {
            val annotations = ctx.evaluateJSReturningArray(annotationElementsScript())
            val payload =
                ctx.captureScreenshotPayload(format = format, resolution = resolution)
                    ?: return errorResponse("SCREENSHOT_FAILED", "Failed to capture annotated screenshot")
            val sessionId = UUID.randomUUID().toString().lowercase()
            ctx.annotationSessionId = sessionId
            ctx.annotationPageURL = ctx.webView?.url
            ctx.annotationElementCount = annotations.size
            successResponse(
                payload +
                    mapOf(
                        "annotations" to annotations,
                        "annotationSessionId" to sessionId,
                        "validUntil" to "next_navigation",
                        "hint" to "Annotations are valid until the page URL changes. Take a fresh screenshot-annotated if you navigate.",
                    ),
            )
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun clickAnnotation(body: Map<String, Any?>): Map<String, Any?> {
        val index = (body["index"] as? Int) ?: return errorResponse("MISSING_PARAM", "index is required")
        annotationExpiredError()?.let { return it }
        return try {
            val result = ctx.evaluateJSReturningJSON(annotationActivationScript(index))
            val diagnostics = result["diagnostics"] as? Map<String, Any?>
            when (result["error"]) {
                "not_found" -> errorResponse("ELEMENT_NOT_FOUND", "Annotation index $index not found", diagnostics)
                "not_visible" -> errorResponse("ELEMENT_NOT_VISIBLE", "Annotated element $index is not visible or is obscured", diagnostics)
                null -> successResponse(mapOf("element" to result))
                else -> errorResponse("ELEMENT_NOT_FOUND", "Annotation index $index not found", diagnostics)
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun fillAnnotation(body: Map<String, Any?>): Map<String, Any?> {
        val index = (body["index"] as? Int) ?: return errorResponse("MISSING_PARAM", "index is required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value is required")
        annotationExpiredError()?.let { return it }
        return try {
            val result = ctx.evaluateJSReturningJSON(fillAnnotationScript(index, value))
            val diagnostics = result["diagnostics"] as? Map<String, Any?>
            when (result["error"]) {
                "not_found" -> errorResponse("ELEMENT_NOT_FOUND", "Annotation index $index not found", diagnostics)
                "not_editable" -> errorResponse("INVALID_PARAMS", "Annotated element $index is not an editable form control", diagnostics)
                null -> successResponse(mapOf("element" to result, "value" to value))
                else -> errorResponse("ELEMENT_NOT_FOUND", "Annotation index $index not found", diagnostics)
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private fun annotationExpiredError(): Map<String, Any?>? {
        val annotationPageURL = ctx.annotationPageURL ?: return null
        val currentPageURL = ctx.webView?.url
        if (currentPageURL == annotationPageURL) return null
        return errorResponse(
            "ANNOTATION_EXPIRED",
            "Annotations expired because the page URL changed. Take a fresh screenshot-annotated before interacting again.",
            mapOf("annotationSessionId" to (ctx.annotationSessionId ?: "")),
        )
    }
}
