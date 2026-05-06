# AI Configuration & Setup Prompt

Copy and paste the prompt below into your favorite AI coding assistant (Claude, ChatGPT, Cursor, etc.) to automatically configure this script for your server. This prompt is engineered to handle discovery, framework integration, and custom setup.

---

### Senior Engineer Prompt for `peak-sprays` Integration

**Context:**
You are a Senior FiveM Developer. I have installed the `peak-sprays` resource, a high-performance graffiti system. I need you to configure it to match my server's environment perfectly.

**Your Objective:**
Analyze my server files, identify dependencies, and perform all necessary configuration steps to make the script production-ready.

**Step 1: Discovery Phase**
- Scan my server's resource folder to identify the active Framework (e.g., QBCore, ESX, QBox, or Custom).
- Identify the Inventory system (e.g., ox_inventory, qb-inventory, qs-inventory, etc.).
- Locate the Notification and Progress Bar systems being used.
- Confirm if `ox_lib` and `oxmysql` are installed and running.

**Step 2: Configuration Mapping**
- Based on your findings, update `shared/config.lua`. Ensure `Config.Framework` and `Config.SQLDriver` are set correctly.
- If I am using a custom framework or have modified core functions, use the hooks in `client/custom.lua` and `server/custom.lua` to override default logic (e.g., `Open.CustomNotify`, `Open.CustomProgressBar`).

**Step 3: Item Registration**
- Provide me with the exact code snippets or JSON data needed to register the items `spraypaint` and `spraycloth` in my specific inventory system.
- If using QBCore, provide the `shared/items.lua` entry. If using ESX, provide the SQL insert or `items.lua` entry.

**Step 4: Database Check**
- Ensure the SQL queries in the script are compatible with my database wrapper. If I use a custom wrapper, refactor the calls in `server/bridge.lua`.

**Step 5: Final Validation**
- Review `fxmanifest.lua` to ensure all script paths are correct.
- Check for any potential conflicts with other scripts (e.g., other spray scripts or DUI-based resources).
- Perform a final syntax check on all modified files.

**Instructions for the AI:**
- Do not make changes until you have confirmed the framework and inventory names.
- Ask for clarification if you cannot find a specific dependency.
- Prioritize using `custom.lua` files for overrides to keep the core logic clean.
