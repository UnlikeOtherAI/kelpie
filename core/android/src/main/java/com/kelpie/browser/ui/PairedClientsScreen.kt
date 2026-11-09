package com.kelpie.browser.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.kelpie.browser.network.PairApprovalCoordinator

/**
 * Sub-screen listing paired clients with revoke actions.
 *
 * Computer permissions, legacy grants, temporary sessions and recent denials.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PairedClientsScreen(
    coordinator: PairApprovalCoordinator,
    onBack: () -> Unit,
) {
    var refreshTick by remember { mutableIntStateOf(0) }
    val prompt by coordinator.currentPrompt.collectAsState()
    // Refresh after an approval decision or revocation; durable storage is not Observable.
    val computers = remember(refreshTick, prompt) { coordinator.store.trustedComputers.list() }
    val persistent = remember(refreshTick, prompt) { coordinator.store.listPersistent() }
    val sessions = remember(refreshTick, prompt) { coordinator.store.listSessions() }
    val denied = remember(refreshTick, prompt) { coordinator.store.listDeniedSources() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Paired Clients") },
                actions = { TextButton(onClick = onBack) { Text("Done") } },
            )
        },
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding).padding(horizontal = 16.dp)) {
            item { sectionHeader("Trusted computers") }
            if (computers.isEmpty()) {
                item { emptyRow("No remote computers approved. Localhost is always allowed.") }
            } else {
                items(computers, key = { it.publicKey }) { computer ->
                    pairingRow(name = computer.name, subtitle = "${computer.address} · ${computer.publicKey}") {
                        coordinator.store.trustedComputers.revoke(computer.publicKey)
                        refreshTick++
                    }
                }
            }
            item { sectionHeader("Earlier client approvals") }
            if (persistent.isEmpty()) {
                item { emptyRow("No persistent pairings.") }
            } else {
                items(persistent, key = { it.clientId }) { record ->
                    pairingRow(
                        name = record.clientName,
                        subtitle = timeAgoLabel(record.approvedAt),
                    ) {
                        coordinator.store.revoke(record.clientId)
                        refreshTick++
                    }
                }
            }

            item { sectionHeader("Account and temporary access") }
            if (sessions.isEmpty()) {
                item { emptyRow("No active session pairings.") }
            } else {
                items(sessions, key = { it.clientId }) { record ->
                    pairingRow(
                        name = record.clientName,
                        subtitle = timeAgoLabel(record.approvedAt),
                    ) {
                        coordinator.store.revoke(record.clientId)
                        refreshTick++
                    }
                }
            }

            item { sectionHeader("Recently denied") }
            if (denied.isEmpty()) {
                item { emptyRow("No suppressed sources.") }
            } else {
                items(denied, key = { it.first }) { (addr, expires) ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(addr, style = MaterialTheme.typography.bodyMedium)
                        Text(expiresInLabel(expires), style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun sectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun emptyRow(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 8.dp))
}

@Composable
private fun pairingRow(
    name: String,
    subtitle: String,
    onRevoke: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyMedium)
            Text(subtitle, style = MaterialTheme.typography.labelSmall)
        }
        TextButton(onClick = onRevoke) { Text("Revoke") }
    }
}

private fun timeAgoLabel(ms: Long): String {
    val seconds = (System.currentTimeMillis() - ms).coerceAtLeast(0) / 1000
    if (seconds < 60) return "just now"
    if (seconds < 3600) return "${seconds / 60} min ago"
    if (seconds < 86_400) return "${seconds / 3600} hr ago"
    return "${seconds / 86_400} days ago"
}

private fun expiresInLabel(ms: Long): String {
    val seconds = (ms - System.currentTimeMillis()).coerceAtLeast(0) / 1000
    if (seconds < 60) return "$seconds s left"
    return "${seconds / 60} min left"
}
