package com.kelpie.browser.ai.openai

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The agent's own structured plan. The model writes it with the `update_task_list`
 * tool; Kelpie uses it to tell whether the model still has work left when it tries to
 * stop, and returns it to the caller. Updating the list is bookkeeping, not a browser
 * step, so it does not use the step budget.
 */
class AgentTaskList {
    data class Item(
        val task: String,
        val done: Boolean,
    ) {
        fun toPublic(): Map<String, Any?> = linkedMapOf("task" to task, "done" to done)
    }

    var items: List<Item> = emptyList()
        private set

    val unfinished: List<Item> get() = items.filter { !it.done }

    /** Replaces the list from a tool call and returns the tool result JSON. */
    fun apply(call: AssembledToolCall): String {
        val raw =
            call.parsedArguments()?.get("tasks") as? JsonArray
                ?: return OpenAIJson.encode(
                    OpenAIJson.fromAny(mapOf("ok" to false, "error" to "Send {\"tasks\": [{\"task\": \"…\", \"done\": false}]}.")),
                )
        items =
            raw.take(MAX_ITEMS).mapNotNull { entry ->
                val obj = entry as? JsonObject ?: return@mapNotNull null
                val task = OpenAIJson.string(obj["task"])?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                Item(task.take(MAX_TASK_CHARS), OpenAIJson.boolean(obj["done"]) ?: false)
            }
        return OpenAIJson.encode(OpenAIJson.fromAny(linkedMapOf("ok" to true, "remaining" to unfinished.map { it.task })))
    }

    /** Kelpie's one-time reminder when the model answers with open tasks. */
    fun unfinishedReminder(): String? {
        val open = unfinished
        if (open.isEmpty()) return null
        val list = open.mapIndexed { index, item -> "${index + 1}. ${item.task}" }.joinToString("\n")
        return "Kelpie: your task list still has unfinished tasks:\n$list\n" +
            "If they still need doing, continue with the tools. If they are already done, mark them done and repeat your " +
            "complete final answer, because only your last message is shown to the person. If they cannot be done, " +
            "give your complete final answer and explain why."
    }

    companion object {
        const val TOOL_NAME = "update_task_list"
        const val MAX_ITEMS = 20
        const val MAX_TASK_CHARS = 200

        fun definition(): JsonObject {
            val item =
                JsonObject(
                    mapOf(
                        "type" to JsonPrimitive("object"),
                        "properties" to
                            JsonObject(
                                mapOf(
                                    "task" to schema("string", "What needs doing"),
                                    "done" to schema("boolean", "True once done and verified"),
                                ),
                            ),
                        "required" to JsonArray(listOf(JsonPrimitive("task"), JsonPrimitive("done"))),
                    ),
                )
            val parameters =
                JsonObject(
                    mapOf(
                        "type" to JsonPrimitive("object"),
                        "properties" to
                            JsonObject(mapOf("tasks" to JsonObject(mapOf("type" to JsonPrimitive("array"), "items" to item)))),
                        "required" to JsonArray(listOf(JsonPrimitive("tasks"))),
                    ),
                )
            val description =
                "Record your plan as a list of tasks and mark tasks done once you have verified them. " +
                    "Send the whole list every time. This does not use a browser step."
            return JsonObject(
                mapOf(
                    "type" to JsonPrimitive("function"),
                    "function" to
                        JsonObject(
                            mapOf(
                                "name" to JsonPrimitive(TOOL_NAME),
                                "description" to JsonPrimitive(description),
                                "parameters" to parameters,
                            ),
                        ),
                ),
            )
        }

        private fun schema(
            type: String,
            description: String,
        ) = JsonObject(mapOf("type" to JsonPrimitive(type), "description" to JsonPrimitive(description)))
    }
}
