package com.kelpie.browser.ui

import android.app.Activity
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import com.kelpie.browser.account.UOAAccount
import com.kelpie.browser.browser.BookmarkStore

@Composable
internal fun AccountButton(activity: Activity) {
    val account by UOAAccount.state.collectAsState()
    val syncError by BookmarkStore.syncError.collectAsState()
    var menu by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = {
            if (account.profile == null && !account.signingIn) UOAAccount.signIn() else menu = true
        }, modifier = Modifier.size(44.dp)) {
            val avatar = remember(account.avatar) { account.avatar?.let { decodeAvatar(it) } }
            val label = if (account.profile == null) "Login/register" else "Account"
            if (avatar != null) {
                Image(avatar.asImageBitmap(), label, Modifier.size(32.dp).clip(CircleShape))
            } else {
                Icon(Icons.Default.PersonOutline, label)
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            if (account.signingIn) {
                DropdownMenuItem(text = { Text("Cancel login") }, onClick = {
                    menu = false
                    UOAAccount.signOut()
                })
            } else {
                DropdownMenuItem(text = { Text(account.profile?.name ?: account.profile?.email.orEmpty()) }, enabled = false, onClick = {})
                if (syncError != null) DropdownMenuItem(text = { Text(syncError.orEmpty()) }, enabled = false, onClick = {})
                DropdownMenuItem(text = { Text("Refresh favourites") }, onClick = {
                    menu = false
                    BookmarkStore.refreshAccountBookmarks()
                })
                DropdownMenuItem(text = { Text("Sign out") }, onClick = {
                    menu = false
                    UOAAccount.signOut()
                })
            }
        }
    }
    account.error?.let { message ->
        AlertDialog(
            onDismissRequest = UOAAccount::dismissError,
            text = { Text(message) },
            confirmButton = { TextButton(onClick = UOAAccount::dismissError) { Text("OK") } },
        )
    }
}

private fun decodeAvatar(data: ByteArray): android.graphics.Bitmap? {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(data, 0, data.size, options)
    options.inSampleSize = maxOf(1, maxOf(options.outWidth, options.outHeight) / 128)
    options.inJustDecodeBounds = false
    return BitmapFactory.decodeByteArray(data, 0, data.size, options)
}
