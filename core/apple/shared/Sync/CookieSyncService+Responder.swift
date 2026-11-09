import Foundation

/// The responder side: `hello`, `auth` and `exchange` on the sync listener.
/// Errors are `{"error":"<CODE>"}`; no response ever carries cookie data in clear.
extension CookieSyncService {
    // MARK: - Admission (before the body is read)

    func admit(_ route: SyncRoute, _ head: SyncHTTPHead, source: String, run: SyncRun) -> SyncAdmission {
        guard isCurrent(run) else { return .reject(.error(503, "UNAVAILABLE")) }
        switch route {
        case .hello:
            return run.helloLimiter.allow(source) ? .accept : .reject(.error(429, "RATE_LIMITED"))
        case .auth:
            return .accept
        case .exchange:
            guard let id = head.value("x-kelpie-sync-session"), let channel = run.channels[id],
                  !channel.isInitiator, now() < channel.expiresAt else { return .reject(.error(401, "SYNC_SESSION")) }
            return .accept
        }
    }

    func handle(_ route: SyncRoute, _ head: SyncHTTPHead, body: Data, source: String, run: SyncRun) async -> SyncHTTPResponse {
        guard isCurrent(run) else { return .error(503, "UNAVAILABLE") }
        switch route {
        case .hello: return hello(body, run: run)
        case .auth: return await auth(body, run: run)
        case .exchange: return await exchange(head, body, run: run)
        }
    }

    // MARK: - Handshake

    /// Refuses malformed messages, foreign hints and clock skew before any UOA call,
    /// then records a pending handshake for 60 s.
    private func hello(_ body: Data, run: SyncRun) -> SyncHTTPResponse {
        guard let hello = SyncJSON.object(body), SyncStoreBridge.invalidReason("hello", hello) == nil,
              let peer = hello["replica"] as? String, peer != run.replica,
              let hint = hello["hint"] as? String, let keyText = hello["key"] as? String,
              let nonce = hello["nonce"] as? String, let peerNow = SyncJSON.int64(hello["now"]),
              let peerKey = try? SyncCrypto.publicKey(keyText) else { return .error(400, "INVALID_MESSAGE") }
        guard acceptedHints(run).contains(hint) else { return .error(409, "ACCOUNT_MISMATCH") }
        guard SyncLimits.withinSkew(peerNow, now()) else {
            run.peers[peer]?.lastError = "CLOCK_SKEW"
            return .error(409, "CLOCK_SKEW")
        }
        let key = SyncCrypto.makePrivateKey()
        let keyReply = SyncCrypto.publicKeyText(key)
        let ownNonce = SyncCrypto.randomText(32)
        guard let challenge = try? SyncStoreBridge.challenge(
            initiator: ["replica": peer, "key": keyText, "nonce": nonce],
            responder: ["replica": run.replica, "key": keyReply, "nonce": ownNonce]
        ) else { return .error(400, "INVALID_MESSAGE") }
        let pending = SyncPendingHandshake(
            id: SyncCrypto.randomText(32),
            peer: peer,
            platform: hello["platform"] as? String ?? "",
            name: hello["name"] as? String ?? "",
            peerKey: peerKey,
            privateKey: key,
            challenge: challenge,
            expiresAt: now() + timing.pendingMillis
        )
        run.addPending(pending)
        return .json(200, [
            "v": 1, "replica": run.replica, "now": now(), "platform": environment.platform, "name": environment.deviceName,
            "key": keyReply, "nonce": ownNonce, "handshakeId": pending.id, "expiresAt": pending.expiresAt
        ])
    }

    /// The first `auth` consumes the handshake whatever happens next. The initiator's
    /// ticket must validate for the transcript and its role-prefixed client id before
    /// this side issues its own ticket and installs the session keys, once.
    private func auth(_ body: Data, run: SyncRun) async -> SyncHTTPResponse {
        guard let auth = SyncJSON.object(body), SyncStoreBridge.invalidReason("auth", auth) == nil,
              let id = auth["handshakeId"] as? String, let ticket = auth["ticket"] as? String else {
            return .error(400, "INVALID_MESSAGE")
        }
        guard let pending = run.takePending(id), now() < pending.expiresAt else { return .error(401, "SYNC_SESSION") }
        do {
            guard try await validateTicket(ticket, pending.challenge, clientId: "kelpie-sync:i:\(pending.peer)") else {
                run.peers[pending.peer]?.lastError = "PROOF_REJECTED"
                return .error(403, "PROOF_REJECTED")
            }
            try ensureCurrent(run)
            let own = try await issueTicket(pending.challenge, clientId: "kelpie-sync:r:\(run.replica)")
            try ensureCurrent(run)
            let secret = try SyncCrypto.sharedSecret(pending.privateKey, pending.peerKey)
            let keys = try SyncCrypto.channelKeys(sharedSecret: secret, challenge: pending.challenge)
            let expiresAt = now() + timing.sessionMillis
            let peer = run.peer(pending.peer)
            peer.platform = pending.platform
            peer.name = pending.name
            peer.lastError = nil
            installed(run, SyncChannel(
                sessionId: pending.id,
                peer: pending.peer,
                role: .responder,
                sendKey: keys.r2i,
                receiveKey: keys.i2r,
                expiresAt: expiresAt
            ))
            noteSeen(run, pending.peer)
            return .json(200, ["ticket": own, "sessionExpiresAt": expiresAt])
        } catch {
            SyncLog.failure("auth", error)
            return isCurrent(run) ? .error(503, SyncFailure.code(of: error)) : .error(503, "UNAVAILABLE")
        }
    }

    // MARK: - Exchange

    private func exchange(_ head: SyncHTTPHead, _ body: Data, run: SyncRun) async -> SyncHTTPResponse {
        guard let id = head.value("x-kelpie-sync-session"), let channel = run.channels[id], !channel.isInitiator,
              now() < channel.expiresAt else { return .error(401, "SYNC_SESSION") }
        guard let envelope = SyncJSON.object(body), SyncStoreBridge.invalidReason("exchange", envelope) == nil,
              let seq = SyncJSON.uint64(envelope["seq"]), let box = envelope["box"] as? String else {
            return .error(400, "INVALID_MESSAGE")
        }
        guard channel.replay.canAccept(seq) else { return .error(409, "REPLAYED") }
        guard let plain = try? SyncCrypto.open(box, key: channel.receiveKey, sessionId: id, direction: .request, seq: seq),
              let request = SyncJSON.object(plain) else { return .error(400, "INVALID_MESSAGE") }
        channel.replay.mark(seq)
        do {
            let response: [String: Any]
            switch request["op"] as? String {
            case "pull": response = try await answerPull(request, channel: channel, run: run)
            case "push": response = try await acceptPush(request, channel: channel, run: run)
            default: return .error(400, "INVALID_MESSAGE")
            }
            guard isCurrent(run), run.channels[id] === channel else { return .error(401, "SYNC_SESSION") }
            let sealed = try SyncCrypto.seal(try SyncJSON.data(response), key: channel.sendKey, sessionId: id, direction: .response, seq: seq)
            return .json(200, ["seq": NSNumber(value: seq), "box": sealed])
        } catch {
            SyncLog.failure("exchange", error)
            return isCurrent(run) ? .error(500, SyncFailure.code(of: error)) : .error(503, "UNAVAILABLE")
        }
    }

    /// Answers at once when there are records after `since`, otherwise when the feed
    /// changes or `wait` (at most 25 s) runs out.
    private func answerPull(_ pull: [String: Any], channel: SyncChannel, run: SyncRun) async throws -> [String: Any] {
        guard pull["replica"] as? String == channel.peer else { throw SyncFailure("INVALID_MESSAGE") }
        let wait = min(max(SyncJSON.int64(pull["wait"]) ?? 0, 0), Int64(SyncLimits.maxPullWaitMillis))
        let deadline = Date().addingTimeInterval(TimeInterval(wait) / 1_000)
        run.answering += 1
        defer { run.answering -= 1 }
        while true {
            let seen = run.changes.version
            let response = try await run.store.answerPull(pull, snapshot: snapshot(run))
            try ensureCurrent(run)
            let records = response["records"] as? [Any] ?? []
            let ready = !records.isEmpty || response["more"] as? Bool == true || response["warming"] as? Bool == true
            if ready || Date() >= deadline || run.channels[channel.sessionId] !== channel { return response }
            run.answering -= 1
            await run.changes.wait(after: seen, until: deadline)
            run.answering += 1
        }
    }

    /// Commits a push, then reports how far this store has committed from the initiator.
    private func acceptPush(_ push: [String: Any], channel: SyncChannel, run: SyncRun) async throws -> [String: Any] {
        guard push["replica"] as? String == channel.peer, let records = push["records"] as? [Any],
              let seq = SyncJSON.uint64(push["seq"]) else { throw SyncFailure("INVALID_MESSAGE") }
        let applied = try await run.store.merge(
            records: records, source: ["replica": channel.peer, "seq": NSNumber(value: seq)], apply: applyOps(run)
        )
        try ensureCurrent(run)
        let watermark = try await run.store.watermark(channel.peer)
        run.peer(channel.peer).lastSyncAt = now()
        if applied > 0 { feedChanged(run, except: channel.peer) }
        if push["more"] as? Bool != true { warmupProgress(run, completed: channel.peer) }
        return ["yourWatermark": watermark]
    }
}
