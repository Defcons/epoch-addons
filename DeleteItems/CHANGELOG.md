# DeleteItems — Changelog

## v1.1 — Escape support
- **Escape closes the window:** both the main DeleteItems frame and the Junk Scanner frame now register with `UISpecialFrames`. Escape closes any open StaticPopup confirmation first, then the main window

## v1.0 — Initial Release

### Core data layer
- Three independent deletion lists (`list1`/`list2`/`list3`) stored in `DIData` (`SavedVariables` — account-wide, shared across all characters)
- Data migration path: old `DITotalSavedItems` / `DICurrentList` format automatically converted on first load
- String keys for all item IDs (prevents WoW SavedVariables numeric-key serialisation quirks)
- `activeList` persisted across sessions

### Main window
- Scrollable item list with alternating row backgrounds, rarity colour-coding, and per-item vendor price shown inline
- Drag-and-drop zone: drag any item from bags directly onto the zone to add it to the active list
- Per-row `[Remove]` button; row tooltip shows the full item tooltip
- Three list-tab buttons at the top — **left-click** switches list, **right-click** opens a rename dialog (`StaticPopup` with `hasEditBox`)
- Per-list **notes** field (auto-saves on focus lost, Escape to revert, placeholder text)
- `[Delete Items From Bags]` button — requires **Shift+click** to confirm; tooltip shows live count of matching bag slots and total vendor value that would be destroyed
- `[Clear List]` button with confirmation popup
- `[Scan Bags for Junk Suggestions]` button to open the junk scanner

### Launcher button
- Small draggable frame button always visible on screen (replaces minimap button)
- **Hover tooltip:** shows active list name, number of matching bag slots that would be freed, and total vendor value to be destroyed
- **Click:** toggle the main window open/close
- **Shift+click:** delete immediately without opening the window
- Drag to reposition anywhere on screen

### Junk scanner
- Separate draggable frame (430 px wide) anchored to the right of the main window
- **Threshold control:** `Max sell price (gray/white):` edit box (silver) — `0` shows all grays regardless of price; `> 0` shows gray and white items whose sell price per item is ≤ the threshold
- `[Scan Bags Now]` button — reads current threshold, scans all bags, results sorted cheapest first
- Per-row layout: item icon + name (quality colour) on line 1; formatted vendor price/ea + bag count + max-stack hint on line 2; stacked `[Add to List]` and `[Ignore]` buttons on the right
- `[Add All Suggestions to Active List]` — bulk-adds all current results
- Per-item **Ignore** button: adds item to `DIData.junkIgnore`; ignored items never appear in future scans
- `[Clear Ignored Items (N)]` button — shows live count, disabled when list is empty
- Items already in any deletion list are automatically excluded from scan results
- Object pooling (`junkRowPool`) for efficient re-renders

### Slash commands
- `/di` — open/close window
- `/di add <id|link>`, `/di rem <id>`, `/di del`, `/di list`, `/di clear`
- `/di set list1|list2|list3`, `/di junk` — open junk scanner
