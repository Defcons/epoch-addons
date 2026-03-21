
Current Version
---------------

MozzFullWorldMap (Fan's Update) v3.36.30301
WotLK ready.

General Description
-------------------

Show Unexplored Areas on the WorldMap, and now also on AlphaMap (Fan's Update)

MozzFullWorldMap is simple: it adds a new checkbox in the upper left of the world map named 'Show Unexplored Areas'. Checking it will do just that.

Key binding available for users of AlphaMap / Cartographer / MetaMap
(NOTE : The key binding is disabled while the WorldMap is open - unless the World Map has been modified by another AddOn such as AlphaMap)

The default settings mean that unexplored areas appear with a blue/green tinge. I believe this setting is the most useful as it means that you can see all the details of the map, while still being able to identify which areas you have not yet explored.
You can change the behaviour of the AddOn via the Slash commands detailed below, and remove the blue tinge completely, leaving you with a standard view of each map as though you had already explored every area :)

This AddOn is compatible with :
WorldMapFrame,
AlphaMap,
MetaMap (you should disable MetaMapFWM if using this AddOn)
Cartographer (you should disable Foglight if using this AddOn)

This AddOn adds a 'Show Unexplored Areas' checkbox to your world map.

Uses a hardcoded set of overlay data which duplicates data available in the client.  Since it
also queries the client to find out which overlays should be 100%, it will detect discrepancies
in the client data and record any mismatched or not-present data in a saved Errata table.

Original by Mozz, updated by Shub, then Telic and currently kept alive by K. Scott Piel (spiel2001).

Slash Commands
--------------

/mfwm					-- displays help
/mfwm blue				-- shows unexplored areas in blue
/mfwm normal			-- shows unexplored areas in the normal color
/mfwm trans [0.0 - 1.0]	-- change transparency (0.0 = invisible)
/mfwm rainbow			-- choose your own colour/transparency from the Colour Picker Frame


* * * * * * * * * * * * * * * * * * * * * * * *

If you find errors, and have time to help, please do the folllowing : 
_____________________________________________________________________

1.) Exit the game
2.) Delete your SavedVariables MozzFullWorldMap.lua file
3.) Log back in to the game
4.) Open up the World Map Frame and open up every map one after the other
5.) Exit the game
6.) Send your SavedVariables MozzFullWorldMap.lua file to me at telic@hotmail.co.uk

* * * * * * * * * * * * * * * * * * * * * * * *


Change History
--------------

Changes in MFWM v3.36.30304
------------------------------------------------------
- Fixed location of the "Show Unexplored Areas" checkbox
  when the map is changed between full screen and windowed
  
Changes in MFWM v3.36.30303
------------------------------------------------------
- Given the changes in the ADDON_LOADED implementation
  and that it is no longer guaranteed the addon's saved
  variables are loaded before VARIABLES_LOADED fires,
  the onEvent() was changed to use ADDON_LOADED instead

Changes in MFWM v3.36.30300
------------------------------------------------------

- Verified functionality and updated TOC for Patch 3.3

Changes in MFWM v3.36.30200 from v3.35.30200
------------------------------------------------------

- zone fix for WoW patch v3.2


Changes in MFWM v3.35.30200 from v3.35.30100
------------------------------------------------------

- toc update for WoW patch v3.2



Changes in MFWM v3.35.30100 from v3.34.30100
------------------------------------------------------

- fix to Zone map opacity



Changes in MFWM v3.34.30100 from v3.34.30000
------------------------------------------------------

- toc update for WoW patch v3.1



Changes in (Fan's Update) v3.34.30000 from v3.33.30000
------------------------------------------------------

- fix to prevent taint of Set Focus and Clear Focus drop down menu actions



Changes in (Fan's Update) v3.33.30000 from v3.32.30000
------------------------------------------------------

- fix to EPL data



Changes in (Fan's Update) v3.32.30000 from v3.31.20400
------------------------------------------------------

- update for WoW toc v3 and WotLK

- also small corrections to original data



Changes in (Fan's Update) v3.31.20400 from v3.30.20400
------------------------------------------------------

- Chinese localisation update

- changed the behaviour to be 'On' by default when newly installed



Changes in (Fan's Update) v3.30.20400 from v3.30.20300
------------------------------------------------------

- toc update

- data updated for Sunwell Isle



Changes in (Fan's Update) v3.30.20300 from v3.26.20300
------------------------------------------------------

- Now works with the Battlefield Minimap



Changes in (Fan's Update) v3.26.20300 from v3.25.20300
------------------------------------------------------

- correction to Alpha setting if Colour Picker Cancelled



Changes in (Fan's Update) v3.25.20300 from v3.15.20200
------------------------------------------------------

- NEW FUNCTIONALITY Choose your own Color !
Use the following slash command to pick a colour and transparency that suits you :

/mfwm rainbow


- small data correction for Bloodcursed Isle



Changes in (Fan's Update) v3.15.20200 from v3.14.20100
------------------------------------------------------

- simply a toc update



Changes in (Fan's Update) v3.14.20100 from v3.12.20100
------------------------------------------------------

- couple more fixes. Hopefully should fix a BladesEdgeMountain glitch



Changes in (Fan's Update) v3.12.20100 from v3.11.20100
------------------------------------------------------

- couple of area database updates



Changes in (Fan's Update) v3.11.20100 from v3.11.20003
------------------------------------------------------

- just a toc update



Changes in (Fan's Update) v3.11.20003 from v3.10.20000
------------------------------------------------------

- couple of small data corrections



Changes in (Fan's Update) v3.10.20003 from v3.00.20000
------------------------------------------------------

- toc update

- localised for German, French, Spanish

- added a key binding for users of AlphaMap / Cartographer / MetaMap
(NOTE : The key binding is disabled while while the WorldMap is open - unless modified by another AddOn such as AlphaMap)



Changes in (Fan's Update) v3.00.20000 from v2.05.11200
------------------------------------------------------------

- Updated for Burning Crusade Beta
(Burning Crusade Beta is a moving target, so this AddOn may need updating often before final Burning Crusade release. In other words, WoW Beta testers please report problems politely, as any Map changes Blizzard make in one of their frequent Beta Patches may require a corresponding update here ;)

- Updated for compatibility with Future versions of AlphaMap


Changes in (Fan's Update) v2.05.11200 from v2.00.11200
------------------------------------------------------

- very small change to increase compatibility with versions of AlphaMap (Fan's Update) v2.30.11200 and later
- added a localisation file for anyone who wants to localise the ONE single text string ;)


Changes in (Fan's Update) v2.00.11200 from v2.00.11100
------------------------------------------------------

- Simplay a .toc update



Changes in (Fan's Update) v2.00.11100 from v2.00
------------------------------------------------

- Simply a toc update


Changes in (Fan's Update) v2.00 from v1.10 - Telic
--------------------------------------------------

- made compatible with "AlphaMap (Fan's Update)" so unexplored areas can now be seen in the AlphaMap AddOn.


Changes in v1.10 from v1.02 - Shub
----------------------------------

Fixed bug where entire map was blue when first opened.
Added three commands:
/mozzfullworldmap blue -- shows unexplored areas in blue
/mozzfullworldmap normal -- shows unexplored areas in the normal color
/mozzfullworldmap trans [0.0...1.0] -- makes unexplored areas transparent (0.0 is completely
    clear, that is invisible, 1.0 is completely opaque, the default)



Changes in v1.02 from v1.01 - Shub
----------------------------------

Minor bug fix



v1.00 Updated for WoW Patch 1.10 by Shub

Original MozzPack version by Mozz