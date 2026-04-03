package com.mollotov.browser.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.material3.Switch
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mollotov.browser.FeatureFlags
import com.mollotov.browser.device.DeviceInfo

@Composable
fun SettingsScreen(
    deviceInfo: DeviceInfo,
    isServerRunning: Boolean,
    isMDNSAdvertising: Boolean,
    onShowWelcome: () -> Unit,
) {
    val context = LocalContext.current
    var enable3DInspector by remember { mutableStateOf(FeatureFlags.is3DInspectorEnabled(context)) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
    ) {
        Text("Mollotov", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(16.dp))

        SectionHeader("Device")
        InfoRow("Name", deviceInfo.name)
        InfoRow("Model", deviceInfo.model)
        InfoRow("ID", deviceInfo.id.take(8) + "...")
        InfoRow("Platform", "Android")

        HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

        SectionHeader("Network")
        InfoRow("IP Address", deviceInfo.ip)
        InfoRow("Port", deviceInfo.port.toString())
        InfoRow("HTTP Server", if (isServerRunning) "Running" else "Stopped")
        InfoRow("mDNS", if (isMDNSAdvertising) "Advertising" else "Off")

        HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

        SectionHeader("Display")
        InfoRow("Width", "${deviceInfo.width}px")
        InfoRow("Height", "${deviceInfo.height}px")

        HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

        SectionHeader("Help")
        HelpActionRow("Show Welcome Screen", onClick = onShowWelcome)
        HelpActionRow("Open Mollotov Website") {
            openHelpURL(context, "https://unlikeotherai.github.io/mollotov")
        }
        HelpActionRow("Open GitHub Repository") {
            openHelpURL(context, "https://github.com/UnlikeOtherAI/mollotov")
        }
        HelpActionRow("Open UnlikeOtherAI") {
            openHelpURL(context, "https://unlikeotherai.com")
        }

        Spacer(Modifier.height(8.dp))
        SectionHeader("Experimental")
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("3D DOM Inspector", style = MaterialTheme.typography.bodyMedium)
            Switch(
                checked = enable3DInspector,
                onCheckedChange = {
                    enable3DInspector = it
                    FeatureFlags.set3DInspectorEnabled(context, it)
                },
            )
        }

        Spacer(Modifier.height(8.dp))
        InfoRow("Version", deviceInfo.version)
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(bottom = 8.dp),
    )
}

@Composable
private fun InfoRow(label: String, value: String) {
    Text(
        text = "$label: $value",
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.padding(vertical = 2.dp),
    )
}

@Composable
private fun HelpActionRow(
    title: String,
    onClick: () -> Unit,
) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            text = title,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

private fun openHelpURL(context: android.content.Context, value: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(value)).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    context.startActivity(intent)
}
