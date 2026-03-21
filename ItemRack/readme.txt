This is a mod to make swapping equipment easier through popout slot menus, equip slot buttons, gear sets and automated swaps.

__ Ascension (3.3.5) Port Changes __
* Ported to WoW 3.3.5 client (Interface: 30300) for Ascension private server
* Added per-set "Disable in BG/Arena" option — when checked, a set will not be automatically equipped by any event (Buff, Stance, Zone) while inside a battleground or arena
* Options panel height increased to accommodate the new checkbox

__ New in 2.43 __
* Full Titan's Grip support
* Shamans without Dual Wield talent should not see one-hands in offhand menu
* Death Knight dual wield support
__ New in 2.242 __
* Limited Titan's Grip support (see note below)
__ New in 2.241 __
* Unequipping by events should be more reliable
* Button fonts fixed
* Buff events should work again
__ New in 2.24 __
* Immediate fixes for WotLK (scrolling frames, auto queue, events)

__ Quick Start Guide __

Minimap button:
* Right-click the minimap button to open options or create sets
* Left-click the minimap button to choose a set
* Shift-click the minimap button to unequip the last set equipped
* Alt-right-click the minimap button to toggle events on/off
* Alt-left-click the minimap button to show hidden sets

Dockable buttons:
* Alt+click slots on the character sheet to create/remove buttons
* Alt+click yourself in the character sheet to create/remove a set button
* Alt+click the created buttons to toggle their auto-queue status
* Shift+drag buttons to break them apart if they're docked to each other
* Drag the menu's border around to dock it to a different side of buttons
* Right-click the menu's border to rotate the menu
* Size, alpha, spacing, etc are in options

Creating/equipping sets:
* You create sets in the Sets tab after right-clicking the minimap button
* Select slots for the set, choose a name and icon and click Save
* Once a set is saved, there are several ways to equip it:
1. Left-click the minimap button and choose the set
2. Mouseover a set button you've created (Alt+click yourself in character sheet)
3. Use a key binding you define in the set ("Bind Key" button)
4. In macros with /itemrack equip setname
5. In events or scripts that use EquipSet("setname")

Popout menus:
* Click an item or set in a menu to equip it
* Shift+click a set in a menu to unequip it
* Alt+click an item in a menu to hide/unhide it
* Hold Alt as you mouseover a slot to show all hidden items

While at a bank:
* Items/sets in the bank have a blue border.
* Selecting an item or set that's in the bank will pull it from the bank to your bags.
* Selecting an item or set that's not in the bank will attempt to put it all into the bank.

__ Slash Commands __

/itemrack : list the most common slash commands
/itemrack opt : summon the options GUI
/itemrack equip setname : equips a set
/itemrack reset : resets buttons
/itemrack reset everything : wipes all settings, sets and events
/itemrack lock/unlock : locks and unlocks the buttons
/itemrack toggle set name[, second set name] : equips/unequips "set name" (or swaps between two sets if a second set given)

__ Macro Functions __

EquipSet("setname") -- equips "setname"
UnequipSet("setname") -- unequips "setname"
ToggleSet("setname") -- toggles (equips then unequips) "setname"
IsSetEquipped("setname") -- returns true if "setname" is equipped

In the unlikely event that another mod (or default UI in the future) uses these function names, you can use their long version ItemRack.EquipSet(), ItemRack.UnequipSet(), etc.  This mod only commandeers the shortened names if they appear to be unused.

__ Events __

2.2 (re)introduces events.  These are scripts to automatically equip and unequip gear as things happen in game.

To use an event:
1. In the 'Sets' tab, create or make sure you have a set you'd like to equip when the event happens.
2. In the 'Events' tab, click the red ? icon beside the event you want to use.
3. Choose the set for this event.
4. Ensure the event has a check beside it.

As events are enabled, a separate process watches for those events and equips (and unequips if chosen) as they happen.

If you want to create or edit an event, there are four types of events:

Buff: These events equip gear as you gain buffs. ie, Evocation, Drinking and being on a mount.
Stance: These events equip gear when you change stances or forms. ie, Battle Stance, Moonkin Form, Shadowform
Zone: These events equip gear when you're in one of a list of zones. ie, the PVP event includes all arena and BG maps.
Script: For those with lua knowledge, you can create your own event based on a game event.  A couple examples are in the default events.

When dealing with events, it's good to keep some things in mind:
* You'll get the most predictable behavior by having sets that don't overlap.  If you're a warrior with a Tanking, DPS and PVP set, consider not including weapons in those sets.  If you decide to make an event to swap in a 2H when you go into Berserker Stance and a 1h+shield when you go into Defensive Stance, you won't step on the toes of events that swap in PVP gear in a BG/arena or a tuxedo in a city.
* A gold gear icon on the minimap button (and on the sets button if you've created one) means that events are enabled.  If you decide you want to temporarily shut down all events, Alt+click the minimap button or the sets button. (You can disable events in options also)
* For non-English users, you might want to edit the events that have English text within them.  I try to keep it locale-independant when possible (ie, warrior and most druid stances use the numbers instead of names), but you'll never enter "Stormwind City" on a deDE client for the city event.
* Script Events do not have a "set" defined to them like other events do.  They need to EquipSet("setname") explicitly.  Its set button will always be the macro keys icon.
* Advanced users of 1.9x may notice the lack of a delay option in scripted events.  I've decided to pull this down into the scripting system to streamline the event process.  For now, you can use ItemRack.CreateTimer and ItemRack.StartTimer defined in ItemRack.lua.

__ Future plans __

* Move back to an associated set icon for script events
* Possible option of flags for less "persistent" events (only equip if specific state changes)
* Tighter integration/use of EquipItemByName for unique slots
* Moving options to the default UI's new option panels
* Dynamically reordering gear swaps to handle unique-equipped gems in different sets
* Supporting the existing ItemRackFu and TitanFu plugins if possible
* Native ButtonFacade support
* Possibly adding a Combat Log event type
* A set button to sit to the left of weapon slot since the character model isn't an intuitive "button"
* Moving slot key bindings back to default key binding interface

* Set equips while casting will wait until casting ends. (For now this is just sets. Swapping invidual slots from a menu isn't delayed yet.)
* Buff/Mount and Stance events now have an option "Except in PVP instances" to ignore that event in BGs or arenas
* Added new option "Disable Alt+Click" to disable toggling auto queue on buttons
* Druid Tree of Life event fixed

__ More documentation to come __

2.242, 8/17/08, delayed OnLogin to timer, basic Titan's Grip support
2.241, 8/13/08, removed nil of .old in unequip, PLAYER_AURAS_CHANGED to UNIT_AURA, button font to styles
2.24, 8/9/08, added self,offset to OnVerticalScroll, changed GetPlayerBuffName to UnitAura
2.23, 7/17/08, changed "Tree of Life Form" to "Tree of Life", added "Except in PVP instances" option to buff/stance events, added "Disable alt+clicK" option, UNIT_SPELLCAST_x now watched to delay set swaps via existing SetsWaiting, changed if elseif elseif etc in OnEvent to tabled ItemRack.EventHandlers
2.22, 7/10/08, MouseIsOver in menu update checks for frame visibility, second set to /itemrack toggle, alt+left click (show hidden sets) on minimap button with "Allow hidden items" disabled will behave the same as alt+right click (toggle events), "Equip on choosen set" renamed "Equip in options" and works for slots now as well as sets, changed shine flash from default UI's fade to inhouse timer (taint issue)
2.21, 6/29/08, added options Equip on choosing set, Set menu wrap, Show minimap tooltips, alt+left click minimap button=show hidden sets, alt+right click minimap button=toggle events, added swimming, druid flight form, druid swift flight form to events, prevent mount event on taxi (SaberHawke), gear icon on minimap regardless of dockable set button status, check for existing set on tooltip
2.2, 6/19/08, added event system
2.16, 6/8/08, added item lock throttle, equippable items in container cache (updated at end of lock update), replaced buff cache with GetPlayerBuffName, Feign Death checked with GetPlayerBuffName if enUS, gear icon shows if all queues disabled, but half alpha
2.15, 5/26/08, menu strata forced high in DockWindows, item tooltips look in bank if not on person, "^Requires" exception for IsRed changed to ITEM_MIN_SKILL global, set equip/unequip wait system added, hide set checkbutton, ignore/show/hide cloak/helm buttons back for now
2.14, 5/15/08, BankFrame:IsVisible() now a flag again, ITEM_SPELL_CHARGES split to separate search strings (Maldivia), Cooldown90 option, TrinketMenuMode fixed
2.13, 5/13/08, added topLevel="true" to ItemRackMenuFrame (Romracer), Menu on Shift tooltip bug (Romracer)
2.12, 5/12/08, ITEM_SPELL_CHARGES_P1 removed, %d+ replaced with %-?%d+, empty->2h swap fix by Romracer, AnythingLocked() fixed, ValidBag uses GetItemFamily
2.1, 7/14/07, tooltip fix for 2.2 patch, minor edits/fixes over past months
2.0-beta, 1/30/07, complete rewrite.
1.991, 12/23/06, bug fixed: hide/show made combat-aware
1.99, 12/4/06, added: 2.0 changes, key bindings
1.983, 10/19/06, changed: "inventory" attribute to "item" attribute
1.982, 10/14/06, updated: for lua 5.1 (by Esamynn), uses secure action buttons
1.974, 8/22/06, toc changed
1.973, 8/2/06, bugs fixed: changed evocation to ITEMRACK_BUFFS_CHANGED, changed Spirit Tab Begin arg1 to ItemRack.Buffs
1.972, 7/29/06, bug fixes: arg1 preserved through BuffsChanged, GetMouseFocus() could be nil in BAG_UPDATE
1.971, 7/28/06, bug fixes: changed BankFrame:IsVisible to a flag when bank open/closed, SPELLS_CHANGED events now PLAYER_AURAS_CHANGED for 1.12
1.97, 7/27/06, added: bank support, ITEMRACK_BUFFS_CHANGED
1.96, 4/20/06, bug fixed: 4606 error, checked if queue empty, changed: unequip will unequip whole set even if partial unequipped, reset events will nil .old itemid's in sets
1.95, 4/6/06, changes: IsSetEquipped "optimizations" removed, temporary events reverted to earlier versions, tooltip fix scaled back to one SetOwner, queuing a worn set clears queue for those slots, added: queued item insets to character sheet
1.94, 3/29/06, bug fix: menu not appearing on bar
1.93, 3/29/06, bug fixes: nil errors from tooltip changes, added: relic slot support
1.92, 3/20/06, bug fixes: attempt to fix arithmetic on string value 4706
1.91, 3/19/06, bug fixes: invalid key for 'next', couple nil errors, changed: mount event to old style, added: option ('Show set icon labels') to show/hide set labels, option ('Auto toggle sets') to auto toggle sets, shift on chosing set toggles set
1.9, 1/24/06, release of 1.891-1.897
1.897 (1.9 beta7) 2/24/06, bug fixed: queue jams (hopefully) gone for good, added: option to show/hide cloak/helm, AQ mount checks, changed: consolidated timers
1.896 (1.9 beta6) 2/21/06, bug fixed: new user and post-combat/death error
1.895 (1.9 beta5) 2/20/06, bug fixed: hide tradables fixed
1.894 (1.9 beta4) 2/19/06, changed: options to scrollable list, form events use IR_FORM global, combat/death queue redone to a single "set" instead of a full queue, alt+click on locked bar won't add/remove slots, one-hand won't show up in offhand for non-DW'ers, items clicked on cooldown won't appear to be used, added: square minimap, large cooldown, reset events
1.893 (1.9 beta3) 2/5/06, bug fixed: TrinketMenu Mode menu fixed if only trinkets on bar, added: Large font option for event script, changed: Event scripts overhauled for new EquipSet
1.892 (1.9 beta2) 1/29/06, bug fixed: non-standard bags recognized, old freespace code removed, 2h swaps on bar immediate move
1.891 (1.9 beta1) 1/28/06, changed: new EquipSet (enchants recognized), ^Requires dropped from "red" check, player-made events won't unregister on zoning, minimap button scaling fixed, /itemrack reset fixed
1.84, 1/20/06, bug fixed: menu update only checks MouseIsOver for plugin if it's installed
1.83, 1/19/06, added: titan support/docking, bug fixed: scroll wheel on lists, changed: checks for TitanRider enabled, events unregister/register on zoning
1.82, 1/16/06, changed: ALT+click/hide behavior made an option for all but sets (default off), bugs fixed: notify with no bar on screen should reliably fire, 2h->1h+offhand swaps will moved orphaned offhand to leftmost bag again
1.81, 1/14/06, bug fixed: Mount event
1.8, 1/12/06, added: IsSetEquipped(setname) returns true if all slots in a set are currently worn, error message when attempting to equip a set that doesn't exist, TitanPanel_ItemRackUpdate, note that events are suspended when set/event window up, bugs fixed: Disenchants/enchants/etc during gear swaps will abort the swap, Bloodvine will show up in menu on enUS clients, ammo count shows again, changed: initialization done in phases, removed cooldown boundry checks, tooltip scans changed to GetItemInfo, new events: Eating-Drinking, Low Mana, Skinning, Mage:Evocation, Priest:Spirit Tap Begin, Priest:Spirit Tap End
1.74, 1/8/06: bugs fixed: bags should work properly on deDE clients, set icon will remember last set when leaving an event, "Mount" event no longer disabled if TitanRider installed
1.73, 1/7/06: bugs fixed: Scrollbars enabled properly (the thumb will appear in 1.9.1 patch), Bindings saved using new SaveBindings, Soul Bags treated like quivers, ammo slot name lifted from tooltip for SaveSet, notify will happen if bar is off screen, changed: In TrinketMenu Mode, hold Shift to keep menu open on the bar, if any event uses ITEMRACK_NOTIFY trigger notify is automatically enabled, removed: check for TitanRider
1.72, 1/3/06: added: reset button added to options, bugs fixed: items used from action bars noticed by mod, users without SCT won't have notify messages "stick", scaling fixes for 1.9, removed scalebugfix (huzzah!)
1.71, 12/21/05: changed: inventory items used elsewhere in the UI reflects in the mod, arg1 and arg2 save on delayed events, added: ITEMRACK_ITEMUSED event (arg1=item name, arg2=item slot), Insignia Ready/Insignia Used events, examples for making scripts that swap on use, bugs fixed: added pink tiger to problem mounts
1.7, 12/8/05, added: events (see events manual.txt), sets queue, sets menu on minimap button, 30 second notify, French localization by Tinou, more slash commands (/itemrack help)
1.61, 11/02/05, bugs fixed: tooltip back to standard GameTooltip (should fix issues with Tipster, TipBuddy and other tooltip mods), set builder now updates properly when nothing on the bar
1.6, 10/31/05, bug fixed: error when items on notify queue are banked, "Container" in DE localized, added: menu pops up on character sheet, audible alert on notify, changed: ItemRack_CurrentSet made global
1.5, 10/5/05, bug fixed: pairs of items of same name with one worn swap, "Container" in German, added: Flip bar growth option, alt+click items in menu to hide them, changed: selecting set equips it
1.42, 10/2/05, bug fixed: two items of same name will swap in sets, key bindings in normal key binding window force to sets
1.41, 9/30/05, bug fixed: nil error on mouseover set icon
1.4, 9/30/05, added: sets, minimap button, /itemrack opt, help text, changed: using sharpening stones/poisons/enchants/etc will work on the bar, only wearable items will show in menu, options moved to a tab on sets window, bugs fixed: ghost countdowns for real
1.32, 9/18/05, bugs fixed: overhead errors fade normally, tabard on bar with cooldown/notify won't error, switching from 2h to 1h+shield queue works properly, swapping to empty won't attempt to put items in quivers, "ghost" cooldowns no longer show on empty slots, removed check for 1.7 in supposed client bug fix for 1.7 that never happened, changed: queues process as sets in stages
1.31, 9/8/05, bug fixed: rotate menu works when bar is horizontal
1.3, 9/7/05, added: German translation by Leelaa, Alt+right click an item will add a space after it, changed: right-click will activate an item same as left click, holding Alt while mouseover items will show full tooltip if Tiny Tooltips enabled, option TrinketMenu Clicks renamed TrinketMenu Mode, while TrinketMenu Mode enabled trinkets show as one menu, bugs fixed: overlapping tooltips, queue won't process upon FD, ammo count shows when adding to rack
1.21, 9/3/05, added: ammo shows quantity, changed: custom tooltip used instead of standard, bug fixed: thrown weapons recognized, multiple ammo stacks show as one in menu, error clicking empty slot with notify on, weapons will queue while dead
1.2, 9/3/05, added: options to hide tooltips or make them smaller, notify when items ready, /itemrack scale as alternative to set scale, changed: spacers to trinkets when TrinketMenu Clicks checked, OnUpdates given ItemRack_InvFrame parent, bugs fixed: mod hides when UI hidden, hunter FD won't block item swaps
1.1, 9/2/05, added: option to swap to empty slots, option to reverse menu growth, left/right-click trinkets options added, changed: "Soulbound Only" renamed to "Hide Tradables", some slots ignore soulbound flag now: trinket, ammo, shirt, tabard. quest and conjured items now show with 'Soulbound Only' on. bug fixed: items queued while dead will swap on res before release
1.0, 8/31/05, initial release
