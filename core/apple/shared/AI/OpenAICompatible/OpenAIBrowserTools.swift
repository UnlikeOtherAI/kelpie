import Foundation

/// A browser tool offered to an OpenAI-compatible model. Every tool maps to an
/// existing Kelpie router method, so tab resolution, validation and the
/// script-recording gate are the same as for any other API caller.
struct OpenAIBrowserTool: Sendable {
    enum ArgumentType: String, Sendable {
        case string
        case integer
        case boolean
    }

    struct Argument: Sendable {
        let name: String
        let type: ArgumentType
        let description: String
        let required: Bool
        let enumValues: [String]?

        init(_ name: String, _ type: ArgumentType, _ description: String, required: Bool = false, enumValues: [String]? = nil) {
            self.name = name
            self.type = type
            self.description = description
            self.required = required
            self.enumValues = enumValues
        }
    }

    enum SanitizedArguments {
        case valid([String: Any])
        case invalid(String)
    }

    let name: String
    let routerMethod: String
    let description: String
    let arguments: [Argument]
    /// Changes page state; offered only when the caller allowed actions.
    let isAction: Bool

    var definition: [String: Any] {
        var properties: [String: Any] = [:]
        for argument in arguments {
            var schema: [String: Any] = ["type": argument.type.rawValue, "description": argument.description]
            if let enumValues = argument.enumValues { schema["enum"] = enumValues }
            properties[argument.name] = schema
        }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": arguments.filter(\.required).map(\.name)
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    /// Keeps only declared arguments of the declared type. Model-supplied
    /// `tabId`, `windowId` or anything else is dropped.
    func sanitize(_ raw: [String: Any]) -> SanitizedArguments {
        var clean: [String: Any] = [:]
        for argument in arguments {
            guard let value = raw[argument.name], !(value is NSNull) else {
                if argument.required { return .invalid("Missing required argument \"\(argument.name)\".") }
                continue
            }
            switch argument.type {
            case .string:
                guard let string = value as? String else { return .invalid("\"\(argument.name)\" must be a string.") }
                if let enumValues = argument.enumValues, !enumValues.contains(string) {
                    return .invalid("\"\(argument.name)\" must be one of \(enumValues.joined(separator: ", ")).")
                }
                clean[argument.name] = String(string.prefix(4_000))
            case .integer:
                guard let number = value as? NSNumber else { return .invalid("\"\(argument.name)\" must be an integer.") }
                clean[argument.name] = number.intValue
            case .boolean:
                guard let flag = value as? Bool else { return .invalid("\"\(argument.name)\" must be a boolean.") }
                clean[argument.name] = flag
            }
        }
        return .valid(clean)
    }
}

enum OpenAIBrowserToolCatalog {
    private typealias Argument = OpenAIBrowserTool.Argument

    static let observation: [OpenAIBrowserTool] = [
        make("get_current_url", "get-current-url", "Return the URL and title of the tab."),
        make(
            "get_page_text",
            "get-page-text",
            "Return the readable text of the page.",
            [Argument("selector", .string, "Optional CSS selector to read only part of the page")]
        ),
        make(
            "get_visible_elements",
            "get-visible-elements",
            "List elements visible in the viewport with tag, text, role and position.",
            [Argument("interactableOnly", .boolean, "Only return links, buttons and form controls")]
        ),
        make(
            "find_element",
            "find-element",
            "Find one element by its visible text and optional ARIA role. Returns a reusable CSS selector.",
            [
                Argument("text", .string, "Visible text to search for", required: true),
                Argument("role", .string, "Optional ARIA role such as button, link or textbox")
            ]
        ),
        make(
            "get_form_state",
            "get-form-state",
            "Return every form field with its selector, label, type, value and validation state.",
            [Argument("selector", .string, "Optional CSS selector of one form")]
        ),
        make(
            "get_accessibility_tree",
            "get-accessibility-tree",
            "Return the accessibility tree (roles and names) of the page.",
            [
                Argument("maxDepth", .integer, "Maximum depth, default 5"),
                Argument("interactableOnly", .boolean, "Only include interactive elements")
            ]
        ),
        make(
            "wait_for_element",
            "wait-for-element",
            "Wait until an element matching a CSS selector exists.",
            [
                Argument("selector", .string, "CSS selector", required: true),
                Argument("timeout", .integer, "Timeout in milliseconds, default 5000")
            ]
        )
    ]

    static let actions: [OpenAIBrowserTool] = [
        make(
            "click",
            "click",
            "Click the element matching a CSS selector.",
            [Argument("selector", .string, "CSS selector from find_element or get_form_state", required: true)],
            isAction: true
        ),
        make(
            "fill",
            "fill",
            "Replace the value of an input or textarea.",
            [
                Argument("selector", .string, "CSS selector of the field", required: true),
                Argument("value", .string, "Text to enter", required: true)
            ],
            isAction: true
        ),
        make(
            "select_option",
            "select-option",
            "Choose an option of a <select> element by value.",
            [
                Argument("selector", .string, "CSS selector of the select element", required: true),
                Argument("value", .string, "Option value", required: true)
            ],
            isAction: true
        ),
        make(
            "check",
            "check",
            "Check a checkbox or radio button.",
            [Argument("selector", .string, "CSS selector", required: true)],
            isAction: true
        ),
        make(
            "uncheck",
            "uncheck",
            "Uncheck a checkbox.",
            [Argument("selector", .string, "CSS selector", required: true)],
            isAction: true
        )
    ]

    static func tools(allowActions: Bool) -> [OpenAIBrowserTool] {
        allowActions ? observation + actions : observation
    }

    static func tool(named name: String) -> OpenAIBrowserTool? {
        (observation + actions).first { $0.name == name }
    }

    private static func make(
        _ name: String,
        _ routerMethod: String,
        _ description: String,
        _ arguments: [Argument] = [],
        isAction: Bool = false
    ) -> OpenAIBrowserTool {
        OpenAIBrowserTool(name: name, routerMethod: routerMethod, description: description, arguments: arguments, isAction: isAction)
    }
}
