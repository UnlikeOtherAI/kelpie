package com.mollotov.browser.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mollotov.browser.device.DeviceInfo

@Composable
fun SettingsScreen(
    deviceInfo: DeviceInfo,
    isServerRunning: Boolean,
    isMDNSAdvertising: Boolean,
) {
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
