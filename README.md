# Snappr

A tiny macOS menu bar app that auto-pastes screenshots into whatever you're typing in.

Inspired by [Wispr Flow](https://wisprflow.ai)'s "tap-modifier-twice to arm" UX. Double-tap **Ctrl** to arm, take screenshots normally, and they land in your focused input — Claude Code chat, Cursor, Slack, Notes, anywhere. Tap **Ctrl** or **Esc** once to disarm.

No more saving screenshots to Desktop, dragging them into a chat box, then deleting them later.

## Why

If you build with AI coding agents (Claude Code, Cursor, Copilot Chat, ChatGPT desktop), you paste screenshots constantly — bug repros, design references, error states. The default macOS flow is: `Cmd+Shift+4` → save to Desktop → drag into chat → manually delete the file later. Snappr collapses that to: arm, screenshot, done.

## Features

- **Armed mode** — double-tap Ctrl to enter, single Ctrl tap or Esc to exit.
- **Floating HUD** — a small pill at the bottom of the screen with a pulsing dot so you never forget you're armed.
- **Smart paste routing** — sends `Cmd+V` to native apps (Notes, Cursor, Slack), `Ctrl+V` to terminals (iTerm2, Terminal, Ghostty, kitty, Alacritty, WezTerm, Warp, Hyper) so TUIs like Claude Code can read the image off the clipboard.
- **Focus check** — if you're not on an editable field when the screenshot lands, Snappr leaves it on the clipboard and shows a "⌘V to paste" hint instead of pasting into the wrong place.
- **Status icon** — `○ Snappr` when idle, `● Snappr` when armed.

## Install

You'll need macOS 13+ and Xcode (for the Swift toolchain).

```bash
git clone https://github.com/lavanpuri1999/Snappr.git
cd Snappr
./build-app.sh
open Snappr.app
```

The build script compiles a release binary, wraps it in a `.app` bundle (so macOS Accessibility permission can attach to a stable bundle ID), ad-hoc signs it, and leaves `Snappr.app` in the project root.

## First-run setup

On first launch macOS will prompt for Accessibility permission. Snappr needs it to:
- Listen for the double-Ctrl global hotkey
- Read which app/input has focus
- Synthesize the `Cmd+V` / `Ctrl+V` keystroke

If you miss the prompt:

1. **System Settings → Privacy & Security → Accessibility**
2. Click `+`, navigate to `Snappr.app`, add it
3. Toggle it on
4. Quit and reopen Snappr

You also want screenshots going to the clipboard. Either:
- Hold **Ctrl** with your screenshot shortcut (`Ctrl+Cmd+Shift+4` for selection → clipboard), or
- Set it as the default: `Cmd+Shift+5` → **Options** → **Save to: Clipboard**

## Usage

Click into any text input, then **double-tap Ctrl** to arm. Press **Ctrl** (single tap) or **Esc** when done.

### Screenshots

1. Arm in the input you want screenshots to land in.
2. Take a screenshot from anywhere — Snappr pastes it back into the armed input automatically.

### Videos

1. Arm anywhere.
2. Record a screen video (saves to Desktop) — Snappr extracts the first 20 frames at 1 fps; HUD shows "N frames ready · disarm to paste".
3. Click into the input you want the frames in, then disarm — frames flush in sequence.

## License

MIT.
