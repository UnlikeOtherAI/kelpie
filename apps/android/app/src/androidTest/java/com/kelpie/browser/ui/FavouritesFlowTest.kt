package com.kelpie.browser.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import com.kelpie.browser.MainActivity
import com.kelpie.browser.browser.BookmarkStore
import org.junit.Rule
import org.junit.Test
import java.util.UUID

/** Exercises the real browser entry, editor, touch drag and recoverable removal. */
class FavouritesFlowTest {
    @get:Rule
    val ui = createAndroidComposeRule<MainActivity>()

    @Test
    fun createNestDragRemoveAndUndo() {
        ui.waitForIdle()
        if (ui.onAllNodesWithText("Get Started").fetchSemanticsNodes().isNotEmpty()) {
            ui.onNodeWithText("Get Started").performClick()
        }
        ui.onNode(hasSetTextAction()).performTextReplacement("https://example.com/")
        ui.onNode(hasSetTextAction()).performImeAction()
        ui.onNodeWithContentDescription("More").performClick()
        ui.onNodeWithText("Bookmarks").performClick()
        ui.onNodeWithContentDescription("Add favourite or folder").performClick()
        ui.onNodeWithText("New Folder").performClick()
        val title = "Drag fixture ${UUID.randomUUID().toString().take(8)}"
        ui.onNodeWithTag("browser.bookmarks.name").performTextReplacement(title)
        ui.onNodeWithTag("browser.bookmarks.save").performClick()
        ui.onNodeWithText(title).assertIsDisplayed()
        val folder = BookmarkStore.nodes.value.single { it.title == title }
        ui.onNodeWithContentDescription("Actions for $title").performClick()
        ui.onNodeWithText("Add Current Page Here").performClick()
        ui.waitUntil(5000) { BookmarkStore.children(folder.id).isNotEmpty() }
        val page = BookmarkStore.children(folder.id).single()
        ui.onNodeWithTag("browser.bookmarks.row.${folder.id}").performClick()
        drag("Drag ${page.title}", "browser.bookmarks.root")
        ui.waitUntil(5000) { BookmarkStore.nodes.value.single { it.id == page.id }.parentId == null }
        ui.onNodeWithTag("browser.bookmarks.row.${folder.id}").performClick()
        ui.onNodeWithTag("browser.bookmarks.row.${page.id}").assertIsDisplayed()
        drag("Drag ${page.title}", "browser.bookmarks.row.${folder.id}")
        ui.onNodeWithTag("browser.bookmarks.row.${page.id}").assertDoesNotExist()
        ui.onNodeWithTag("browser.bookmarks.row.${folder.id}").performClick()
        ui.onNodeWithTag("browser.bookmarks.row.${page.id}").assertIsDisplayed()
        ui.onNodeWithContentDescription("Actions for $title").performClick()
        ui.onNodeWithText("Remove").performClick()
        ui.onNodeWithText("Remove this favourite?").assertIsDisplayed()
        ui.onNodeWithText("Remove").performClick()
        ui.onNodeWithText(title).assertDoesNotExist()
        ui.onNodeWithTag("browser.bookmarks.undo").performClick()
        ui.onNodeWithText(title).assertIsDisplayed()
        ui.onNodeWithTag("browser.bookmarks.row.${page.id}").assertIsDisplayed()
    }

    private fun drag(
        description: String,
        destinationTag: String,
    ) {
        val handle = ui.onNodeWithContentDescription(description)
        val origin = handle.fetchSemanticsNode().boundsInRoot.topLeft
        val destination =
            ui
                .onNodeWithTag(destinationTag, useUnmergedTree = true)
                .fetchSemanticsNode()
                .boundsInRoot.center - origin
        handle.performTouchInput { down(center) }
        ui.mainClock.advanceTimeBy(700)
        handle.performTouchInput {
            moveTo(destination, delayMillis = 400)
            up()
        }
        ui.waitForIdle()
    }
}
