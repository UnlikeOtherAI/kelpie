package com.kelpie.browser.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.kelpie.browser.browser.BrowserDownloads

@Composable
internal fun DownloadsDialog(onDismiss: () -> Unit) {
    val downloads = BrowserDownloads.items
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Downloads") },
        text = {
            if (downloads.isEmpty()) {
                Text("No downloads")
            } else {
                LazyColumn(modifier = Modifier.heightIn(max = 240.dp)) {
                    items(downloads, key = { it.id }) { item ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            val uri = item.uri
                            Column(
                                Modifier
                                    .weight(1f)
                                    .clickable(enabled = uri != null) {
                                        val open = Intent(Intent.ACTION_VIEW).setDataAndType(uri, item.mime)
                                        open.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        try {
                                            context.startActivity(open)
                                        } catch (_: ActivityNotFoundException) {
                                            Toast.makeText(context, "No app can open this file", Toast.LENGTH_SHORT).show()
                                        }
                                    }.padding(vertical = 6.dp),
                            ) {
                                Text(item.name)
                                Text(item.error ?: if (item.finished) "Complete" else "Downloading…", style = MaterialTheme.typography.bodySmall)
                            }
                            if (uri != null) {
                                IconButton(onClick = {
                                    val intent =
                                        Intent(Intent.ACTION_SEND)
                                            .setType(item.mime)
                                            .putExtra(Intent.EXTRA_STREAM, uri)
                                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    context.startActivity(Intent.createChooser(intent, "Share downloaded file"))
                                }) { Icon(Icons.Default.Share, contentDescription = "Share downloaded file") }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
        dismissButton = { TextButton(onClick = BrowserDownloads::clearFinished, enabled = downloads.any { it.finished }) { Text("Clear") } },
    )
}
