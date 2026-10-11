import Foundation

private let accountControlMethods: Set<String> = [
    "capabilities", "documentation", "tabs.list", "tabs.new", "tabs.select", "tabs.close",
    "tab.snapshot", "tab.screenshot", "tab.goto", "tab.click", "tab.type", "page.scroll"
]

@MainActor
extension ConnectBrowser {
    func executeControl(_ command: [String: Any], input: [String: Any]) async -> [String: Any] {
        guard let request = input["request"] as? [String: Any],
              let method = request["method"] as? String,
              let owner = context.browserRouter else { return envelope(failure("INVALID_ARGUMENTS")) }
        guard accountControlMethods.contains(method) else { return envelope(failure("UNSUPPORTED")) }
        if ["tabs.new", "tab.goto"].contains(method), isAccountDestination(request["params"] as? [String: Any]) {
            return envelope(failure("ACCOUNT_SURFACE_FORBIDDEN"))
        }
        let unbound = ["capabilities", "documentation", "tabs.list", "tabs.new"].contains(method)
        let tabID = command["tabId"] as? String
        let expected = command["tabVersion"] as? String
        guard validatePin(unbound: unbound, request: request, method: method, tabID: tabID, expected: expected) else {
            return envelope(failure(unbound ? "TAB_PIN_MISMATCH" : pinFailure(tabID: tabID, expected: expected)))
        }
        let deadline = ConnectAuthorization(command)?.deadline
        let durableAuthorization = { deadline.map { $0 > Date() } == true && NessieConnection.shared.authorizes(command) }
        let authorize: BrowserControlGateway.Authorize = { [weak self] _, _ in
            guard let self, !Task.isCancelled, durableAuthorization() else { return false }
            guard let tabID, let expected else { return unbound }
            return self.versionMatches(tabID, expected: expected)
                && !self.accountSurface(tabID)
                && (method == "tabs.select" || self.isActive(tabID))
        }
        guard let dispatch = accountDispatcher(
            unbound: unbound,
            owner: owner,
            command: command,
            method: method,
            tabID: tabID,
            expected: expected,
            durableAuthorization: durableAuthorization
        ) else { return envelope(failure("TAB_NOT_FOUND")) }
        let response: [String: Any]
        if method == "tabs.select" || method == "tabs.new" {
            response = await NessieConnection.shared.changeTabRemotely {
                await owner.browserControl(request, authorizeAccountStep: authorize, dispatchAccountStep: dispatch)
            }
            claimSelectedTab(method: method, tabID: tabID, response: response)
        } else {
            response = await owner.browserControl(request, authorizeAccountStep: authorize, dispatchAccountStep: dispatch)
        }
        return project(response, method: method, tabID: tabID, expected: expected)
    }

    private func validatePin(
        unbound: Bool,
        request: [String: Any],
        method: String,
        tabID: String?,
        expected: String?
    ) -> Bool {
        if unbound { return tabID == nil && expected == nil }
        guard let tabID, let expected, request["tabId"] as? String == tabID else { return false }
        return versionMatches(tabID, expected: expected) && !accountSurface(tabID)
            && (method == "tabs.select" || isActive(tabID))
    }

    private func pinFailure(tabID: String?, expected: String?) -> String {
        guard let tabID, let expected else { return "TAB_PIN_MISMATCH" }
        return versionMatches(tabID, expected: expected) ? "TAB_NOT_ACTIVE" : "STALE_DOCUMENT"
    }

    private func versionMatches(_ tabID: String, expected: String) -> Bool {
        (try? version(tabID)) == expected
    }

    private func accountSurface(_ tabID: String) -> Bool {
        guard let url = tabs().first(where: { $0["tabId"] as? String == tabID })?["url"] as? String else { return false }
        return isAccountURL(url)
    }

    private func isActive(_ tabID: String) -> Bool {
        tabs().first(where: { $0["tabId"] as? String == tabID })?["active"] as? Bool == true
    }

    private func isAccountDestination(_ params: [String: Any]?) -> Bool {
        guard let url = params?["url"] as? String else { return false }
        return isAccountURL(url)
    }

    private func isAccountURL(_ url: String) -> Bool {
        URLComponents(string: url)?.host?.lowercased() == "authentication.unlikeotherai.com"
    }

    private func accountDispatcher(
        unbound: Bool,
        owner: Router,
        command: [String: Any],
        method: String,
        tabID: String?,
        expected: String?,
        durableAuthorization: @escaping () -> Bool
    ) -> BrowserControlGateway.Dispatch? {
        if unbound {
            return { step, params, mutates in
                guard durableAuthorization() else { return errorResponse(code: "ACCESS_DENIED", message: "The account job expired") }
                if mutates { owner.invalidateAllBrowserReferences() }
                return await owner.browserDispatch(method: step, params: params, pinnedTabId: nil)
            }
        }
        guard let tabID, let expected,
              let job = try? ConnectBrowserControlJob(
                source: context,
                owner: owner,
                command: command,
                tabID: tabID,
                expectedVersion: expected,
                authorized: durableAuthorization
              ) else { return nil }
        return { step, params, mutates in await job.dispatch(method: step, params: params, mutates: mutates) }
    }

    private func claimSelectedTab(method: String, tabID: String?, response: [String: Any]) {
        guard response["ok"] as? Bool == true else { return }
        let value = response["value"] as? [String: Any]
        let claimed = method == "tabs.select" ? tabID : value?["id"] as? String
        if let claimed { NessieConnection.shared.claimTab(claimed) }
    }

    private func project(_ response: [String: Any], method: String, tabID: String?, expected: String?) -> [String: Any] {
        var projected = response
        if method == "capabilities", response["ok"] as? Bool == true, var value = response["value"] as? [String: Any] {
            value["extensions"] = [String]()
            value["methods"] = (value["methods"] as? [String] ?? []).filter { accountControlMethods.contains($0) }
            projected["value"] = value
        }
        var result: [String: Any] = ["response": projected]
        if method == "tabs.list", response["ok"] as? Bool == true {
            let listed = Set((response["value"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
            result["tabs"] = tabs().filter { listed.contains($0["tabId"] as? String ?? "") }.compactMap { tab -> [String: String]? in
                guard let id = tab["tabId"] as? String, let version = tab["tabVersion"] as? String else { return nil }
                return ["tabId": id, "tabVersion": version]
            }
        } else if method == "tabs.new", response["ok"] as? Bool == true,
                  let value = response["value"] as? [String: Any],
                  let id = (value["id"] ?? value["tabId"]) as? String,
                  let current = tabs().first(where: { $0["tabId"] as? String == id }) {
            result["tab"] = ["tabId": id, "tabVersion": current["tabVersion"]]
        } else if let tabID, let current = tabs().first(where: { $0["tabId"] as? String == tabID }),
                  let version = current["tabVersion"] as? String,
                  response["ok"] as? Bool == true || version == expected {
            result["tab"] = ["tabId": tabID, "tabVersion": version]
        }
        return result
    }

    private func failure(_ code: String) -> [String: Any] {
        ["version": 1, "ok": false, "error": [
            "code": code, "message": "Browser request refused; observe the page before continuing.",
            "mayHaveCompleted": false
        ]]
    }

    private func envelope(_ response: [String: Any]) -> [String: Any] { ["response": response] }
}
