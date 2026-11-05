package com.kelpie.browser.automation

import com.kelpie.browser.account.UOAAccount
import com.kelpie.browser.network.AccountPairingAuthorization
import com.kelpie.browser.network.AuthDecision
import com.kelpie.browser.network.PairingStore
import com.kelpie.browser.network.ParsedRequest

/** Reuses existing pairing/account authority; body sessionId never enters this boundary. */
fun scriptHttpAuthority(
    clientId: String,
    request: ParsedRequest,
    store: PairingStore,
    admittedListener: String,
    listener: () -> String?,
): ScriptAuthority {
    val bearer =
        request.headers["authorization"]
            ?.singleOrNull()
            ?.drop(7)
            ?.trim()
            .orEmpty()
    if (bearer.isEmpty()) throw ScriptFailure("SCRIPT_AUTHORIZATION_REQUIRED")
    val account = store.accountApproval(bearer)
    return ScriptAuthority(
        ScriptOwner(clientId, PairingStore.hashToken(bearer), admittedListener),
        synchronous = {
            val grant = account?.accountGrant
            listener() == admittedListener &&
                (
                    store.validateBearer(bearer) == clientId ||
                        (
                            account != null &&
                                store.accountApproval(bearer) == account &&
                                grant != null &&
                                grant.sourceAddress == request.sourceAddress &&
                                grant.expiresAt > System.currentTimeMillis() &&
                                UOAAccount.pairingSession == grant.session
                        )
                )
        },
    ) {
        listener() == admittedListener &&
            (AccountPairingAuthorization(store).evaluate(request) as? AuthDecision.Authenticated)?.clientId == clientId
    }
}
