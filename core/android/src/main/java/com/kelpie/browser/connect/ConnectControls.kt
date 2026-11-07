package com.kelpie.browser.connect

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.kelpie.browser.account.UOAAccount

/** Shared Settings and in-context browsing controls. */
@Composable
fun ConnectControls(compact: Boolean = false) {
    val connection by NessieConnection.state.collectAsState()
    val account by UOAAccount.state.collectAsState()
    if (compact && !connection.running && !connection.paused) return
    Row(Modifier.fillMaxWidth().padding(8.dp).testTag("nessie.controls")) {
        Text(if (connection.running) "Nessie is using this tab" else connection.status, Modifier.weight(1f))
        Spacer(Modifier.padding(4.dp))
        if (account.profile != null) {
            if (connection.requiresSignIn) {
                TextButton(onClick = NessieConnection::renewConsent, modifier = Modifier.testTag("nessie.sign-in")) { Text("Sign in again") }
            } else {
                TextButton(onClick = NessieConnection::togglePause, modifier = Modifier.testTag("nessie.pause")) {
                    Text(if (connection.paused) "Resume Nessie" else "Pause Nessie")
                }
                if (connection.running) {
                    TextButton(onClick = NessieConnection::stop, modifier = Modifier.testTag("nessie.stop")) { Text("Stop Nessie") }
                }
            }
        }
    }
}
