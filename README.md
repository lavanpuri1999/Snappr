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

1. Click into any text input (chat box, code editor, terminal, note, message).
2. **Double-tap Ctrl** within ~0.4 seconds. The HUD appears: a pulsing red dot and "Listening · Esc to stop".
3. Take a screenshot. The image is auto-pasted into your input.
4. Take another. And another. Keep going.
5. Press **Ctrl** (single tap) or **Esc** when done.

If you click into a non-editable area between screenshots, Snappr will skip auto-pasting that one and flash "On clipboard · ⌘V to paste". The next screenshot, if your cursor is back in an input, will paste normally.

## Iterating

After editing `Sources/Snappr/main.swift`:

```bash
./build-app.sh
killall Snappr 2>/dev/null
open Snappr.app
```

### About the re-grant loop

Each rebuild produces a new ad-hoc code signature, which macOS treats as a different app. The Accessibility toggle stays on but points at the old signature, so you'll get re-prompted.

**Workaround:** in System Settings → Accessibility, click the `–` button to remove Snappr, then re-add it via `+`. Re-grants stick until the next rebuild.

**Long-term fix:** create a self-signed code signing certificate in Keychain Access and update `build-app.sh` to use `codesign --sign "Your Cert Name"` instead of `--sign -`. Then rebuilds preserve the signature and the AX grant persists. Not done yet — PRs welcome.

## How it works

Roughly 350 lines of Swift in a single file. The pieces:

- **`CGEventTap`** listens system-wide for `flagsChanged` events. When it sees Ctrl-down twice within 0.4s, it fires `arm()`. While armed, it watches for Ctrl or Escape and fires `disarm()`.
- **`PasteboardWatcher`** polls `NSPasteboard.general.changeCount` every 150ms. macOS has no clipboard-change notification API; polling is the documented approach. When the change count moves and the new content is image-typed (`public.png` or `public.tiff`), it fires the callback.
- **Focus check** uses `AXUIElementCopyAttributeValue` against `kAXFocusedUIElementAttribute` on the system-wide AX element. We accept `kAXTextFieldRole`, `kAXTextAreaRole`, `kAXComboBoxRole`, an `AXEditable` attribute set to true, or any element where `kAXValueAttribute` is settable.
- **Terminal routing** matches `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` against a small allowlist of terminal bundles. If matched, we send Ctrl+V instead of Cmd+V — terminals intercept Cmd+V to paste *text only* from the clipboard, but TUIs running inside them (like Claude Code) bind Ctrl+V to "read NSPasteboard directly and grab the image."
- **`NSPanel`** with `.borderless`, `.nonactivatingPanel`, and `.floating` level renders the HUD without stealing focus.

## Limitations

- **One image at a time.** macOS clipboard is single-slot. Snappr replaces the clipboard contents on each capture.
- **Terminal allowlist is hand-maintained.** If you use a terminal not on the list, paste won't reach the TUI inside. Add its bundle ID to the `Terminals.bundleIDs` set in `main.swift` and rebuild. Find it via `mdls -name kMDItemCFBundleIdentifier /Applications/YourTerminal.app`.
- **Some Electron apps with custom inputs** may report a non-editable focused element. The screenshot stays on clipboard in that case; manual `Cmd+V` works.
- **No video / multi-frame support.** A WIP branch explores extracting frames from a screen recording and pasting them as a sequence; not yet on `main`.

## Roadmap

- Configurable hotkey (currently hardcoded double-Ctrl)
- Configurable disarm key (currently single Ctrl + Esc)
- Per-app paste routing config
- Video → frame sequence (1 fps, ≤15s cap)
- Self-signed cert in build script
- Login-item / launch-at-startup option

## License

MIT. Use it however you like.
