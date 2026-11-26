<p align="center"><img src="docs/assets/logo.png" width="100" alt="PawAtlas paw logo"></p>
<h1 align="center">PawAtlas</h1>
<p align="center"><a href="README.md">Русский</a> · <b>English</b></p>
<p align="center">Your mount collection guide and farming planner for WoW Retail (12.1.5).</p>
<p align="center"><a href="https://github.com/Zik/PawAtlas/releases/latest">📦 Download from GitHub</a> · <a href="https://www.curseforge.com/wow/addons/pawatlas">CurseForge</a> · <a href="https://github.com/Zik/PawAtlas/issues">🐛 Report an issue</a></p>

## 🐾 Your mount-hunting companion

- 🔎 **Catalog** — search by mount, boss, or location. Filter by expansion or any of ten acquisition methods. Sort by name or show collected or uncollected mounts first.
- 🗺️ **Mount cards** — switch routes and waypoints, check vendor prices and requirements, and see quest and achievement progress. A clock shows the estimated respawn time for rares with a known interval.
- 🎲 **Attempts & chances** — see drop chances, count attempts, and track items as you collect them. Import your farming history from Rarity.
- 📋 **Warband planner** — create goal lists, check each character’s lockouts, and share plans with friends.
- 🧭 **Expedition mode** — track your goals in a standalone window and set WoW or TomTom waypoints. The same list opens from the broker bar. Drag the corner to resize either window. Both windows share their size, lock, and background opacity settings.
- 🤝 **Collection comparison** — open a player's chat link to see which of their mounts you own and which you're missing.
- 🔔 **Settings** — loot notifications, event reminders, fonts, tooltips, and window scale.

## 📸 Take a look

![Loyal Gorger mount card showing the questline starter item and quest progress](docs/assets/catalog-en.png)

<details>
<summary>📸 Warband planner and settings</summary>

![Plan goals and their availability across the warband](docs/assets/planner-en.png)

![Font, window scale, and transparency settings](docs/assets/settings-en.png)

</details>

*Screenshots use demo data.*

## 📦 Installation

1. Download **PawAtlas-X.Y.Z.zip** from the [latest release](https://github.com/Zik/PawAtlas/releases/latest).
2. Extract the **PawAtlas** folder into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Enable the addon and type **/paw**, or click the minimap paw.

## 🖱️ Quick controls

| Action | Where |
| --- | --- |
| Open the atlas | `/paw`, `/pawatlas`, or PawAtlas in the minimap addon menu |
| Import Rarity attempts | Settings → Integrations |
| Enable the tracker | Settings → Expedition mode |
| Hide or show a character in the Warband planner | Settings → Statistics → eye icon next to the character |
| Choose holiday and world boss reminders | Settings → Events. Hover over an event to see its mounts |
| Rename a plan you created or imported | Select it in the planner, open the plan list, and choose Rename |
| Reorder plans | Drag a plan up or down in the list. “Personal plan” always comes first |
| Share a plan or import one from a code | Share icon in the planner |
| Share your collection | Open chat (including WIM whispers), then Shift + left-click the collection count |
| Use the broker counter | Left-click: target · Right-click: atlas · Shift + left-click: tracker |

> 💡 To view a shared collection, both players must be online with PawAtlas. Each character’s lockouts update when you log in on that character. The cumulative drop chance is an estimate.

<details>
<summary>🤝 Credits & resources</summary>

Thanks to the authors of the projects whose data, libraries, and tools helped make PawAtlas:

- [Rarity: Collector’s Edition](https://github.com/aSnejbjerg/Rarity-Collectors-edition) — source data, drop chances, and tracking conditions.
- [WoWthing](https://github.com/ThingEngineering/wowthing-data) and [Simple Armory](https://github.com/kevinclement/SimpleArmory) — catalog and expansion data.
- [LiteMount](https://github.com/xod-wow/LiteMount) — mount expansion metadata.
- [TrinityCore](https://github.com/TrinityCore/TrinityCore) and [Wowhead](https://www.wowhead.com/npcs) — creature display data for NPC portraits.
- [All The Things](https://github.com/ATTWoWAddon/AllTheThings), [HandyNotes](https://github.com/kemayo) and [HandyNotes: The War Within](https://github.com/zarillion/handynotes-plugins) — sources and coordinates.
- [TomTom](https://www.curseforge.com/wow/addons/tomtom/source) — navigation arrow integration.
- [Ace3](https://github.com/WoWUIDev/Ace3), [LibDataBroker](https://github.com/tekkub/libdatabroker-1-1), [LibStub](https://repos.wowace.com/wow/libstub/trunk/), [CallbackHandler](https://repos.wowace.com/wow/callbackhandler/trunk/), [LibSharedMedia](https://repos.wowace.com/wow/libsharedmedia-3-0/trunk/) — bundled libraries.

</details>

---

<p align="center">🐾 Happy mount hunting!</p>
