# AI agents

Two things here: **find past AI chats** and **ask a quick question**.

## `ai` — find a past agent session

Type `ai` to list the AI coding sessions on this computer, newest first, with
the folder they ran in and how long ago.

- `ai tailscale` finds the session about Tailscale.
- **Enter** reopens it in a terminal, right where you left off.

Works with **omp**. Sessions from **Claude Code** and **Codex** show up too,
once you've used them on this computer.

Typing words from an old task (without `ai`) also shows the 3 best matching
sessions among your normal results.

## `ask` — ask a question, get the answer right here

`ask` sends your question to your **default AI agent**, which searches the
web and answers. The answer appears in the search box; no terminal opens.

```
ask what is the latest hyprland version
```

While it works you'll see *"Searching the web… 4 s"*. About 10 seconds later
the answer appears with source links. Then:

| Key | What it does |
|---|---|
| Enter | copy the answer |
| Ctrl + O | keep chatting with the agent in a terminal |
| ↑ / ↓ | scroll a long answer |
| Esc | back to the search |

### Ask is off at first

Each question uses a little of your AI plan, so `ask` starts **off**. To turn
it on: type `settings`, highlight **Ask AI agent (web search)**, press
**Enter**. When it's on, every search also ends with an **Ask AI** row.

### Which agent answers?

Your system's default agent: Omarchy menu → **Setup → Defaults → Agent**
(or `omarchy default agent <name>`).

- **omp** answers with your fast, cheap "smol" model, no extra thinking.
- **Claude Code, Codex, OpenCode, Pi, Gemini, Qwen** answer in the search too.
- Any other agent opens in a terminal instead.
