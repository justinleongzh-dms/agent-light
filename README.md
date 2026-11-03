# Agent Light

A small traffic light that floats in the corner of a Mac screen and shows what Claude Code is doing, across all open sessions.

| Light | Meaning |
|---|---|
| 🔴 Red, flashing | A session stopped and needs you (a question, a permission, an approval) |
| 🟡 Yellow, pulsing | A session is working |
| 🟢 Green, flashing | Everything just finished. Flashes for at least 10 seconds, then until you switch back to the Claude app |
| 🟢 Green, steady | Nothing needs you |

If any session needs you, the light is red, even when others are still working.

Drag the light to move it. Right-click it to change its size or quit.

## How it works

1. Claude Code [hooks](https://code.claude.com/docs/en/hooks) run `hook.py` at set moments: you send a message, a tool starts or ends, Claude asks for permission, a reply ends, a session closes.
2. `hook.py` writes that session's state (`working`, `waiting` or `idle`) to its own file in `~/.claude/agent-light/sessions/`.
3. The app (`light.swift`) reads those files 10 times a second and lights one lamp.

The hooks only write small files. They print nothing, so they add nothing to Claude's context. Each one takes about 0.07 s.

## Install

Needs macOS with the Xcode Command Line Tools (`xcode-select --install`), which also provide `/usr/bin/python3`.

1. Copy the code and build the app:
   ```bash
   mkdir -p ~/.claude/agent-light
   cp light.swift hook.py ~/.claude/agent-light/
   cd ~/.claude/agent-light
   swiftc -O light.swift -o AgentLight
   open AgentLight
   ```
2. Add the `"hooks"` section from `hooks-example.json` to `~/.claude/settings.json`. If you already have hooks, merge the lists rather than replacing them.
3. Optional, start it at login: in `com.agentlight.plist`, replace `YOUR_NAME` with your Mac username, then:
   ```bash
   cp com.agentlight.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agentlight.plist
   ```

## Limits

- It only sees Claude Code sessions (the terminal CLI, or the Code tab in the Claude desktop app). Chat and Cowork conversations don't run hooks on your Mac, so it can't see them.
- The green flash stops when the Claude desktop app is in front. If you only use the terminal CLI, it flashes until your next message.
- If you stop Claude mid-reply, that session can stay yellow for up to 15 minutes.
- Sessions not heard from in 12 hours are ignored.

## Remove

1. Delete the `"hooks"` section from `~/.claude/settings.json`.
2. If you set up start at login: `launchctl bootout gui/$(id -u)/com.agentlight`, then delete `~/Library/LaunchAgents/com.agentlight.plist`.
3. Right-click the light and choose Quit light.

## Credit

Inspired by [eternityspring/agent-light](https://github.com/eternityspring/agent-light), which drives a physical Arduino traffic light. This version is screen-only, written in Swift and Python, with no dependencies to install.

MIT licence.
