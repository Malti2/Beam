# Beam

A Spotlight-style command bar for macOS that turns natural language into
AppleScript and shell commands — powered by any OpenAI-compatible AI
endpoint you point it at.

Press the hotkey, type what you want your Mac to do, and Beam writes and
runs the commands. Anything potentially destructive asks for your explicit
confirmation first; everything else just runs.

## Features

- **Global hotkey** — left ⌘ + right ⌘ by default, configurable in Settings
  (⌥ Space, ⇧⌥ Space, ⌃⌥ Space).
- **Any AI endpoint** — OpenRouter is preset; add any OpenAI-compatible
  base URL. If the endpoint supports `/models`, Beam loads the list with
  search; otherwise you type the model name yourself. API keys live in the
  Keychain.
- **AppleScript + shell** — Beam picks the better tool per task: app
  control, Finder and system settings via AppleScript, files and text via
  zsh.
- **Safety gate** — commands the model flags as dangerous (or that match
  Beam's own destructive-pattern list) show a review dialog before they
  run.
- **Research passes (optional)** — Beam can gather information first
  (list a directory, read state) and use the result to build the right
  command. Configurable: on/off, max passes, single vs. multiple commands.
- **Native** — SwiftUI, menu bar app, no dock icon, dark glass panel.
- **Self-updating** — checks GitHub releases and installs new versions
  in place.

## Download

Grab the latest `Beam.zip` from
[Releases](https://github.com/Malti2/Beam/releases), unzip, move
`Beam.app` to `/Applications`.

The build is unsigned: on first launch, right-click the app and choose
**Open**. On the first start, macOS asks for **Accessibility access** —
Beam needs it for the global hotkey. AppleScript automation is asked the
first time Beam controls an app.

## Setup

1. Open Settings (menu bar icon → Settings…).
2. The **OpenRouter** endpoint is preset. Paste a key from
   [openrouter.ai/keys](https://openrouter.ai/keys) (free models work
   without credits, with a daily limit).
3. Click **Load models** and pick one — or type a model name manually.
4. Press left ⌘ + right ⌘ anywhere and go.

## Build it yourself

Requires Xcode and [XcodeGen](https://github.com/yonsm/XcodeGen)
(`brew install xcodegen`):

```bash
git clone https://github.com/Malti2/Beam.git
cd Beam
./Scripts/build.sh        # produces ./Beam.app
```

Every push and tag also builds on GitHub Actions; tags `v*` publish a
release with `Beam.zip`.

## Privacy

Beam sends your prompt plus basic system context (macOS version, home
directory path, date) to the endpoint you configured — nothing else, and
nowhere else. Commands run locally. Endpoint keys are stored in the
macOS Keychain.
