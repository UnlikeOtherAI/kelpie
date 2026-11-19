package com.kelpie.browser.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.kelpie.browser.account.UOAAccount
import com.kelpie.browser.browser.BookmarkStore

@Composable
internal fun AccountButton() {
    val account by UOAAccount.state.collectAsState()
    var menu by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = {
            if (account.profile == null && !account.signingIn) UOAAccount.signIn() else menu = true
        }, modifier = Modifier.size(44.dp)) {
            val label = if (account.profile == null) "Login/register" else "Account"
            AccountAvatar(account.avatar, label)
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            if (!account.signingIn) {
                DropdownMenuItem(text = { Text(account.profile?.name ?: account.profile?.email.orEmpty()) }, enabled = false, onClick = {})
            }
            AccountMenuActions { menu = false }
        }
    }
}

@Composable
internal fun AccountMenuEntry(
    onDismiss: () -> Unit,
    onShowAccount: () -> Unit,
) {
    val account by UOAAccount.state.collectAsState()
    val profile = account.profile
    val label =
        when {
            account.signingIn -> "Cancel login"
            profile != null -> profile.name ?: profile.email
            else -> "Login/register"
        }
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = { AccountAvatar(account.avatar, null) },
        modifier = Modifier.testTag("browser.account.menu"),
        onClick = {
            when {
                account.signingIn -> {
                    onDismiss()
                    UOAAccount.signOut()
                }
                profile == null -> {
                    onDismiss()
                    UOAAccount.signIn()
                }
                else -> onShowAccount()
            }
        },
    )
}

@Composable
internal fun AccountMenuBack(onBack: () -> Unit) {
    DropdownMenuItem(
        text = { Text("Account") },
        leadingIcon = { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") },
        onClick = onBack,
    )
}

@Composable
internal fun AccountMenuActions(onDismiss: () -> Unit) {
    val account by UOAAccount.state.collectAsState()
    val syncError by BookmarkStore.syncError.collectAsState()
    if (account.signingIn) {
        DropdownMenuItem(text = { Text("Cancel login") }, onClick = {
            onDismiss()
            UOAAccount.signOut()
        })
    } else {
        syncError?.let { error ->
            DropdownMenuItem(text = { Text(error) }, enabled = false, onClick = {})
        }
        DropdownMenuItem(text = { Text("Refresh favourites") }, onClick = {
            onDismiss()
            BookmarkStore.refreshAccountBookmarks()
        })
        DropdownMenuItem(text = { Text("Sign out") }, onClick = {
            onDismiss()
            UOAAccount.signOut()
        })
    }
}

@Composable
internal fun AccountLoginError() {
    val account by UOAAccount.state.collectAsState()
    account.error?.let { message ->
        AlertDialog(
            onDismissRequest = UOAAccount::dismissError,
            text = { Text(message) },
            confirmButton = { TextButton(onClick = UOAAccount::dismissError) { Text("OK") } },
        )
    }
}

@Composable
private fun AccountAvatar(
    data: ByteArray?,
    label: String?,
) {
    val avatar = remember(data) { data?.let(::decodeAvatar) }
    if (avatar != null) {
        Image(avatar.asImageBitmap(), label, Modifier.size(32.dp).clip(CircleShape))
    } else {
        Icon(Icons.Default.PersonOutline, label)
    }
}

private fun decodeAvatar(data: ByteArray): android.graphics.Bitmap? {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(data, 0, data.size, options)
    options.inSampleSize = maxOf(1, maxOf(options.outWidth, options.outHeight) / 128)
    options.inJustDecodeBounds = false
    return BitmapFactory.decodeByteArray(data, 0, data.size, options)
}
