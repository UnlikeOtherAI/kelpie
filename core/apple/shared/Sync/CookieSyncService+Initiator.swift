import Foundation
import Network

/// The initiator side: discovery, handshakes, the long-poll pull loop and pushes.
/// Only the initiator of a session sends requests.
extension CookieSyncService {
    // MARK: - Discovery

    func discoveryChanged(_ run: SyncRun, _ adverts: [SyncAdvert]) {
        guard isCurrent(run) else { return }
        let accepted = acceptedHints(run)
        let visible = adverts.filter { $0.replica != run.replica && accepted.contains($0.hint) }
        let replicas = Set(visible.map(\.replica))
        for advert in visible {
            let peer = run.peer(advert.replica)
            if peer.advert == nil { peer.quietSince = Date() }
            peer.advert = advert
            if peer.name.isEmpty { peer.name = advert.name }
            noteSeen(run, advert.replica)
            considerConnecting(run, peer)
        }
        for peer in run.peers.values where peer.advert != nil && !replicas.contains(peer.replica) {
            peer.advert = nil
            peer.timer?.cancel()
        }
    }

    /// One session per pair: the smaller replica id initiates at once; the other only
    /// when no session has formed `initiatorFallback` seconds after it saw the peer or
    /// after the last session ended.
    func considerConnecting(_ run: SyncRun, _ peer: SyncPeer) {
        guard isCurrent(run), peer.advert != nil, !peer.handshaking, run.channel(for: peer.replica) == nil else { return }
        var due = Date()
        if let retryAt = peer.retryAt { due = max(due, retryAt) }
        if !Self.precedes(run.replica, peer.replica) {
            due = max(due, peer.quietSince.addingTimeInterval(timing.initiatorFallback))
        }
        guard due <= Date() else {
            schedule(run, peer, at: due)
            return
        }
        guard run.outgoingLimiter.allow("all") else {
            schedule(run, peer, at: run.outgoingLimiter.nextSlot())
            return
        }
        connect(run, peer)
    }

    static func precedes(_ lhs: String, _ rhs: String) -> Bool { Array(lhs.utf8).lexicographicallyPrecedes(rhs.utf8) }

    private func schedule(_ run: SyncRun, _ peer: SyncPeer, at date: Date) {
        peer.timer?.cancel()
        peer.timer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(date.timeIntervalSinceNow))
            guard !Task.isCancelled, let self, self.isCurrent(run) else { return }
            self.considerConnecting(run, peer)
        }
    }

    private func connect(_ run: SyncRun, _ peer: SyncPeer) {
        peer.handshaking = true
        run.spawn { [weak self] in
            guard let self else { return }
            do {
                let channel = try await self.handshake(run, peer)
                guard self.isCurrent(run) else { return }
                peer.handshaking = false
                peer.failures = 0
                peer.retryAt = nil
                peer.lastError = nil
                self.installed(run, channel)
            } catch {
                peer.handshaking = false
                guard self.isCurrent(run) else { return }
                self.handshakeFailed(run, peer, error)
            }
        }
    }

    /// Exponential backoff from 5 s to 5 min after a failure.
    private func handshakeFailed(_ run: SyncRun, _ peer: SyncPeer, _ error: Error) {
        peer.failures += 1
        let delay = min(timing.backoffMinimum * pow(2, Double(peer.failures - 1)), timing.backoffMaximum)
        peer.retryAt = Date().addingTimeInterval(delay)
        peer.lastError = SyncFailure.code(of: error)
        SyncLog.failure("handshake", error)
        considerConnecting(run, peer)
    }

    // MARK: - Handshake

    private func handshake(_ run: SyncRun, _ peer: SyncPeer) async throws -> SyncChannel {
        guard let advert = peer.advert, let discovery = run.discovery else { throw SyncFailure("UNREACHABLE") }
        guard let endpoint = await discovery.resolve(advert) else { throw SyncFailure("UNREACHABLE") }
        try ensureCurrent(run)
        let key = SyncCrypto.makePrivateKey()
        let keyText = SyncCrypto.publicKeyText(key)
        let nonce = SyncCrypto.randomText(32)
        guard let hint = try? SyncStoreBridge.accountHints(subject: run.fence.subject, now: now()).current else {
            throw SyncFailure("INTERNAL")
        }
        let hello: [String: Any] = [
            "v": 1, "replica": run.replica, "hint": hint, "now": now(), "platform": environment.platform,
            "name": environment.deviceName, "key": keyText, "nonce": nonce
        ]
        let reply = try await post(endpoint, .hello, hello)
        try ensureCurrent(run)
        guard SyncStoreBridge.invalidReason("hello-reply", reply) == nil, reply["replica"] as? String == advert.replica,
              let peerKeyText = reply["key"] as? String, let peerNonce = reply["nonce"] as? String,
              let handshakeId = reply["handshakeId"] as? String, let peerNow = SyncJSON.int64(reply["now"]) else {
            throw SyncFailure("PROTOCOL")
        }
        guard abs(peerNow - now()) <= SyncLimits.maxClockSkewMillis else { throw SyncFailure("CLOCK_SKEW") }
        let peerKey = try SyncCrypto.publicKey(peerKeyText)
        peer.platform = reply["platform"] as? String ?? peer.platform
        peer.name = reply["name"] as? String ?? peer.name
        let challenge = try SyncStoreBridge.challenge(
            initiator: ["replica": run.replica, "key": keyText, "nonce": nonce],
            responder: ["replica": advert.replica, "key": peerKeyText, "nonce": peerNonce]
        )
        let ticket = try await issueTicket(challenge, clientId: "kelpie-sync:i:\(run.replica)")
        try ensureCurrent(run)
        let auth = try await post(endpoint, .auth, ["handshakeId": handshakeId, "ticket": ticket])
        try ensureCurrent(run)
        guard SyncStoreBridge.invalidReason("auth-reply", auth) == nil, let peerTicket = auth["ticket"] as? String,
              let sessionExpiresAt = SyncJSON.int64(auth["sessionExpiresAt"]) else { throw SyncFailure("PROTOCOL") }
        guard try await validateTicket(peerTicket, challenge, clientId: "kelpie-sync:r:\(advert.replica)") else {
            throw SyncFailure("PROOF_REJECTED")
        }
        try ensureCurrent(run)
        let keys = try SyncCrypto.channelKeys(sharedSecret: try SyncCrypto.sharedSecret(key, peerKey), challenge: challenge)
        return SyncChannel(
            sessionId: handshakeId,
            peer: advert.replica,
            role: .initiator(endpoint),
            sendKey: keys.i2r,
            receiveKey: keys.r2i,
            expiresAt: min(now() + timing.sessionMillis, sessionExpiresAt)
        )
    }

    func ensureCurrent(_ run: SyncRun) throws {
        guard isCurrent(run) else { throw CancellationError() }
    }

    func issueTicket(_ challenge: String, clientId: String) async throws -> String {
        do {
            return try await uoa.run { try await account.issueTicket(challenge: challenge, clientId: clientId) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncFailure("UOA_UNAVAILABLE")
        }
    }

    func validateTicket(_ ticket: String, _ challenge: String, clientId: String) async throws -> Bool {
        do {
            return try await uoa.run { try await account.validateTicket(ticket, challenge: challenge, clientId: clientId) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncFailure("UOA_UNAVAILABLE")
        }
    }

    /// An unauthenticated handshake request. Non-200 replies become their `error` code.
    private func post(_ endpoint: NWEndpoint, _ route: SyncRoute, _ body: [String: Any]) async throws -> [String: Any] {
        let response = try await SyncHTTPClient.post(
            endpoint, path: route.rawValue, body: try SyncJSON.data(body), timeout: 15, rule: environment.rule
        )
        let json = SyncJSON.object(response.body)
        guard response.status == 200, let json else { throw SyncFailure(json?["error"] as? String ?? "HTTP_\(response.status)") }
        return json
    }

    // MARK: - Sessions

    func installed(_ run: SyncRun, _ channel: SyncChannel) {
        run.install(channel)
        run.peer(channel.peer).timer?.cancel()
        guard channel.isInitiator else { return }
        channel.spawn { [weak self] in await self?.pullLoop(run, channel) }
        schedulePush(run, channel)
    }

    func isLive(_ run: SyncRun, _ channel: SyncChannel) -> Bool {
        isCurrent(run) && !channel.closed && run.channels[channel.sessionId] === channel && now() < channel.expiresAt
    }

    /// Ends a session. An expired or unknown session handshakes again at once; any other
    /// failure backs off.
    func channelFailed(_ run: SyncRun, _ channel: SyncChannel, _ error: Error) {
        guard isCurrent(run), run.channels[channel.sessionId] === channel else { return }
        run.remove(channel)
        let peer = run.peer(channel.peer)
        peer.quietSince = Date()
        let code = SyncFailure.code(of: error)
        if code == "SYNC_SESSION" {
            considerConnecting(run, peer)
        } else {
            handshakeFailed(run, peer, error)
        }
    }

    // MARK: - Pull

    private func pullLoop(_ run: SyncRun, _ channel: SyncChannel) async {
        while isLive(run, channel) {
            do {
                try await pullOnce(run, channel)
            } catch {
                channelFailed(run, channel, error)
                return
            }
        }
        if isCurrent(run), !channel.closed { channelFailed(run, channel, SyncFailure("SYNC_SESSION")) }
    }

    private func pullOnce(_ run: SyncRun, _ channel: SyncChannel) async throws {
        let since = try await run.store.watermark(channel.peer)
        let request: [String: Any] = ["op": "pull", "replica": run.replica, "since": since, "wait": timing.pullWaitMillis]
        let timeout = TimeInterval(timing.pullWaitMillis) / 1_000 + 15
        let response = try await exchange(run, channel, request, timeout: timeout)
        guard response["replica"] as? String == channel.peer, let seq = SyncJSON.uint64(response["seq"]) else {
            throw SyncFailure("PROTOCOL")
        }
        noteWatermark(run, channel, response["yourWatermark"])
        if response["warming"] as? Bool == true {
            try await Task.sleep(nanoseconds: Self.nanoseconds(timing.warmingRetry))
            return
        }
        let records = response["records"] as? [Any] ?? []
        if !records.isEmpty || seq != SyncJSON.uint64(since["seq"]) {
            let applied = try await run.store.merge(
                records: records, source: ["replica": channel.peer, "seq": NSNumber(value: seq)], apply: applyOps(run)
            )
            try ensureCurrent(run)
            if applied > 0 { feedChanged(run, except: channel.peer) }
        }
        run.peer(channel.peer).lastSyncAt = now()
        if response["more"] as? Bool != true, response["incomplete"] as? Bool != true {
            warmupProgress(run, completed: channel.peer)
        }
    }

    private func noteWatermark(_ run: SyncRun, _ channel: SyncChannel, _ value: Any?) {
        guard let watermark = value as? [String: Any], watermark["replica"] as? String == run.replica,
              let seq = SyncJSON.uint64(watermark["seq"]) else { return }
        if let known = SyncJSON.uint64(channel.yourWatermark?["seq"]), known > seq { return }
        channel.yourWatermark = watermark
    }

    // MARK: - Push

    /// Pushes local changes. A push already in flight is followed by one more.
    func schedulePush(_ run: SyncRun, _ channel: SyncChannel) {
        guard channel.isInitiator, isLive(run, channel) else { return }
        guard !channel.pushing else {
            channel.pushAgain = true
            return
        }
        channel.pushing = true
        channel.spawn { [weak self] in
            defer { channel.pushing = false }
            guard let self else { return }
            do {
                repeat {
                    channel.pushAgain = false
                    try await self.pushAll(run, channel)
                } while channel.pushAgain && self.isLive(run, channel)
            } catch {
                self.channelFailed(run, channel, error)
            }
        }
    }

    private func pushAll(_ run: SyncRun, _ channel: SyncChannel) async throws {
        for _ in 0..<1_000 {
            let watermark = channel.yourWatermark ?? ["replica": run.replica, "seq": 0]
            let built = try await run.store.buildPush(watermark: watermark, snapshot: snapshot(run))
            guard isLive(run, channel) else { throw CancellationError() }
            guard let push = built["push"] as? [String: Any] else { return }
            let response = try await exchange(run, channel, push, timeout: 60)
            noteWatermark(run, channel, response["yourWatermark"])
            run.peer(channel.peer).lastSyncAt = now()
            if push["more"] as? Bool != true { return }
        }
    }

    // MARK: - Channel

    /// One sealed request and its sealed response, under the session's next sequence number.
    private func exchange(_ run: SyncRun, _ channel: SyncChannel, _ plaintext: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard let endpoint = channel.endpoint else { throw SyncFailure("PROTOCOL") }
        guard isLive(run, channel) else { throw SyncFailure("SYNC_SESSION") }
        channel.lastSeq += 1
        let seq = channel.lastSeq
        let box = try SyncCrypto.seal(
            try SyncJSON.data(plaintext), key: channel.sendKey, sessionId: channel.sessionId, direction: .request, seq: seq
        )
        let response = try await SyncHTTPClient.post(
            endpoint,
            path: SyncRoute.exchange.rawValue,
            body: try SyncJSON.data(["seq": NSNumber(value: seq), "box": box]),
            headers: ["X-Kelpie-Sync-Session": channel.sessionId],
            timeout: timeout,
            rule: environment.rule
        )
        let envelope = SyncJSON.object(response.body)
        guard response.status == 200, let envelope else {
            throw SyncFailure(envelope?["error"] as? String ?? "HTTP_\(response.status)")
        }
        guard SyncStoreBridge.invalidReason("exchange", envelope) == nil, SyncJSON.uint64(envelope["seq"]) == seq,
              let sealed = envelope["box"] as? String else { throw SyncFailure("PROTOCOL") }
        let plain = try SyncCrypto.open(sealed, key: channel.receiveKey, sessionId: channel.sessionId, direction: .response, seq: seq)
        guard let json = SyncJSON.object(plain) else { throw SyncFailure("PROTOCOL") }
        return json
    }
}
