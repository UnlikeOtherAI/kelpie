import WebKit

// swiftlint:disable line_length

/// Handles LLM-optimized endpoints: accessibility, find, visible, pageText, formState.
struct LLMHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-accessibility-tree") { body in await getAccessibilityTree(body) }
        router.register("get-visible-elements") { body in await getVisibleElements(body) }
        router.register("get-page-text") { body in await getPageText(body) }
        router.register("get-form-state") { body in await getFormState(body) }
        router.register("find-element") { body in await findElement(body) }
        router.register("find-button") { body in await findButton(body) }
        router.register("find-link") { body in await findLink(body) }
        router.register("find-input") { body in await findInput(body) }
        router.register("screenshot-annotated") { body in await screenshotAnnotated(body) }
        router.register("click-annotation") { body in await clickAnnotation(body) }
        router.register("fill-annotation") { body in await fillAnnotation(body) }
    }

    @MainActor
    private func getAccessibilityTree(_ body: [String: Any]) async -> [String: Any] {
        let root = body["root"] as? String ?? "body"
        let maxDepth = body["maxDepth"] as? Int ?? 5
        let js = """
        (function(){function walk(el,depth){if(depth>"\(maxDepth)")return null;var role=el.getAttribute('role')||el.tagName.toLowerCase();var name=el.getAttribute('aria-label')||el.textContent?.trim().substring(0,50)||'';var node={role:role,name:name};if(el.getAttribute('aria-checked'))node.checked=el.getAttribute('aria-checked')==='true';if(el.disabled)node.disabled=true;if(document.activeElement===el)node.focused=true;var children=[];for(var c of el.children){var cn=walk(c,depth+1);if(cn)children.push(cn);}if(children.length)node.children=children;return node;}var root=document.querySelector('\(JSEscape.string(root))');if(!root)return{tree:{role:'none'},nodeCount:0};var tree=walk(root,0);var count=root.querySelectorAll('*').length;return{tree:tree,nodeCount:count};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getVisibleElements(_ body: [String: Any]) async -> [String: Any] {
        let interactableOnly = body["interactableOnly"] as? Bool ?? false
        let js = """
        (function(){var els=document.querySelectorAll('*');var visible=[];for(var el of els){var r=el.getBoundingClientRect();if(r.width>0&&r.height>0&&r.top<window.innerHeight&&r.bottom>0&&r.left<window.innerWidth&&r.right>0){var tag=el.tagName.toLowerCase();if(\(interactableOnly)&&!['a','button','input','select','textarea'].includes(tag)&&!el.onclick&&el.getAttribute('role')!=='button')continue;visible.push({tag:tag,text:(el.textContent||'').trim().substring(0,100),rect:{x:r.x,y:r.y,width:r.width,height:r.height},role:el.getAttribute('role')||undefined,interactable:['a','button','input','select','textarea'].includes(tag)});if(visible.length>=200)break;}}return{viewport:{width:window.innerWidth,height:window.innerHeight,scrollX:window.scrollX,scrollY:window.scrollY},elements:visible,count:visible.length};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getPageText(_ body: [String: Any]) async -> [String: Any] {
        let selector = body["selector"] as? String ?? "body"
        let js = """
        (function(){var el=document.querySelector('\(JSEscape.string(selector))');if(!el)return{title:'',content:'',wordCount:0};var text=el.innerText||el.textContent||'';return{title:document.title,byline:null,content:text.trim(),wordCount:text.trim().split(/\\s+/).length,language:document.documentElement.lang||null,excerpt:text.trim().substring(0,200)};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getFormState(_ body: [String: Any]) async -> [String: Any] {
        let js = """
        (function(){var forms=document.querySelectorAll('form');if(!forms.length)return{forms:[],formCount:0};return{forms:Array.from(forms).map(function(f,i){var fields=Array.from(f.querySelectorAll('input,select,textarea')).map(function(el){return{name:el.name||'',type:el.type||'text',selector:el.tagName.toLowerCase()+(el.name?'[name=\"'+el.name+'\"]':''),label:null,value:el.value||'',required:el.required,valid:el.checkValidity(),disabled:el.disabled};});var btn=f.querySelector('button[type=submit],input[type=submit]');return{selector:'form:nth-of-type('+(i+1)+')',action:f.action||'',method:f.method||'get',fields:fields,isValid:f.checkValidity(),emptyRequired:fields.filter(function(fl){return fl.required&&!fl.value;}).map(function(fl){return fl.name;}),submitButton:btn?{selector:btn.tagName.toLowerCase(),text:btn.textContent?.trim()||btn.value||'',disabled:btn.disabled}:null};}),formCount:forms.length};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func findElement(_ body: [String: Any]) async -> [String: Any] {
        guard let text = body["text"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "text is required")
        }
        return await findByText(text, filter: "true")
    }

    @MainActor
    private func findButton(_ body: [String: Any]) async -> [String: Any] {
        guard let text = body["text"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "text is required")
        }
        return await findByText(text, filter: "['BUTTON','A','INPUT'].includes(el.tagName)||el.getAttribute('role')==='button'")
    }

    @MainActor
    private func findLink(_ body: [String: Any]) async -> [String: Any] {
        guard let text = body["text"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "text is required")
        }
        return await findByText(text, filter: "el.tagName==='A'||el.getAttribute('role')==='link'")
    }

    @MainActor
    private func findInput(_ body: [String: Any]) async -> [String: Any] {
        let label = body["label"] as? String ?? ""
        let js = """
        (function(){var inputs=document.querySelectorAll('input,select,textarea');for(var el of inputs){var lbl=el.getAttribute('aria-label')||el.placeholder||el.name||'';if(lbl.toLowerCase().includes('\(JSEscape.string(label.lowercased()))')){var r=el.getBoundingClientRect();return{found:true,element:{tag:el.tagName.toLowerCase(),type:el.type||'text',name:el.name||'',selector:el.tagName.toLowerCase()+(el.name?'[name=\"'+el.name+'\"]':''),rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};}}return{found:false};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return result
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func findByText(_ text: String, filter: String) async -> [String: Any] {
        let js = """
        (function(){var all=document.querySelectorAll('*');for(var el of all){if(!(\(filter)))continue;var t=(el.textContent||'').trim();if(t.toLowerCase().includes('\(JSEscape.string(text.lowercased()))')){var r=el.getBoundingClientRect();if(r.width>0&&r.height>0)return{found:true,element:{tag:el.tagName.toLowerCase(),text:t.substring(0,100),selector:el.tagName.toLowerCase()+(el.id?'#'+el.id:''),rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};}}return{found:false};})()
        """
        do {
            return try await context.evaluateJSReturningJSON(js)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    // MARK: - Annotated Screenshots (stub — full impl needs canvas overlay)

    @MainActor
    private func screenshotAnnotated(_ body: [String: Any]) async -> [String: Any] {
        // Basic implementation: take screenshot + list annotations
        guard let webView = context.webView else {
            return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
        }
        let js = """
        (function(){var els=document.querySelectorAll('a,button,input,select,textarea,[role=button]');return Array.from(els).slice(0,50).map(function(el,i){var r=el.getBoundingClientRect();if(r.width<=0||r.height<=0)return null;return{index:i,role:el.getAttribute('role')||el.tagName.toLowerCase(),name:(el.textContent||el.value||el.placeholder||'').trim().substring(0,50),selector:el.tagName.toLowerCase()+(el.id?'#'+el.id:''),rect:{x:r.x,y:r.y,width:r.width,height:r.height}};}).filter(Boolean);})()
        """
        do {
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            let image = try await webView.takeSnapshot(configuration: config)
            let imageData = image.pngData() ?? Data()
            let annotationsJSON = try await context.evaluateJSReturningString("JSON.stringify(\(js))")
            let annotations = (try? JSONSerialization.jsonObject(with: Data(annotationsJSON.utf8))) as? [[String: Any]] ?? []
            return successResponse([
                "image": imageData.base64EncodedString(),
                "width": Int(image.size.width * image.scale),
                "height": Int(image.size.height * image.scale),
                "format": "png",
                "annotations": annotations
            ])
        } catch {
            return errorResponse(code: "SCREENSHOT_FAILED", message: error.localizedDescription)
        }
    }

    @MainActor
    private func clickAnnotation(_ body: [String: Any]) async -> [String: Any] {
        guard let index = body["index"] as? Int else {
            return errorResponse(code: "MISSING_PARAM", message: "index is required")
        }
        let js = """
        (function(){var els=document.querySelectorAll('a,button,input,select,textarea,[role=button]');var el=Array.from(els).filter(function(e){var r=e.getBoundingClientRect();return r.width>0&&r.height>0;})[\(index)];if(!el)return null;el.scrollIntoView({block:'center'});el.click();return{role:el.getAttribute('role')||el.tagName.toLowerCase(),name:(el.textContent||'').trim().substring(0,50),selector:el.tagName.toLowerCase()+(el.id?'#'+el.id:'')};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Annotation index \(index) not found") }
            return successResponse(["element": result])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func fillAnnotation(_ body: [String: Any]) async -> [String: Any] {
        guard let index = body["index"] as? Int, let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "index and value are required")
        }
        let js = """
        (function(){var els=document.querySelectorAll('input,select,textarea');var el=Array.from(els).filter(function(e){var r=e.getBoundingClientRect();return r.width>0&&r.height>0;})[\(index)];if(!el)return null;el.focus();el.value='\(JSEscape.string(value))';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return{role:el.getAttribute('role')||el.tagName.toLowerCase(),name:(el.placeholder||el.name||'').trim(),selector:el.tagName.toLowerCase()+(el.id?'#'+el.id:'')};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Annotation index \(index) not found") }
            return successResponse(["element": result, "value": value])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }
}
