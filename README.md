# Super Spaces

Omarchy bar workspaces where workspaces past 9 fold away, like the tray drawer.

![Folded (+) and open (-) states](preview.png)

- Workspaces 1–9 show as usual.
- Workspaces 10 and up hide behind a **`+`**; click it to show them (with their
  full number, e.g. `15`), and **`-`** to hide them again.
- The workspace you are on always stays visible, even when folded.

Replaces the built-in `omarchy.workspaces` widget and keeps everything it does:
click to switch, click the current one to cycle its layout, scroll to move.

## Install

```bash
omarchy plugin add https://github.com/achardz/omarchy-super-spaces.git --enable
omarchy restart shell
```

## Remove

```bash
omarchy plugin remove anzlaptop.super-spaces
```

MIT — based on Omarchy's `omarchy.workspaces` widget.
