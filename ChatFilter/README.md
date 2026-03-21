# ChatFilter

**Lightweight Chat Filter Addon for WotLK (3.3.5)**

ChatFilter automatically hides chat messages that contain specific keywords.  


## 📌 Use Case

I currently use it in tandem with **GroupBulletinBoard** to clean my chat from LFG spam.  
But you can configure it for any kind of unwanted messages (gold sellers, ads, etc.).


## ⚙️ How to Use

1. Install the addon by placing the `ChatFilter-main` folder into:  
Interface/AddOns/

2. Rename it `ChatFilter`

3. Open `ChatFilter.lua`.
   
4. Add or remove keywords inside the `blockedWords` list if needed. Example : 

```lua
local blockedWords = {
 "gold",
 "cheap",
 "powerlevel",
 "www"
}
