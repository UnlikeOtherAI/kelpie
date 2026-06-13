package com.kelpie.browser.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.kelpie.browser.network.PairApprovalCoordinator

/**
 * Modal dialog shown when an unauthenticated client requests pairing.
 *
 * Per the design (Codex finding #24): "No" is the default button — first in
 * stacking order, prominent. Back-press / outside-tap is treated as denial.
 * "Always allow" is visually distinct (orange-tinted) and never the default.
 */
@Composable
fun PairingDialog(coordinator: PairApprovalCoordinator) {
    val prompt by coordinator.currentPrompt.collectAsState()
    val current = prompt ?: return

    AlertDialog(
        onDismissRequest = { coordinator.deny(current.requestId) },
        properties = DialogProperties(dismissOnBackPress = true, dismissOnClickOutside = false),
        title = { Text("Allow this client to control this browser?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Name (self-reported):", style = MaterialTheme.typography.labelSmall)
                Text(current.clientName.ifEmpty { "(no name)" }, style = MaterialTheme.typography.bodyMedium)

                Spacer(Modifier.height(4.dp))

                Text("From:", style = MaterialTheme.typography.labelSmall)
                Text(current.sourceAddress, style = MaterialTheme.typography.bodyMedium)

                Spacer(Modifier.height(8.dp))

                Text(
                    "This client will be able to navigate, type, screenshot, run JavaScript, and read cookies.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        },
        confirmButton = {
            // "No" is the default — placed in confirmButton slot so it gets
            // visual primacy.
            Button(
                onClick = { coordinator.deny(current.requestId) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("No")
            }
        },
        dismissButton = {
            Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { coordinator.approve(current.requestId, persist = false) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Yes, once")
                }
                OutlinedButton(
                    onClick = { coordinator.approve(current.requestId, persist = true) },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFFEF6C00)),
                ) {
                    Text("Always allow")
                }
            }
        },
    )
}
