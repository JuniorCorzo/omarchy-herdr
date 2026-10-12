# omarchy-herdr

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Omarchy%204.0%20%7C%20Hyprland-brightgreen.svg)](https://github.com/omarchy)
[![Quickshell](https://img.shields.io/badge/Quickshell-0.3.1+-orange.svg)](https://quickshell.outfoxxed.me)

A native [Omarchy](https://github.com/omarchy) Quickshell menu plugin to dynamically browse, manage, and attach active [Herdr](https://herdr.dev) multi-agent persistent workspaces.

---

## Features

- **Native Quickshell & Omarchy 4.0 Integration**: Built using Wayland `WlrLayershell` overlay surfaces with keyboard focus isolation, smooth backdrop scrim, and keyboard-first ergonomics.
- **Dynamic Session Discovery**: Reads live Herdr state asynchronously via `herdr session list --json` without freezing the compositor UI thread.
- **Dynamic Terminal Detection (`xdg-terminal-exec`)**: Adheres to the XDG Default Terminal Execution specification, launching the user's configured terminal (Ghostty, Foot, Alacritty, Kitty, WezTerm) automatically.
- **Full Reactive Omarchy Theme Engine**: Binds to Omarchy shell color tokens (`Color.menu`, `Color.accent`, `Color.foreground`, `Color.background`, `Color.urgent`), instantly re-evaluating when switching Omarchy desktop themes at runtime.
- **Live Search & Fuzzy Filtering**: Filter active sessions on-the-fly by typing session names, runtime status, or workspace directory paths.
- **Visual Status Badges**: Distinguishes running vs. stopped sessions, highlights the designated `DEFAULT` workspace, and provides quick attachment triggers.
- **New Environment Creation**: Includes a one-click / shortcut (`Ctrl+N`) action to spawn a new Herdr environment.
- **Keyboard-First Workflow**: Full Vim-friendly and standard navigation (`Up`/`Down`, `Enter`, `Ctrl+N`, `Ctrl+R`, `Esc`).

---

## Architecture & Omarchy 4.0 Ecosystem

`omarchy-herdr` integrates directly into the Omarchy shell architecture via the Quickshell plugin specification.

```
                    ┌────────────────────────────┐
                    │     Hyprland Keybind       │
                    │   SUPER + CTRL + RETURN    │
                    └─────────────┬──────────────┘
                                  │
                                  ▼
                    ┌────────────────────────────┐
                    │    omarchy-shell IPC       │
                    │  (shell toggle ...herdr)   │
                    └─────────────┬──────────────┘
                                  │
                                  ▼
      ┌────────────────────────────────────────────────────────┐
      │                      Menu.qml                          │
      │  ┌───────────────────┐        ┌─────────────────────┐  │
      │  │ Reactive Color    │        │ Quickshell Process  │  │
      │  │ Singleton Binding │        │ + StdioCollector    │  │
      │  └───────────────────┘        └──────────┬──────────┘  │
      └──────────────────────────────────────────┼─────────────┘
                                                 │
                                                 ▼
                              ┌─────────────────────────────────────┐
                              │  herdr session list --json          │
                              └──────────────────┬──────────────────┘
                                                 │
                                                 ▼
                              ┌─────────────────────────────────────┐
                              │  xdg-terminal-exec herdr session... │
                              └─────────────────────────────────────┘
```

### Component Breakdown

1. **`manifest.json`**:
   Declares the plugin metadata, entry point (`Menu.qml`), and schema specification (`schemaVersion: 1`, `kinds: ["menu"]`).

2. **`Menu.qml`**:
   - Implements Omarchy shell hooks: `open(payloadJson)`, `close()`, `dismiss()`, and `toggle()`.
   - Spawns background queries through `Quickshell.Io.Process` and `StdioCollector` to parse JSON session arrays safely.
   - Leverages `qs.Commons` (`Color`, `Style`, `Border`, `Util`) and `qs.Ui` (`BorderSurface`, `PointerMoveGate`).
   - Launches user sessions in detached background processes via `Quickshell.execDetached(["xdg-terminal-exec", "herdr", "session", "attach", sessionName])`.

---

## Dynamic Theme Support

The plugin subscribes to Omarchy's central theme system. When you switch themes via `omarchy theme select <name>`, `Menu.qml` reactively re-evaluates all surface bindings without requiring a shell reload:

- `Color.menu.background`: Panel card background with theme-configured opacity.
- `Color.menu.text`: Base typography color.
- `Color.menu.border`: Border outlines matching theme geometry.
- `Color.menu.scrim`: Compositor overlay wash.
- `Color.menu.selectedBackground` & `Color.menu.selectedText`: Highlight and focus accents.
- `Color.urgent`: Visual indication for stopped or errored sessions.
- `Color.accent`: Primary brand highlights and action button states.

---

## Installation

### Method 1: Using Omarchy CLI (Recommended)

```bash
omarchy plugin add JuniorCorzo/omarchy-herdr
```

### Method 2: Manual Installation via Git

Clone the repository and symlink it into your local Omarchy plugins directory:

```bash
# Clone the repository
git clone https://github.com/JuniorCorzo/omarchy-herdr.git ~/Work/personal/omarchy-herdr

# Create the plugin symlink
ln -sfn ~/Work/personal/omarchy-herdr ~/.config/omarchy/plugins/juniorcorzo.herdr
```

---

## Configuration

### 1. Enable Plugin in `shell.json`

Add `"id": "juniorcorzo.herdr"` to the `"plugins"` array in your Omarchy shell configuration (`~/.config/omarchy/shell.json` or your dotfiles):

```json
{
  "plugins": [
    {
      "id": "juniorcorzo.herdr"
    }
  ]
}
```

### 2. Configure Hyprland Keybinding

Add the keybinding to your Hyprland user bindings file (`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + CTRL + RETURN", "Herdr sessions menu", "omarchy-shell shell toggle juniorcorzo.herdr")
```

### 3. Rescan Plugins

Notify `omarchy-shell` to reload the plugin registry:

```bash
omarchy-shell shell rescanPlugins
```

---

## Usage & Controls

Press <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>RETURN</kbd> to open the Herdr Sessions menu.

| Key / Action | Action Description |
| :--- | :--- |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Navigate sessions list |
| <kbd>Enter</kbd> | Attach selected session in default terminal |
| <kbd>Ctrl</kbd> + <kbd>N</kbd> | Create & attach new Herdr session |
| <kbd>Ctrl</kbd> + <kbd>R</kbd> | Refresh sessions list |
| Any character | Search / filter sessions by name, path, or status |
| <kbd>Esc</kbd> | Clear search filter or close menu |
| *Click Row* | Attach clicked session and dismiss menu |
| *Click Outside* | Close menu overlay |

---

## Requirements

- **Linux** (Wayland compositor, e.g., Hyprland)
- **Omarchy Shell 4.0+**
- **Quickshell 0.3.1+**
- **Herdr CLI** (`herdr` available in `$PATH`)
- **xdg-terminal-exec** (installed on Arch Linux via `pacman -S xdg-terminal-exec`)

---

## License

MIT License © 2026 [Junior Corzo](https://github.com/JuniorCorzo).
