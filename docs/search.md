# Searching

Press **Super + Space** and just type. Results from several places are mixed
together, best matches first.

## What it finds

| Type this… | …and you get |
|---|---|
| nothing at all | your open windows, the apps you use most, files you opened recently |
| an app name | the app. If it's already open, **Enter** jumps to it and **Shift + Enter** opens a new window |
| a nickname like `chrome`, `browser`, `files`, `code`, `terminal` | the app you actually use for that |
| part of a window's title | that window, wherever it is |
| `space 3` | the windows on workspace 3 |
| part of a file or folder name | recent files first, then anything in your home folder |
| a sum like `12*7` or `(1+2)^3` | the answer; **Enter** copies it |
| a number like `14` | "Go to workspace 14" |
| anything | a **Search the web** row at the bottom, opening your browser |

## It learns

- Apps you open from the search **move up** the list.
- Files and folders you open show up as **Recent** next time.

## Windows: close and move

Highlight a window (or an app that's open) and press:

- **Ctrl + W** to close it. The search stays open, so you can close more.
- **Ctrl + M** to move it. Type a workspace number and press **Enter**.

## Your own nicknames

Want `ff` to open Firefox? Create `~/.config/omarchy/super-spaces/aliases.json`:

```json
{
  "firefox": "ff fox",
  "com.thisisgm.flea": "files"
}
```

The left side is the app's ID (its `.desktop` file name without `.desktop`),
the right side is the words you want to type. Changes apply the next time you
open the search.

## Where files come from

File search looks through your **home folder** while you type, skipping hidden
tool folders, plus `~/.config`. Nothing runs in the background when the
search is closed.
