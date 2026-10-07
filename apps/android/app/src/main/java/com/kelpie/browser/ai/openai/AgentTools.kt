package com.kelpie.browser.ai.openai

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

enum class ArgType(
    val jsonType: String,
) {
    STRING("string"),
    INT("integer"),
    BOOLEAN("boolean"),
}

data class ToolArg(
    val name: String,
    val type: ArgType,
    val description: String,
    val required: Boolean = false,
)

/** One OpenAI function tool backed by an existing Kelpie router method. */
data class AgentTool(
    val name: String,
    val method: String,
    val description: String,
    val args: List<ToolArg> = emptyList(),
    val requiresActions: Boolean = false,
) {
    fun definition(): JsonObject {
        val properties =
            args.associate { arg ->
                arg.name to
                    JsonObject(
                        mapOf("type" to JsonPrimitive(arg.type.jsonType), "description" to JsonPrimitive(arg.description)),
                    )
            }
        val parameters =
            JsonObject(
                mapOf(
                    "type" to JsonPrimitive("object"),
                    "properties" to JsonObject(properties),
                    "required" to JsonArray(args.filter { it.required }.map { JsonPrimitive(it.name) }),
                    "additionalProperties" to JsonPrimitive(false),
                ),
            )
        val function =
            JsonObject(
                mapOf(
                    "name" to JsonPrimitive(name),
                    "description" to JsonPrimitive(description),
                    "parameters" to parameters,
                ),
            )
        return JsonObject(mapOf("type" to JsonPrimitive("function"), "function" to function))
    }
}

/**
 * The browser-agent tool catalogue. Navigation, script evaluation, cookies, storage,
 * screenshots and tab/window management are deliberately never offered.
 */
object AgentTools {
    const val MAX_WAIT_TIMEOUT_MS = 30_000

    private val selector = ToolArg("selector", ArgType.STRING, "CSS selector of the target element", required = true)

    val all: List<AgentTool> =
        listOf(
            AgentTool("get_current_url", "get-current-url", "Get the URL and title of the current page."),
            AgentTool(
                "get_page_text",
                "get-page-text",
                "Get the readable text of the page or of one element.",
                listOf(ToolArg("selector", ArgType.STRING, "Optional CSS selector to limit the text to one element")),
            ),
            AgentTool(
                "get_visible_elements",
                "get-visible-elements",
                "List elements currently visible in the viewport with their selectors.",
                listOf(ToolArg("interactableOnly", ArgType.BOOLEAN, "Only include links, buttons and form fields")),
            ),
            AgentTool(
                "find_element",
                "find-element",
                "Find the first visible element whose text contains the given text.",
                listOf(
                    ToolArg("text", ArgType.STRING, "Text to search for", required = true),
                    ToolArg("role", ArgType.STRING, "Optional ARIA role filter"),
                ),
            ),
            AgentTool(
                "get_form_state",
                "get-form-state",
                "Describe the forms on the page, their fields, values and validity.",
                listOf(ToolArg("selector", ArgType.STRING, "Optional CSS selector of one form")),
            ),
            AgentTool(
                "get_accessibility_tree",
                "get-accessibility-tree",
                "Get the semantic accessibility tree of the page.",
                listOf(
                    ToolArg("maxDepth", ArgType.INT, "Maximum tree depth"),
                    ToolArg("interactableOnly", ArgType.BOOLEAN, "Only include interactive nodes"),
                ),
            ),
            AgentTool(
                "wait_for_element",
                "wait-for-element",
                "Wait until an element matching the selector is visible.",
                listOf(selector, ToolArg("timeout", ArgType.INT, "Timeout in milliseconds (max 30000)")),
            ),
            AgentTool("click", "click", "Click an element.", listOf(selector), requiresActions = true),
            AgentTool(
                "fill",
                "fill",
                "Replace the value of a text field.",
                listOf(selector, ToolArg("value", ArgType.STRING, "Value to enter", required = true)),
                requiresActions = true,
            ),
            AgentTool(
                "select_option",
                "select-option",
                "Choose an option in a select element.",
                listOf(selector, ToolArg("value", ArgType.STRING, "Option value to select", required = true)),
                requiresActions = true,
            ),
            AgentTool("check", "check", "Check a checkbox or radio button.", listOf(selector), requiresActions = true),
            AgentTool("uncheck", "uncheck", "Uncheck a checkbox.", listOf(selector), requiresActions = true),
        )

    fun offered(allowActions: Boolean): List<AgentTool> = all.filter { allowActions || !it.requiresActions }

    fun definitions(allowActions: Boolean): JsonArray = JsonArray(offered(allowActions).map { it.definition() })

    /**
     * Keeps only declared arguments with the declared type. Model-supplied `tabId`,
     * `windowId` and any unknown keys are dropped. Returns null plus the missing name
     * when a required argument is absent.
     */
    fun sanitize(
        tool: AgentTool,
        raw: JsonObject,
    ): Pair<Map<String, Any?>?, String?> {
        val clean = linkedMapOf<String, Any?>()
        for (arg in tool.args) {
            val value = coerce(arg.type, raw[arg.name])
            if (value != null) clean[arg.name] = value
        }
        if (tool.name == "wait_for_element") {
            clean["timeout"] = ((clean["timeout"] as? Int) ?: 5_000).coerceIn(0, MAX_WAIT_TIMEOUT_MS)
        }
        val missing = tool.args.firstOrNull { it.required && clean[it.name] == null }
        return if (missing != null) null to missing.name else clean to null
    }

    private fun coerce(
        type: ArgType,
        element: JsonElement?,
    ): Any? {
        val primitive = element as? JsonPrimitive ?: return null
        return when (type) {
            ArgType.STRING -> if (primitive.isString) primitive.content else null
            ArgType.INT -> OpenAIJson.int(primitive)
            ArgType.BOOLEAN ->
                OpenAIJson.boolean(primitive)
                    ?: primitive.content
                        .lowercase()
                        .takeIf { primitive.isString && it in setOf("true", "false") }
                        ?.toBoolean()
        }
    }
}
