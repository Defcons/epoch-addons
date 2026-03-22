# DeleteItems

A complete item-deletion utility for **WoW 3.3.5a (Ascension/Epoch)**, built from the ground up.

## Features

- **Three independent deletion lists** — switch with left-click, rename with right-click
- **Per-list notes field** — auto-saves on focus lost
- **Drag-and-drop** — drag any item from your bags onto the drop zone to add it
- **Scrollable item list** — alternating rows, rarity colour-coding, vendor price per item
- **Shift+click to delete** — requires confirmation; tooltip shows live bag slot count and total vendor value
- **Junk scanner** — scans bags for gray/white items below a configurable silver threshold; per-item Ignore list
- **Launcher button** — small draggable button always on screen; hover shows live stats, Shift+click deletes without opening window

## Slash Commands

| Command | Action |
|---|---|
| `/di` | Toggle main window |
| `/di add <id\|link>` | Add item to active list |
| `/di rem <id>` | Remove item from active list |
| `/di del` | Delete matching items from bags |
| `/di list` | Print active list to chat |
| `/di clear` | Clear active list |
| `/di set list1\|list2\|list3` | Switch active list |
| `/di junk` | Open junk scanner |

## Compatibility

- **Server:** Ascension / Epoch private server
- **Interface:** 30300 (WoW 3.3.5a)
- **Lua:** 5.1
