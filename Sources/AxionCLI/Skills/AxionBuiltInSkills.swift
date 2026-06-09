import OpenAgentSDK

/// Convenience namespace for Axion's built-in desktop automation skills.
///
/// Mirrors the SDK's `BuiltInSkills` pattern — a caseless enum serving as a
/// namespace, with each static property returning a new `Skill` value instance.
///
/// ```swift
/// let registry = SkillRegistry()
/// registry.register(AxionBuiltInSkills.screenshotAnalyze)
/// ```
public enum AxionBuiltInSkills {

    // MARK: - screenshot-analyze

    /// Captures the current screen and produces a structured analysis of window
    /// contents and UI elements using both visual (screenshot) and structural
    /// (AX tree) data.
    public static var screenshotAnalyze: Skill {
        Skill(
            name: "screenshot-analyze",
            description: "Capture and analyze the current screen, combining visual screenshot with accessibility tree data to produce a structured description of UI elements.",
            aliases: ["sa", "analyze", "screen"],
            userInvocable: true,
            toolRestrictions: nil,
            promptTemplate: """
            Analyze the current screen content. Follow these steps:

            ## Step 1: Capture visual context
            1. Call `screenshot` to capture the current screen.
            2. Call `list_windows` to identify all visible windows.
            3. Call `get_window_state` on the frontmost window to get its title, bounds, and state.

            ## Step 2: Analyze UI structure
            1. Call `get_accessibility_tree` on the frontmost window to extract the UI element hierarchy.
            2. Identify key interactive elements: buttons, text fields, menus, lists, tables.
            3. Note the current focus state and any selected items.

            ## Step 3: Synthesize analysis
            Provide a structured description:
            - **Active Application**: Window title and app name
            - **Window Layout**: Position and size of visible windows
            - **UI Elements**: Key interactive elements with their roles and current values
            - **Content Summary**: What the user is currently viewing or working on
            - **Notable State**: Any alerts, dialogs, error messages, or pending actions
            """,
            whenToUse: "User needs to analyze current screen content, describe UI elements on screen, take a screenshot for analysis, or understand the current window state",
            argumentHint: "[focus description]"
        )
    }

    /// Registers all built-in desktop skills into the given registry.
    ///
    /// Call this BEFORE `registerDiscoveredSkills()` so that filesystem
    /// skills with the same name can override built-in defaults.
    public static func registerAll(into registry: SkillRegistry) {
        registry.register(screenshotAnalyze)
        registry.register(dataExtract)
        registry.register(formFill)
    }

    // MARK: - data-extract

    /// Extracts structured data (tables, lists, text) from the current window's
    /// accessibility tree.
    public static var dataExtract: Skill {
        Skill(
            name: "data-extract",
            description: "Extract structured data (tables, lists, text content) from the current application window's UI elements.",
            aliases: ["extract", "de"],
            userInvocable: true,
            toolRestrictions: nil,
            promptTemplate: """
            Extract structured data from the current application window. Follow these steps:

            ## Step 1: Identify the data source
            1. Call `list_windows` to find the target window.
            2. Call `get_accessibility_tree` on the relevant window to discover UI elements containing data.
            3. Identify data containers: tables (AXTable), lists (AXList), text groups (AXGroup), outline views (AXOutline).

            ## Step 2: Extract data
            Based on the data structure found:
            - **Table**: Extract column headers and row values from AXTable/AXRow/AXCell elements.
            - **List**: Extract items from AXList/AXStaticText elements.
            - **Outline**: Extract hierarchical items from AXOutline with their indentation levels.
            - **Free text**: Extract text from AXStaticText/AXTextArea elements.

            ## Step 3: Format output
            Return the extracted data in the user's requested format:
            - If the user asked for a specific format (JSON, CSV, table), use that format.
            - Otherwise, present as a clean markdown table or list.
            - Include column headers when extracting tabular data.
            - Note any truncated or partially visible data.
            """,
            whenToUse: "User needs to extract data from an on-screen application, get file listings, read table content, or collect text from UI elements",
            argumentHint: "[data type or filter]"
        )
    }

    // MARK: - form-fill

    /// Identifies form fields in the current window and fills them with
    /// user-supplied data.
    public static var formFill: Skill {
        Skill(
            name: "form-fill",
            description: "Identify form fields in the current window and automatically fill them with user-provided data.",
            aliases: ["fill", "ff"],
            userInvocable: true,
            toolRestrictions: nil,
            promptTemplate: """
            Fill form fields in the current application window. Follow these steps:

            ## Step 1: Identify form fields
            1. Call `get_accessibility_tree` on the frontmost window to discover form elements.
            2. Identify fillable elements: text fields (AXTextField), text areas (AXTextArea), combo boxes (AXComboBox), checkboxes (AXCheckBox), radio buttons (AXRadioButton), pop-up buttons (AXPopUpButton).
            3. For each field, note its label (AXLabel or title), current value, and role.

            ## Step 2: Map user data to fields
            From the user's arguments, extract field-value pairs. Match them to form fields:
            - Match by label text (case-insensitive, partial match).
            - Common aliases: "username"/"email"/"account" → first text field; "password"/"pass" → secure field.
            - If no explicit mapping, fill fields in top-to-bottom, left-to-right order.

            ## Step 3: Fill fields
            For each mapped field:
            1. **Text fields**: Click the field to focus, then use `type_text` to enter the value. Clear existing content first by selecting all (Cmd+A) then typing.
            2. **Checkboxes/Radio**: Use `click` to toggle to the desired state.
            3. **Dropdowns/Select**: Use `click` to open, then click the target option.
            4. After filling each field, verify the value was entered correctly.

            ## Step 4: Report results
            List all fields filled with their values. Note any fields that could not be filled or matched.
            Do NOT submit the form unless the user explicitly asks.
            """,
            whenToUse: "User needs to fill in a form, enter data into multiple fields, or auto-complete a login or registration form",
            argumentHint: "[field=value ...]"
        )
    }
}
