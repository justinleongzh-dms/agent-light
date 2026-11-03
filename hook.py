# Claude Code runs this at set moments (see the "hooks" section in ~/.claude/settings.json).
# Each session gets its own file in sessions/, so the traffic light can combine all open chats.
#
#   hook.py prompt      I sent a message               -> working
#   hook.py tool        Claude is about to use a tool  -> working, or waiting if the tool asks me something
#   hook.py tool-done   the tool finished              -> working
#   hook.py needs-you   Claude wants my permission     -> waiting
#   hook.py stop        Claude finished its reply      -> idle, or waiting if it ended on a blocking question
#   hook.py end         the session closed             -> its file is removed
#
# The light shows: waiting = red, working or asking = yellow, idle = green.

import json
import os
import sys

QUESTION_TOOLS = ["AskUserQuestion", "ExitPlanMode"]
WRAP_UP_TOOL = "mcp__ccd_turn__wrap_up"

folder = os.path.expanduser("~/.claude/agent-light/sessions")
os.makedirs(folder, exist_ok=True)

moment = sys.argv[1]
event = json.load(sys.stdin)
session_id = event.get("session_id", "unknown")
session_file = os.path.join(folder, session_id)

if moment == "end":
    if os.path.exists(session_file):
        os.remove(session_file)
    sys.exit(0)

previous = ""
if os.path.exists(session_file):
    with open(session_file) as f:
        previous = f.read().strip()

tool_name = event.get("tool_name", "")
tool_input = event.get("tool_input", {})

state = "working"
if moment == "tool" and tool_name in QUESTION_TOOLS:
    state = "waiting"
if moment == "tool" and tool_name == WRAP_UP_TOOL and tool_input.get("blocked"):
    state = "asking"  # the reply is about to end on a question the work is stuck on
if moment == "tool-done" and previous == "asking":
    state = "asking"
if moment == "needs-you":
    state = "waiting"
if moment == "stop" and previous == "asking":
    state = "waiting"
if moment == "stop" and previous != "asking":
    state = "idle"

with open(session_file, "w") as f:
    f.write(state)
