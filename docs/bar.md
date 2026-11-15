# The bar

Super Spaces replaces Omarchy's workspace numbers in the top bar. It works the
same way, with one difference: **workspaces above 9 fold away**.

```
1 ■ 3 4 5 9 +2        ← two workspaces (say 12 and 14) are folded
1 ■ 3 4 5 9 - 12 14   ← click +2 to show them, click - to hide them again
```

## What you can do

- **Click a number** to go to that workspace.
- **Click the one you're on** to switch its layout (tiling, scrolling, floating).
- **Scroll** over the numbers to move left and right.
- **Click `+N`** to show folded workspaces; **click `-`** to fold them again.

## Good to know

- The workspace you're on **always stays visible**, even if it's folded.
- `+N` turns **red** (your theme's alert colour) when a folded workspace has
  a window that wants your attention, like a terminal bell.
- Super Spaces **remembers** whether you left it folded or open, even after a
  restart.
