package com.kelpie.browser.ui

import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Alignment
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import com.kelpie.browser.browser.HistoryStore

@Composable
fun HistoryAutocompleteField(
    currentUrl: String,
    placeholder: String,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
    shape: Shape = CircleShape,
    textStyle: TextStyle = TextStyle.Default,
    onEditingChanged: (Boolean) -> Unit = {},
    trailingIcon: @Composable (() -> Unit)? = null,
) {
    val historyEntries by HistoryStore.entries.collectAsState()
    var urlText by remember { mutableStateOf(currentUrl) }
    var isFocused by remember { mutableStateOf(false) }

    LaunchedEffect(currentUrl, isFocused) {
        if (!isFocused) {
            urlText = currentUrl
        }
    }

    val completion =
        remember(urlText, historyEntries) {
            HistoryStore.bestUrlCompletion(urlText)
        }
    val displayCompletion =
        remember(urlText, completion) {
            inlineCompletionDisplay(input = urlText, fullCompletion = completion)
        }
    val completionSuffix =
        remember(urlText, displayCompletion, isFocused) {
            inlineCompletionSuffix(
                input = urlText,
                displayCompletion = displayCompletion,
                isFocused = isFocused,
            )
        }

    BasicTextField(
        value = urlText,
        onValueChange = { urlText = it },
        singleLine = true,
        textStyle = textStyle,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
        keyboardActions =
            KeyboardActions(onGo = {
                resolvedNavigationUrl(input = urlText, fullCompletion = completion)?.let(onNavigate)
            }),
        decorationBox = { inner ->
            Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, shape).padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    if (urlText.isEmpty()) Text(placeholder, style = textStyle, maxLines = 1)
                    inner()
                }
            if (!completionSuffix.isNullOrEmpty()) {
                Text(
                    text = completionSuffix,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
                    maxLines = 1,
                )
            }
                trailingIcon?.invoke()
            }
        },
        modifier = modifier.onFocusChanged { isFocused = it.isFocused; onEditingChanged(it.isFocused) },
    )
}

private fun resolvedNavigationUrl(
    input: String,
    fullCompletion: String?,
): String? {
    val trimmed = input.trim()
    if (trimmed.isEmpty()) {
        return null
    }
    if (!fullCompletion.isNullOrBlank()) {
        return fullCompletion
    }
    return if (startsWithScheme(trimmed)) trimmed else "https://$trimmed"
}

private fun inlineCompletionSuffix(
    input: String,
    displayCompletion: String?,
    isFocused: Boolean,
): String? {
    val trimmed = input.trim()
    if (!isFocused || trimmed.isEmpty() || displayCompletion.isNullOrEmpty()) {
        return null
    }
    if (!displayCompletion.startsWith(trimmed, ignoreCase = true) || displayCompletion.length <= trimmed.length) {
        return null
    }
    return displayCompletion.substring(trimmed.length)
}

private fun inlineCompletionDisplay(
    input: String,
    fullCompletion: String?,
): String? {
    val trimmed = input.trim()
    if (trimmed.isEmpty() || fullCompletion.isNullOrBlank()) {
        return null
    }

    return completionDisplayCandidates(fullCompletion = fullCompletion, input = trimmed)
        .firstOrNull { candidate ->
            candidate.length > trimmed.length && candidate.startsWith(trimmed, ignoreCase = true)
        }
}

private fun completionDisplayCandidates(
    fullCompletion: String,
    input: String,
): List<String> {
    if (startsWithScheme(input)) {
        return listOf(fullCompletion)
    }

    val noScheme = stripScheme(fullCompletion)
    val noWww = stripLeadingWww(noScheme)
    return listOf(noWww, noScheme, fullCompletion).distinct()
}

private fun startsWithScheme(value: String): Boolean = value.startsWith("http://", ignoreCase = true) || value.startsWith("https://", ignoreCase = true)

private fun stripScheme(value: String): String {
    val schemeIndex = value.indexOf("://")
    return if (schemeIndex == -1) value else value.substring(schemeIndex + 3)
}

private fun stripLeadingWww(value: String): String = if (value.startsWith("www.", ignoreCase = true)) value.substring(4) else value
