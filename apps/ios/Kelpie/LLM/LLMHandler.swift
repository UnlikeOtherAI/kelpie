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
        router.register("query-shadow-dom") { body in await queryShadowDOM(body) }
        router.register("get-shadow-roots") { _ in await getShadowRoots() }
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
        (function(){\(elementSelectorBuilderScript())var forms=document.querySelectorAll('form');if(!forms.length)return{forms:[],formCount:0};return{forms:Array.from(forms).map(function(f){var fields=Array.from(f.querySelectorAll('input,select,textarea')).map(function(el){return{name:el.name||'',type:el.type||'text',selector:kelpieBuildSelector(el),label:null,value:el.value||'',required:el.required,valid:el.checkValidity(),disabled:el.disabled};});var btn=f.querySelector('button[type=submit],input[type=submit]');return{selector:kelpieBuildSelector(f),action:f.action||'',method:f.method||'get',fields:fields,isValid:f.checkValidity(),emptyRequired:fields.filter(function(fl){return fl.required&&!fl.value;}).map(function(fl){return fl.name;}),submitButton:btn?{selector:kelpieBuildSelector(btn),text:btn.textContent?.trim()||btn.value||'',disabled:btn.disabled}:null};}),formCount:forms.length};})()
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
        (function(){\(elementSelectorBuilderScript())var inputs=document.querySelectorAll('input,select,textarea');for(var el of inputs){var lbl=el.getAttribute('aria-label')||el.placeholder||el.name||'';if(lbl.toLowerCase().includes('\(JSEscape.string(label.lowercased()))')){var r=el.getBoundingClientRect();return{found:true,element:{tag:el.tagName.toLowerCase(),type:el.type||'text',name:el.name||'',selector:kelpieBuildSelector(el),rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};}}return{found:false};})()
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
        (function(){\(elementSelectorBuilderScript())var all=document.querySelectorAll('*');for(var el of all){if(!(\(filter)))continue;var t=(el.textContent||'').trim();if(t.toLowerCase().includes('\(JSEscape.string(text.lowercased()))')){var r=el.getBoundingClientRect();if(r.width>0&&r.height>0)return{found:true,element:{tag:el.tagName.toLowerCase(),text:t.substring(0,100),selector:kelpieBuildSelector(el),rect:{x:r.x,y:r.y,width:r.width,height:r.height}}};}}return{found:false};})()
        """
        do {
            return try await context.evaluateJSReturningJSON(js)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    // MARK: - Annotated Screenshots

    @MainActor
    private func screenshotAnnotated(_ body: [String: Any]) async -> [String: Any] {
        guard let webView = context.webView else {
            return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
        }
        guard let resolution = ScreenshotResolution.parse(body["resolution"] ?? "viewport") else {
            return errorResponse(code: "INVALID_PARAMS", message: "resolution must be 'native' or 'viewport'")
        }
        do {
            let annotations = try await context.evaluateJSReturningArray(annotationElementsScript())
            // Reuse the regular screenshot handler's scroll-and-stitch capture so
            // the annotated full-page image spans the whole document, not just the
            // viewport. `WKWebView.takeSnapshot` clips to the visible bounds.
            let fullPage = body["fullPage"] as? Bool ?? false
            let image: UIImage
            var fullPageContentHeight: Int?
            if fullPage {
                let capture = try await ScreenshotHandler(context: context).captureFullPage(webView: webView)
                image = capture.image
                fullPageContentHeight = capture.contentHeightCss
            } else {
                let config = WKSnapshotConfiguration()
                config.rect = webView.bounds
                image = try await webView.takeSnapshot(configuration: config)
            }
            var payload = try await context.screenshotPayload(
                from: image,
                format: body["format"] as? String ?? "png",
                quality: ((body["quality"] as? NSNumber)?.doubleValue ?? 80) / 100.0,
                resolution: resolution
            )
            if let contentHeight = fullPageContentHeight {
                applyFullPageMetadata(to: &payload, contentHeightCss: contentHeight)
            }
            let sessionId = UUID().uuidString.lowercased()
            context.annotationSessionId = sessionId
            context.annotationPageURL = context.webView?.url?.absoluteString
            context.annotationElementCount = annotations.count
            payload["annotations"] = annotations
            payload["annotationSessionId"] = sessionId
            payload["validUntil"] = "next_navigation"
            payload["hint"] = "Annotations are valid until the page URL changes. Take a fresh screenshot-annotated if you navigate."
            return successResponse(payload)
        } catch {
            return errorResponse(code: "SCREENSHOT_FAILED", message: error.localizedDescription)
        }
    }

    @MainActor
    private func clickAnnotation(_ body: [String: Any]) async -> [String: Any] {
        guard let index = body["index"] as? Int else {
            return errorResponse(code: "MISSING_PARAM", message: "index is required")
        }
        if let expired = annotationExpiredError() {
            return expired
        }
        do {
            let result = try await context.evaluateJSReturningJSON(annotationActivationScript(index: index))
            let diagnostics = result["diagnostics"] as? [String: Any]
            if result.isEmpty || result["error"] as? String == "not_found" {
                return errorResponse(
                    code: "ELEMENT_NOT_FOUND",
                    message: "Annotation index \(index) not found",
                    diagnostics: diagnostics
                )
            }
            if result["error"] as? String == "not_visible" {
                return errorResponse(
                    code: "ELEMENT_NOT_VISIBLE",
                    message: "Annotated element \(index) is not visible or is obscured",
                    diagnostics: diagnostics
                )
            }
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
        if let expired = annotationExpiredError() {
            return expired
        }
        do {
            let result = try await context.evaluateJSReturningJSON(fillAnnotationScript(index: index, value: value))
            let diagnostics = result["diagnostics"] as? [String: Any]
            if result.isEmpty || result["error"] as? String == "not_found" {
                return errorResponse(
                    code: "ELEMENT_NOT_FOUND",
                    message: "Annotation index \(index) not found",
                    diagnostics: diagnostics
                )
            }
            if result["error"] as? String == "not_editable" {
                return errorResponse(
                    code: "INVALID_PARAMS",
                    message: "Annotated element \(index) is not an editable form control",
                    diagnostics: diagnostics
                )
            }
            return successResponse(["element": result, "value": value])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func queryShadowDOM(_ body: [String: Any]) async -> [String: Any] {
        guard let hostSelector = body["hostSelector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "hostSelector is required")
        }
        let shadowSelector = body["shadowSelector"] as? String ?? "*"
        let pierce = body["pierce"] as? Bool ?? true
        let js = """
        (function(){function f(h,s,r){if(!h||!h.shadowRoot)return null;var el=h.shadowRoot.querySelector(s);if(el)return el;if(r){var a=h.shadowRoot.querySelectorAll('*');for(var i=0;i<a.length;i++){if(a[i].shadowRoot){var found=f(a[i],s,true);if(found)return found;}}}return null;}var host=document.querySelector('\(JSEscape.string(hostSelector))');if(!host)return{found:false,error:'Host not found'};var el=f(host,'\(JSEscape.string(shadowSelector))',\(pierce ? "true" : "false"));if(!el)return{found:false};var r=el.getBoundingClientRect();var tag=el.tagName.toLowerCase();return{found:true,element:{tag:tag,text:(el.textContent||'').trim().substring(0,100),shadowHost:'\(JSEscape.string(hostSelector))',rect:{x:r.x,y:r.y,width:r.width,height:r.height},visible:r.width>0&&r.height>0,interactable:['a','button','input','select','textarea'].includes(tag)}};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getShadowRoots() async -> [String: Any] {
        let js = """
        (function(){\(elementSelectorBuilderScript())var hosts=[];var all=document.querySelectorAll('*');for(var i=0;i<all.length;i++){var el=all[i];if(el.shadowRoot){var tag=el.tagName.toLowerCase();hosts.push({selector:kelpieBuildSelector(el),tag:tag,mode:'open',childCount:el.shadowRoot.childElementCount});}}return{hosts:hosts,count:hosts.length};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func annotationExpiredError() -> [String: Any]? {
        guard let annotationPageURL = context.annotationPageURL else { return nil }
        let currentPageURL = context.webView?.url?.absoluteString
        guard currentPageURL != annotationPageURL else { return nil }
        return errorResponse(
            code: "ANNOTATION_EXPIRED",
            message: "Annotations expired because the page URL changed. Take a fresh screenshot-annotated before interacting again.",
            diagnostics: ["annotationSessionId": context.annotationSessionId ?? ""]
        )
    }
}
