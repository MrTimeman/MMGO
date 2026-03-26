# MMGO — Ministry of MaGic Online

*Game Design Document*

Version 0.8 — Complete Draft

March 2026

## Table of Contents

- [1. Overview](#1-overview)
  - [1.1 Player Classes](#11-player-classes)
- [2. Magic System](#2-magic-system)
  - [2.1 Schools of Magic](#21-schools-of-magic)
  - [2.2 Spell Creation](#22-spell-creation)
  - [2.3 AI Spell Resolution](#23-ai-spell-resolution)
- [3. Combat](#3-combat)
  - [3.1 Combat Modes](#31-combat-modes)
  - [3.2 Core Rules](#32-core-rules)
  - [3.3 Class-Specific Combat UI](#33-class-specific-combat-ui)
  - [3.4 Resolution Pipeline](#34-resolution-pipeline)
  - [3.5 Win Conditions](#35-win-conditions)
  - [3.6 Resolution Order Within a Turn](#36-resolution-order-within-a-turn)
- [4. Time System](#4-time-system)
- [5. Location & Map](#5-location--map)
  - [5.1 Geography](#51-geography)
  - [5.2 Travel](#52-travel)
  - [5.3 Bases](#53-bases)
  - [5.4 The Tower & Magic Zones](#54-the-tower--magic-zones)
  - [5.5 The Secret Cult (Fast Travel)](#55-the-secret-cult-fast-travel)
  - [5.6 Interactions & Events](#56-interactions--events)
- [6. Fediverse & Realms](#6-fediverse--realms)
  - [6.1 Architecture](#61-architecture)
  - [6.2 Inter-Realm Travel ("Leave the Realm")](#62-inter-realm-travel-leave-the-realm)
  - [6.3 Currency Exchange](#63-currency-exchange)
  - [6.4 Realm Discovery](#64-realm-discovery)
- [7. Spell Library & Grimoires](#7-spell-library--grimoires)
  - [7.1 Personal Spell Library](#71-personal-spell-library)
  - [7.2 Grimoires](#72-grimoires)
- [8. Alchemy & Workshops](#8-alchemy--workshops)
- [9. Academy](#9-academy)
  - [9.1 Basic Education (Mandatory)](#91-basic-education-mandatory)
  - [9.2 Admission to the Academy](#92-admission-to-the-academy)
  - [9.3 Specialization Tracks](#93-specialization-tracks)
  - [9.4 Duration & Post-Graduation](#94-duration--post-graduation)
  - [9.5 Academia (Research Path)](#95-academia-research-path)
  - [9.6 Clubs](#96-clubs)
- [10. The Dungeon](#10-the-dungeon)
  - [10.1 Structure](#101-structure)
  - [10.2 The Dungeon AI](#102-the-dungeon-ai)
  - [10.3 Living in the Dungeon](#103-living-in-the-dungeon)
  - [10.4 Navigation & Return](#104-navigation--return)
  - [10.5 Death & Roguelike’s Sacrifice](#105-death--roguelikes-sacrifice)
  - [10.6 Rewards](#106-rewards)
- [11. XP & Leveling](#11-xp--leveling)
  - [11.1 XP Range & Curve](#111-xp-range--curve)
  - [11.2 XP Sources](#112-xp-sources)
  - [11.3 Level-Up Rewards](#113-level-up-rewards)
- [12. Economy & Trading](#12-economy--trading)
  - [12.1 Fixed Money Supply](#121-fixed-money-supply)
  - [12.2 Taxation](#122-taxation)
  - [12.3 Black Market (Illegal P2P)](#123-black-market-illegal-p2p)
  - [12.4 Money Sinks & Faucets](#124-money-sinks--faucets)
  - [12.5 Charity Fund](#125-charity-fund)
- [13. Parties & Roles](#13-parties--roles)
  - [13.1 Party Formation](#131-party-formation)
  - [13.2 Emergent Roles](#132-emergent-roles)
  - [13.3 Loot & XP Sharing](#133-loot--xp-sharing)
- [14. Scavenging & Survival](#14-scavenging--survival)
  - [14.1 Food](#141-food)
  - [14.2 Scavenging](#142-scavenging)
  - [14.3 Weight & Carry Capacity](#143-weight--carry-capacity)
- [15. Monetization](#15-monetization)
  - [15.1 Donation Model](#151-donation-model)
  - [15.2 Principles](#152-principles)
- [16. Game Meta & Design Philosophy](#16-game-meta--design-philosophy)
  - [16.1 Core Experience](#161-core-experience)
  - [16.2 Design Pillars](#162-design-pillars)
  - [16.3 Target Audience](#163-target-audience)
  - [16.4 Technical Platform](#164-technical-platform)

# 1. Overview

MMGO is a text-based MMO-style game played via Telegram (Mini App + bot). It combines MMO social interaction with JRPG-like map and exploration mechanics. The game world runs on a compressed time system and features AI-driven spell creation, alchemy, dungeons, trading, and a player-driven economy.

The game is built around interconnected systems. Circles represent mechanics (active systems players interact with), squares represent data stores (persistent state). The central hub is the Inventory, which connects combat loot, crafting materials, tools, and currency.

**System Dependencies**

|                       |                 |                                |
|-----------------------|-----------------|--------------------------------|
| **From**              | **To**          | **Relationship**               |
| Spell Creation        | Spell DB        | Created spells are stored      |
| Academy               | Spell Creation  | Academy teaches spell creation |
| Academy               | Potion Creation | Academy teaches alchemy        |
| Spell DB              | Grimoires       | Grimoires reference spell DB   |
| Grimoires             | Fights          | Grimoires used in combat       |
| Spell DB / Potion Cr. | XP              | Creating gives XP              |
| Inventory             | \$              | Items can be sold              |
| Scavenging            | Inventory       | Loot goes to inventory         |
| Tools                 | Crafting        | Tools required for crafting    |

## 1.1 Player Classes

- **Casters / Wizards** — primary magic users, focused on spell creation and combat casting. Choose 2 schools at the Academy.

- **Tool Users (formerly Knights)** — melee/ranged fighters using swords, shields, and thrown potions. Dominate overworld combat where magic doesn’t work. Trained via the Mastery track at the Academy.

- **Crafters: Potions** — alchemy specialists, create consumables. Trained via the Alchemy track.

- **Crafters: Tools** — equipment and item crafters. Also via the Mastery track.

# 2. Magic System

The magic system is the core feature of MMGO. Players create spells by combining a school, a base spell, and a Latin incantation of up to 6 words. An AI interprets the combination and produces situational effects that alter the state of the battle, rather than simple numeric damage.

## 2.1 Schools of Magic

Eight schools arranged in an elemental compass. Four base elements occupy the cardinal directions; four hybrid (metaphysical) schools emerge at the diagonals where adjacent base elements meet. Opposite base elements are incompatible (Fire↔Water, Earth↔Air). Opposite hybrid schools are also opposed (Chaos↔Order, Life↔Death).

**Elemental Compass**

|           |           |           |
|-----------|-----------|-----------|
| **Chaos** | **Air**   | **Life**  |
| **Fire**  | —         | **Water** |
| **Death** | **Earth** | **Order** |

**Hybrid School Composition**

|            |                |              |                                        |
|------------|----------------|--------------|----------------------------------------|
| **Hybrid** | **Components** | **Opposite** | **Theme**                              |
| Chaos      | Fire + Air     | Order        | Entropy, unpredictability, wild energy |
| Order      | Earth + Water  | Chaos        | Structure, crystallization, law        |
| Life       | Air + Water    | Death        | Healing, growth, summoning creatures   |
| Death      | Fire + Earth   | Life         | Necromancy, decay, draining            |

## 2.2 Spell Creation

A spell is defined by three components: a school, a base spell from the caster’s personal library, and a Latin incantation of 1–6 words. Each word corresponds to a parameter slot. Using fewer words produces a cheaper, faster, but less predictable spell — the AI fills in unspecified parameters at its discretion.

### 2.2.1 Base Spell

Every spell is built on top of an existing spell from the caster’s personal library. New players start with a small set of starter spells. The library grows through the Academy, loot, trading, and — crucially — every successfully created spell enters the library and can serve as a base for future spells. This creates a recursive progression: spells beget spells.

When a base spell is specified, the AI operates in "revamp" mode: it modifies the base spell according to the new incantation parameters rather than generating from scratch. This preserves lineage and encourages iterative refinement.

### 2.2.2 Incantation Parameters

The player writes up to 6 Latin words. Each word maps to a parameter slot. The vocabulary is intentionally open-ended — players can use any Latin word they believe fits the slot. The AI interprets the intent. There is no fixed dictionary; restricting words would defeat the purpose of having an AI in the loop.

Levenshtein distance validation catches obvious typos (near-misses resolve to the closest known word), but unknown words are passed to the AI as-is for creative interpretation. The table below shows example words per slot, not an exhaustive list:

|        |          |                                   |                                                                                     |
|--------|----------|-----------------------------------|-------------------------------------------------------------------------------------|
| **\#** | **Slot** | **Determines**                    | **Example Words**                                                                   |
| 1      | Actio    | What the spell does (core action) | Ictus (strike), Captio (capture), Scutum (shield), Sanatio (heal), Vocatio (summon) |
| 2      | Forma    | Shape and geometry of the effect  | Radius (beam), Sphaera (sphere), Murus (wall), Conus (cone), Nexus (link)           |
| 3      | Vis      | Intensity / power scale           | Levis (light), Mediocris (medium), Magnus (great), Enormis (extreme)                |
| 4      | Tempus   | Duration                          | Momentum (instant), Sustineo (sustained/channeled), Tardus (delayed)                |
| 5      | Mutatio  | Secondary / combo effect          | Motus (displacement), Glacies (freeze), Dissipatio (dispersion)                     |
| 6      | Pretium  | Additional cost beyond fatigue    | Sanguis (HP cost), Mora (skip next turn), Focus (concentration lock)                |

A minimal spell uses only Actio (1 word). The AI determines all other parameters, making the result cheap but unpredictable. A full 6-word incantation gives the caster maximum control at maximum cost.

## 2.3 AI Spell Resolution

When a spell is cast, the server sends the incantation plus current battle state to the AI. The AI returns a structured JSON response with two layers: a mechanical layer (for the engine) and a narrative layer (for the players).

### 2.3.1 AI Input

The AI receives: the school, base spell reference, all incantation parameters (null for omitted slots), caster level, current environment states, and active states on all participants. This context prevents the AI from generating conflicting or nonsensical effects.

### 2.3.2 AI Output Schema

The AI must return a JSON object with the following structure:

- **spell** — name (canonical Latin), name_ru (display name in Russian), formula (full incantation string), school, source_spell_id

- **target_effects\[\]** — array of effects on targets. Each entry: target ID, array of states (see State Primitives below). Each state has: id, intensity, duration, optional dot_per_turn, optional blocks\[\], optional break_conditions\[\]

- **caster_effects\[\]** — array of states applied to the caster after casting

- **environment_effects\[\]** — array of terrain changes. Each entry: state id, zone, duration, optional dot_per_turn, interaction_rules\[\] defining how other schools interact with this terrain effect

- **cooldown 2014 integer, turns until spell can be used again** — undefined

- **fatigue_cost** — integer, fatigue accumulated by the caster

- **narrative_ru** — human-readable combat narration in Russian, shown to players

*Key design principle: there is no base_damage field. All damage is delivered through states (e.g., "burning" with dot_per_turn, or "impact" with duration: 0 for one-time hits). This ensures every spell creates a situation, not just a number.*

### 2.3.3 State Primitives

The AI must compose effects from a fixed set of state primitives. It can combine multiple primitives per target and adjust intensity/duration, but cannot invent new state IDs. This ensures the engine can always resolve effects deterministically.

|              |              |                                                                                                         |
|--------------|--------------|---------------------------------------------------------------------------------------------------------|
| **State ID** | **Category** | **Effect**                                                                                              |
| impact       | instant      | One-time effect (duration: 0). Used for direct hits. Intensity determines force.                        |
| burning      | DoT          | Damage per turn. Break: water spell on target, roll_on_ground.                                          |
| frozen       | control      | Cannot move. Break: fire spell on target, physical_hit.                                                 |
| trapped      | control      | Cannot take any action. Break: ally hits caster, counter-element from inside.                           |
| blinded      | debuff       | Spells may miss (accuracy penalty). Break: water spell on self, duration expires.                       |
| silenced     | debuff       | Cannot cast spells. Break: ally dispel, duration expires.                                               |
| staggered    | debuff       | Blocks one action per turn. Break: duration expires.                                                    |
| channeling   | self-lock    | Caster maintains an effect; cannot take other actions. Break: caster chooses to stop, caster takes hit. |
| shielded     | defense      | Blocks or weakens next incoming attack. Consumed on trigger.                                            |
| regenerating | HoT          | Healing per turn. Stacks with intensity.                                                                |
| empowered    | buff         | Next spell cast is amplified (intensity = multiplier).                                                  |
| exposed      | debuff       | Vulnerable to next attack (increased damage/effect intensity).                                          |

*This list will expand as the system is playtested. New primitives must be added to the engine before the AI can use them.*

### 2.3.4 Environment Effects

Every sufficiently powerful spell leaves a mark on the environment. The AI specifies environment_effects with interaction_rules: what happens when another school’s spell hits this zone. The engine does not hardcode elemental interactions — instead, the AI declares them per-spell, using a fixed set of result types:

- **spread** — the environment effect expands (e.g., air spell fans fire)

- **replace** — the environment effect is replaced by a new one (e.g., water on fire → steam)

- **amplify** — the environment effect intensifies (e.g., earth on earth → thicker wall)

- **negate** — the environment effect is removed (e.g., water extinguishes fire)

- **transform** — the environment effect changes type (e.g., fire on ice → flood)

The environment state persists across turns. Each turn, the engine applies ongoing environment effects (e.g., burning ground deals DoT to everyone in the zone) before resolving new spells.

# 3. Combat

Combat uses a single engine for all modes. The difference between modes lies in stakes and win conditions, not in mechanics.

## 3.1 Combat Modes

### 3.1.1 Duels (PvP)

- Team vs. team, any size (1v1 up to theoretically 100v100)

- Entry requires a money wager (agreed upon before the fight)

- Loser forfeits the wager; no other penalties

- Only personal equipment allowed: casters use their grimoire spells, tool users use their inventory items

- No external consumables, no loot drops during the fight

### 3.1.2 Dungeons (PvE + optional PvP)

- Party vs. dungeon mobs (AI-controlled foes)

- PvP encounters possible inside dungeons: other player parties can attack, kill, and loot everything

- On death: protected by Roguelike’s Sacrifice (no permadeath), but all carried loot is lost to the attackers

- Full access to inventory, potions, and scavenged items during the run

## 3.2 Core Rules

- **Shared HP** — each side (party) shares a single HP pool. Individual members have separate cooldowns, fatigue, and status effects. Damage to the party depletes the shared pool regardless of which member was targeted.

- **Simultaneous turns** — all participants on all sides declare their actions simultaneously within a turn timer. Once all actions are locked in (or the timer expires), the engine resolves everything at once.

- **Turn timer** — flexible, scales with the number of participants. Larger battles get more time per turn.

- **Cooperation** — coordinating actions between party members yields better outcomes than acting independently. Example: one player traps a foe in a water sphere while another hits the caster from the opposite side.

- **Summons** — summons do NOT split the party’s HP pool. They act as independent entities with their own HP. Extremely hard to obtain.

## 3.3 Class-Specific Combat UI

### 3.3.1 Casters

Casters see a text input field where they type their incantation (Latin words). The UI shows their grimoire (available base spells) for reference. The flow: select a base spell from grimoire → type incantation (1–6 words) → submit. The AI resolves the spell and the engine processes the result.

### 3.3.2 Tool Users

Tool users see a menu-based interface showing their equipped items and available actions. The flow: select an item from inventory → select an action (use, throw, charge, equip) → select a target → submit. All tool user actions are fully deterministic — no AI needed for resolution. Values are looked up from item stat tables.

Tool user item categories:

- **Melee weapons** — swords, axes, maces. Actions: strike (single target), sweep (area). Deal impact state with fixed damage range + possible secondary state (e.g., staggered).

- **Shields** — equip to gain shielded state. Can actively block (consume the shield’s durability to negate incoming damage). Heavy shields slow movement.

- **Thrown potions** — alchemist-crafted consumables. Throw at target or zone. Effects: burning (fire potion), frozen (ice potion), blinded (smoke potion), regenerating (heal potion on ally). Single-use.

- **Mechanical tools** — traps, grapples, nets. Actions: deploy (place trap), activate (trigger mechanism). Create trapped or staggered states on enemies who trigger them.

- **Repair kits** — restore durability to shields and tools mid-combat. Support action, takes a full turn.

Tool user items produce the same state primitives as spells (impact, burning, frozen, shielded, etc.), so the engine resolves them identically. The difference is that tool effects have fixed values with narrow ranges, while spell effects have wider ranges influenced by the AI and orchestrator.

## 3.4 Resolution Pipeline

Each turn is resolved through a three-stage pipeline:

- Collects all declared actions from all participants

- Resolves tool user actions immediately (table lookups, no AI)

- Sends caster incantations to the Spell AI, receives structured JSON responses

- Computes base state changes: which states are applied, damage ranges, fatigue costs

- Checks for conflicts (two spells targeting the same entity, contradictory states)

- Outputs an intermediate result: a set of allowed outcomes with value ranges

- Receives the intermediate result from the engine (allowed outcomes + ranges)

- Selects specific values within those ranges to maximize dramatic impact

- Can decide hit/miss within the probability the engine computed

- Can choose which break_condition triggers first when multiple are valid

- Can pick the exact damage number from the allowed range (e.g., 17 out of 15–25 to keep the enemy alive for a more dramatic next turn)

- Cannot exceed engine ranges, add new states, cancel player actions, or alter fatigue costs

- Receives the final resolved state from the orchestrator

- Generates a vivid, unique Russian-language description of what happened this turn

- Describes every action, every interaction, every environmental change

- This is the only output players see — they never see raw numbers or state IDs

## 3.5 Win Conditions

- A side loses when its shared HP reaches zero

- A side can flee (forfeit) — conditions and penalties depend on combat mode

- Special abilities or items may end combat early (e.g., capture, banishment)

## 3.6 Resolution Order Within a Turn

Within Stage 1 (Engine), effects are applied in this order:

- 1\. All actions are declared and locked

- 2\. Fatigue is accumulated and cooldowns are checked

- 3\. Spell AI resolves all incantations (parallel)

- 4\. Tool user actions are resolved (table lookups)

- 5\. Direct target effects are applied (states on targets and casters)

- 6\. Environment effects are updated (new terrain states added, existing ones tick)

- 7\. Ongoing environment effects apply to all entities in affected zones

- 8\. Break conditions are checked; expired states are removed

- 9\. Shared HP is updated for both sides

- 10\. Engine outputs intermediate result with ranges to Orchestrator

# 4. Time System

The game uses compressed time. All travel, crafting, and world events operate on game time, creating meaningful seasons and yearly cycles within a playable window.

|                |                     |
|----------------|---------------------|
| **Real Time**  | **Game Time**       |
| 24 hours       | 1 year (364 days)   |
| ~4 minutes     | 1 day               |
| ~56 minutes    | 1 month (28 days)   |
| ~1 hour 51 min | 1 season (3 months) |

The calendar uses 13 months of 28 days each (364 days/year). Travel, food consumption, crafting timers, and seasonal events all run on this clock. A journey of 10 game-days takes roughly 40 real minutes.

# 5. Location & Map

The map is the primary interface. To do anything, the player must physically travel there. The visual layer is a Starsector-style map showing the world, player position, and points of interest. All interactions (building, crafting, trading, conversation) happen as text-based events triggered at specific locations. No 3D, no sprites — just the map and text.

## 5.1 Geography

The realm (principality) is bounded by the map edges. Key geographic features:

- **Cities** — safe zones. No PvP. Property can be purchased (not built). Contain shops, trading hubs, the Academy, NPC services. Far from the Tower.

- **The Tower** — located far from cities, in the mountains near the coast. The only place where magic works. Contains the dungeon entrance. All magical gameplay (spell creation in combat, dungeon runs) happens here or inside it.

- **Wilderness** — everything between cities and the Tower. Dangerous: PvP is enabled, bandits and creatures roam. Different regions have different resources, loot tables, and dangers.

- **Micro-villages** — small settlements on the first level of the dungeon or near the Tower. Risky to live in, but minimal travel to the action.

## 5.2 Travel

Travel consumes game time and food. The player moves across the map in real time (their position updates as game-days pass). Longer journeys require more food supplies from inventory. If food runs out, the player suffers penalties (slower movement, HP drain).

The overworld is fully PvP-enabled outside of cities. A player carrying loot from a dungeon run back to their city base can be ambushed on the road. This makes escort parties, trade caravans, and route planning meaningful. Notably, magic does not work in the overworld — combat on the road uses only tools, weapons, and potions. Casters are vulnerable outside the Tower.

## 5.3 Bases

Every player needs a base for storage, crafting, spell composition, and alchemy. There are two ways to get one:

- **Buy in a city** — cheap, safe, close to trade and Academy. Far from the Tower. Best for crafters and traders.

- **Build anywhere** — expensive, requires materials and time. Can be built near the Tower for quick dungeon access, but the location may be dangerous (PvP, monsters). Best for dedicated dungeon runners.

Your base is where your loot is stored. Raiding player bases is NOT possible (the base is instanced/protected), but getting your loot TO your base safely is the challenge.

## 5.4 The Tower & Magic Zones

Magic only works inside the Tower and the dungeon within it. In the overworld, spells cannot be cast. This is the fundamental class balance mechanic:

- **Inside the Tower** — casters dominate. Their spells are at full power. Tool users are weaker but still functional.

- **In the overworld** — tool users dominate. Casters have no magic and must rely on mundane equipment. They are essentially civilians unless they carry tools.

This creates a strong incentive for mixed parties: you need tool users to get safely to the Tower, and casters to succeed inside it.

## 5.5 The Secret Cult (Fast Travel)

Hidden near the main city, a secret cult maintains underground passages that lead directly to the Tower. Discovering the cult requires completing a hidden quest chain. Once found, the cult provides safe, fast passage between the city and the Tower, bypassing the dangerous overworld. This is the primary quality-of-life feature for city-based players who run dungeons regularly.

*The cult’s existence, lore, and quest chain are TBD. Consider: should the cult charge per trip? Should membership be revocable? Can the cult be discovered by following another player?*

## 5.6 Interactions & Events

All non-combat interactions are text-based events, similar to Starsector or classic text adventures. When the player arrives at a location, they see a text description and a set of available actions. Examples:

- Arriving at a city: options to visit shops, Academy, tavern (social hub), housing market

- Encountering another player on the road: options to greet, trade, attack, or avoid

- Reaching your base: options to store/retrieve items, craft, compose spells, rest

- Entering the Tower: options to form/join a party, enter the dungeon, visit the Tower library

# 6. Fediverse & Realms

Each game instance is a "realm" — a self-contained world with its own map, economy, rules, and magic system. The default realm is the canonical one, but anyone can host their own instance with custom rules, connected to the broader network.

## 6.1 Architecture

- Each realm is a separate server instance tied to a Telegram channel

- Realm operators can customize: map layout, economy parameters, magic school definitions, Tower location, NPC behavior, PvP rules

- The core engine is shared; customization happens through configuration, not code forks

## 6.2 Inter-Realm Travel ("Leave the Realm")

A player can choose to leave their current realm. This triggers a migration process:

- The account in the origin realm is frozen for a set duration

- During the freeze, the player accumulates passive XP in the origin realm

- A new character is created in the destination realm

- Currency (converted at a market-determined exchange rate between realms)

- Level / XP (partially — the player arrives at a reduced level, not starting from scratch)

- The character identity (same person, same name, same history)

- Spell library — each realm has its own magic system, so spells are incompatible. The player must learn magic from scratch in the new realm.

- Inventory and equipment — left behind in the origin realm (retrievable if the player returns)

- Base and property — remains in the origin realm

- Reputation and social standing — must be rebuilt

*The spell library not transferring is by design, not limitation. Each realm operator defines their own school system, incantation words, and state primitives. A fire spell from one realm might not even have a concept of “fire” in another.*

## 6.3 Currency Exchange

Realms have independent currencies. Exchange rates are determined by market activity (players trading cross-realm). A player migrating with 1000 gold from Realm A might receive 750 silver in Realm B depending on the current rate. This creates an emergent forex market between realms.

## 6.4 Realm Discovery

New realms appear on the inter-realm map as they are created. Players can browse available realms, see population, activity level, and custom rules before deciding to migrate. Realms that go offline have their connections suspended; returning players find their frozen accounts intact.

# 7. Spell Library & Grimoires

## 7.1 Personal Spell Library

Every caster has a personal spell library — a database of all spells they have ever created. The library is local to the player; when creating a new spell, the AI only checks for duplicates against this player’s library, not the global database. This keeps spell creation fast and avoids penalizing creativity.

Spells enter the library through:

- Academy training (starter spells learned during education)

- Personal creation (every successfully created spell is auto-added)

- The library is the pool of base spells for the creation system — you can only build on spells you own

## 7.2 Grimoires

A grimoire is a physical item — a book that holds a subset of spells from your library. In combat, you can only cast spells that are written in the grimoire you brought.

- **Purchase** — grimoires are bought, not crafted. Different price tiers offer different capacities.

- **Capacity vs. Weight** — expensive grimoires hold more spells (up to ~45) but weigh more. A heavier grimoire means less room for loot in your inventory when dungeon-crawling. Cheap grimoires hold few spells (~5–10) but are lightweight.

- **Write-once** — once spells are inscribed in a grimoire, they cannot be erased or overwritten. To change your loadout, you need a new grimoire.

- **One in combat** — a player can own multiple grimoires (stored at base) but brings only one into any given fight.

- **Strategic choice** — before entering a dungeon or duel, choosing which grimoire to bring is a key decision. A big grimoire gives flexibility but costs carry capacity. A small grimoire is light but limits your options.

# 8. Alchemy & Workshops

- Fixed set of ingredients and tools with predefined effects

- Effects change depending on ingredient combinations

- Requires a dedicated workshop at your base

*Alchemy details are covered under Academy tracks (section 9.3.2). The crafting system will be expanded in a future revision.*

# 9. Academy

The Academy is the primary progression gateway. Every player passes through it. It provides education, social connections, and specialization. Located in the main city.

## 9.1 Basic Education (Mandatory)

All players begin with basic education. This is free and covers fundamentals: history of the realm, basic survival, overworld navigation, and economic literacy. Duration: 10 in-game years (~10 real days).

During basic education, players join social clubs — interest groups where they meet other players, form friendships, and find future party members. Clubs persist and become even more important during university (see 9.6).

## 9.2 Admission to the Academy

After basic education, players can enter the Academy proper through two paths:

- **Merit grant** — players who performed well during basic education (good grades, club participation, etc.) receive a scholarship funded by the charity fund. Free tuition.

- **Self-funded** — players who don’t qualify for a grant pay tuition out of pocket.

## 9.3 Specialization Tracks

Upon entering the Academy, players choose one of three tracks. This choice defines their class for the rest of the game (though retraining is possible).

### 9.3.1 Wizardry (Caster track)

- Learn to cast spells using the incantation system

- Choose 2 schools of magic (out of 8) as your specialization

- Can only cast spells from your chosen schools

- Retraining is possible: choose 2 new schools, but old schools are lost. One of the two may overlap with a previous choice.

- Spells created during training become your starter library

### 9.3.2 Alchemy (Crafter: Potions)

- Phase 1 (Bachelor’s): learn basic potion creation — follow recipes, use standard ingredients

- Phase 2 (Master’s): learn to use all alchemical instruments and advanced techniques

- Phase 3 (Postgraduate): develop your own original methods and recipes

### 9.3.3 Mastery (Crafter: Tools / Tool User)

- Learn to create tools, weapons, shields, and equipment from the start

- This is the track for the tool user class (formerly called “Knighters” in early notes)

- Tools and weapons crafted here are used in overworld combat where magic doesn’t work

## 9.4 Duration & Post-Graduation

The core Academy program takes 3 in-game years (~3 real days). After completing it, players can:

- **Graduate and go to work** — enter the world as a dungeon runner, trader, crafter, etc.

- **Extended study (+2 in-game years)** — deepen specialization. Approximately 2 more real days.

- **Enter Academia** — the long-term research path (see below).

## 9.5 Academia (Research Path)

After graduation, players can choose the academic career. This is a slow, prestigious path focused on creating new knowledge for the community:

- Work on creating new, original spells/potions/tools for the public spell database

- Early research is easy (low-hanging fruit); later discoveries become progressively harder

- Culminates in a doctoral thesis — the ultimate challenge

- After receiving the doctorate, a player can become a Professor

- Professors write courses for the Academy, shaping how future players are taught

- This creates a player-driven education system where high-level players define the curriculum

## 9.6 Clubs

Clubs are a core social mechanic that spans all stages of education and beyond. They begin during basic education and continue through university, becoming more specialized and important over time.

- Basic education clubs: general interest (exploration, history, crafting)

- University clubs: specialized and practical — dueling clubs (practice PvP with friends), research groups, expedition planning societies

- Clubs are where players find party members, practice combat in a safe setting, and build the social connections that matter in the dungeon

- Duel clubs in particular let students train against each other with low stakes before entering real dungeons

# 10. The Dungeon

A single massive mega-dungeon beneath the Tower. Inspired by Dungeon Meshi and Made in Abyss: a living, vertical world with its own ecosystem, communities, and an AI overseer that keeps the dungeon in flux. This is not a place you clear in an afternoon — expeditions last months or years of game time.

## 10.1 Structure

The dungeon is organized into descending levels (floors). Each level is a non-linear graph of rooms/nodes with branching paths, dead ends, shortcuts, and hidden connections. The general layout of each level is fixed (landmarks, key passages, level transitions), but details are procedurally generated and shift over time under the dungeon AI’s control.

- ~7+ levels, each progressively harder and stranger

- Levels 1–3: accessible to competent parties with Academy training

- Levels 4–5: require experienced, well-equipped teams

- Levels 6–7+: only for elite players. Reaching these depths is a major achievement.

## 10.2 The Dungeon AI

An AI system oversees the dungeon, maintaining balance and unpredictability. It does not directly control monsters or events, but it shapes the environment:

- Shifts room connections and passages over time (the dungeon “breathing”)

- Spawns resources, creatures, and hazards based on player activity

- Ensures no path becomes too safe or too farmed

- Introduces rare events, environmental changes, and anomalies

*The dungeon AI is distinct from the combat orchestrator. The orchestrator handles individual fights; the dungeon AI manages the macro-level ecosystem.*

## 10.3 Living in the Dungeon

The dungeon is a world unto itself. Extended expeditions are the norm, not the exception. Parties must manage:

- **Food and supplies** — brought from the surface or scavenged inside. Running out is dangerous.

- **Party composition** — not just fighters. You need support roles: someone to repair equipment (tool user/crafter), someone to prepare potions and food (alchemist), someone to cast the Return Ritual (caster), and fighters to handle combat.

- **Loot management** — everything you find must be carried. Grimoire weight competes with loot weight. Deciding when to head back is a constant tension.

- **Other players** — PvP is active inside the dungeon. Other parties can ambush you, kill your team, and take everything you’re carrying.

Communities exist on the upper levels — micro-villages, rest stops, and trading posts where delvers congregate between expeditions. These are semi-safe social hubs inside the dungeon.

## 10.4 Navigation & Return

Two ways to get back to the surface:

- **Fixed ascent points** — permanent staircases/elevators at known locations on each level. Safe but often far from where you are. Reaching one while injured and loaded with loot is its own challenge.

- **Return Ritual** — a caster in the party can perform a ritual to teleport the group back to the surface. Requires preparation time (vulnerable during casting), and possibly rare components for deeper levels. This is why every serious party needs at least one caster.

## 10.5 Death & Roguelike’s Sacrifice

Permanent death does not exist in the dungeon, thanks to Roguelike’s Sacrifice — an ancient lore event that anchors all souls to the surface. When a party’s shared HP hits zero:

- All party members are revived at the Tower entrance

- All carried loot and inventory is lost (dropped at the death location or taken by attackers)

- Grimoires are lost (they are physical items)

- XP earned during the run is kept

- The sting is economic, not existential: you lose stuff, not progress

## 10.6 Rewards

The dungeon is the primary source of:

- XP (highest rates in the game, especially on deeper levels)

- Rare ingredients (for alchemy and crafting)

- Currency (coin drops, sellable loot)

- Unique items and materials not found anywhere else

- Knowledge (spell fragments, lore, research data for academics)

# 11. XP & Leveling

## 11.1 XP Range & Curve

- Level range: 1–100

- Total XP from level 1 to 100: 1,000,000 XP

- Curve: logarithmic — early levels come fast, high levels require disproportionately more XP

The curve flattens significantly past ~level 70. Reaching level 100 is a long-term achievement, not something achievable in weeks.

## 11.2 XP Sources

XP is awarded for virtually any meaningful activity, but in small amounts. The design intent is that no single activity can be cheesed for fast leveling — diverse play is rewarded over grinding one system.

- Fights (duels and dungeon combat)

- Spell creation (successfully creating a new spell)

- Potion creation and crafting

- Academy training and study

- Scavenging and exploration

- Trading (completing trades)

- Dungeon completion (bonus XP for finishing a run)

- Passive XP during "Leave the Realm" (reduced rate)

Rarer and harder events give more XP. Defeating a high-level dungeon boss yields far more than crafting a basic potion. Repeating the same activity yields diminishing returns.

## 11.3 Level-Up Rewards

Most levels give small quantitative boosts (slightly more HP, stamina, inventory slots). However, specific milestone levels grant qualitative upgrades — entirely new capabilities rather than just bigger numbers.

- **Regular levels** — +HP, +stamina, +minor stat increases

- **Milestone levels** — unlock new mechanics, abilities, or access (e.g., new spell slot, access to a new dungeon tier, ability to teach at the Academy)

*The specific milestone levels and their rewards are TBD. They will be placed at uneven intervals to create surprise and anticipation, not at predictable round numbers.*

# 12. Economy & Trading

The economy is a closed system with a fixed money supply. There is no money printing — every coin in circulation was originally minted into the Treasury at world creation. Money flows from the Treasury to players and back through taxes. The total amount of currency in existence never changes; only its distribution does.

## 12.1 Fixed Money Supply

- A fixed pool (e.g., 1 billion coins) exists in the Treasury at world start

- At launch, roughly half is distributed to players based on initial activity (seeding the economy)

- The remaining half stays in the Treasury and is released through NPC services, quest rewards, Academy stipends, and other sinks/faucets

- The existing database already tracks Treasury balance and per-player balances

## 12.2 Taxation

All legal transactions are taxed. Tax revenue flows back into the Treasury, creating a closed loop:

Treasury → NPC payments, quest rewards, Academy funding → Players → purchases, services, trades → Tax → Treasury

- Tax applies to: NPC shop purchases, legal P2P trades, property transactions, Academy tuition, duel wager payouts

- Tax rate: flat percentage (exact rate TBD, tuned for economic health)

## 12.3 Black Market (Illegal P2P)

Players can conduct trades outside the legal system to avoid taxes. This is the black market — untaxed P2P transactions. The trade-off:

- **Advantage** — no tax, potentially better prices

- **Risk** — no buyer/seller protection (scams possible), potential penalties if caught (fines, reputation loss, NPC hostility)

*The black market is an intended emergent mechanic, not an exploit. It creates a risk/reward decision and a role for player-run enforcement or thieves’ guilds.*

## 12.4 Money Sinks & Faucets

- Quest rewards and dungeon loot (coins)

- NPC vendor purchases (selling items to NPCs)

- Academy stipends for charity-funded students

- Taxes on all legal transactions

- NPC shop prices (buying items from NPCs)

- Property purchase and maintenance

- Academy tuition (for paid tiers)

- Charity fund donations (optional — funds Academy scholarships for other players)

## 12.5 Charity Fund

Players can donate to a charity fund that subsidizes Academy education. This is a social mechanic: wealthy players fund new players’ education, creating community bonds. Donors may receive recognition (titles, public listing) but no mechanical advantage.

# 13. Parties & Roles

Parties are the core social unit. While solo play is possible (especially in the overworld), dungeon expeditions practically require a group. There are no hard-coded roles like tank/healer/DPS — roles emerge naturally from class choice and equipment loadout.

## 13.1 Party Formation

- Parties are formed voluntarily — invite players, agree on terms

- No hard size limit, but larger parties split XP and loot more ways

- Dungeon expeditions with 4–6 members are the practical sweet spot

- Parties can be formed anywhere: in Academy clubs, city taverns, Tower entrance, or even inside the dungeon

## 13.2 Emergent Roles

Roles are not assigned — they emerge from what each player brings. A well-composed dungeon party needs:

- **Frontline (Tool Users)** — melee fighters with swords and shields. Absorb damage via shielded states, deal consistent impact damage. Dominate overworld escort missions. In the dungeon, they protect the casters.

- **Casters (Wizards)** — the primary damage and control source inside the Tower/Dungeon. Create situational effects (trapping, burning, freezing). One caster must know the Return Ritual to get the party home.

- **Alchemist (Crafter: Potions)** — prepares potions, cooks food from scavenged ingredients, heals the party between fights. Thrown potions provide ranged support in combat. Essential for long expeditions.

- **Crafter (Mastery)** — repairs equipment, maintains tools, builds temporary fortifications at rest stops. Without a crafter, gear degrades and shields break permanently.

A party of 5 wizard-casters can technically enter a dungeon, but they will starve, their gear will break, and they will have no way to fight on the overworld road to the Tower. Diverse composition is a survival requirement, not a suggestion.

## 13.3 Loot & XP Sharing

- XP is split equally among party members present for the event

- Loot distribution is agreed upon by the party (first come, round robin, or leader decides)

- No enforced loot rules — betrayal is possible (grab everything and run). Social consequences apply.

# 14. Scavenging & Survival

Survival mechanics apply in the overworld and the dungeon. The core resources are food and supplies. Managing them is a key part of expedition planning.

## 14.1 Food

Food is consumed at a rate of 1 unit per game-day per player (~4 real minutes). Sources:

- **Purchased** — buy rations from city NPC shops before departure. Reliable but heavy and expensive for long trips.

- **Scavenged** — forage in the overworld or dungeon. Unreliable — depends on region and luck. Raw ingredients need an alchemist to prepare.

- **Cooked by alchemist** — an alchemist in the party can combine raw scavenged ingredients into proper meals. Cooked food is lighter and more nutritious than raw or purchased rations.

Running out of food:

- Day 1 without food: movement speed penalty

- Day 2+: HP drain per game-day (from the shared party pool)

- Starvation does not kill (Roguelike’s Sacrifice), but it can weaken the party enough to lose a fight

## 14.2 Scavenging

Scavenging is the act of searching the environment for useful materials. Available in the overworld and dungeon, with different loot tables per region/level.

- Overworld scavenging: herbs, basic ingredients, wood, stone. Low risk, low reward.

- Dungeon scavenging: rare ingredients, spell fragments, unique materials, coins. Higher risk, much higher reward.

- Scavenging takes game-time (you stop moving to search an area)

- Some materials are only available in specific dungeon levels or overworld regions

- Scavenging gives small XP rewards

## 14.3 Weight & Carry Capacity

Everything has weight. Every player has a carry limit based on level and equipment. Weight considerations:

- Food rations are heavy — packing for a long trip means less room for loot

- Grimoires take weight (larger = heavier)

- Loot from scavenging and combat adds up

- Exceeding carry limit: movement speed penalty, cannot flee combat

- This is why choosing a small grimoire for a loot-focused run is strategic

# 15. Monetization

MMGO is completely free to play. There are no premium subscriptions, no pay-to-win mechanics, and no paywalled content. The game is sustained by voluntary donations.

## 15.1 Donation Model

- Players can donate real money to support server costs and development

- Donations grant no mechanical advantage whatsoever — no bonus XP, no exclusive items, no stat boosts

- Donors may receive cosmetic recognition: titles, visual flair on their profile, a place on a public donor board

- The in-game charity fund (Academy scholarships) is funded with in-game currency, not real money

## 15.2 Principles

- No loot boxes, gacha, or gambling mechanics with real money

- No premium currency

- No pay-to-skip-time mechanics

- A new player and a donor have identical mechanical capabilities

# 16. Game Meta & Design Philosophy

## 16.1 Core Experience

MMGO is a slow, social, text-based MMO where the journey matters more than the destination. It is not a game you “win” — it is a world you inhabit. The ideal session is 15–60 minutes of meaningful decisions: planning an expedition, negotiating a trade, composing a new spell, or navigating a dungeon level with your party.

## 16.2 Design Pillars

- **Player-driven world** — the economy, Academy curriculum, spell database, and social structures are shaped by players, not predetermined content. Professors write courses. Players set market prices. The dungeon AI reacts to player behavior.

- **Meaningful trade-offs** — every decision has a cost. Living near the Tower means danger. Carrying a big grimoire means less loot. Spending time in Academia means less dungeon experience. There are no objectively correct choices.

- **Social interdependence** — solo play is possible but limited. The game is designed so that different classes need each other: casters need tool users for overworld travel, tool users need casters in the dungeon, everyone needs an alchemist for long expeditions.

- **AI as game master** — the AI is not a replacement for content — it is a content amplifier. The spell creation system, combat orchestrator, and dungeon AI all use AI to make player actions feel unique and consequential rather than templated.

- **No pay-to-win** — the game respects players’ time equally. Progress comes from skill, knowledge, and social connections, not money.

## 16.3 Target Audience

- Players who enjoy text-based and MUD-style games

- Fans of collaborative RPGs (Dungeon Meshi, Made in Abyss vibes)

- Players who like theorycrafting and creative systems (spell composition)

- Social gamers who want persistent relationships and communities

- Telegram-native users looking for deep gameplay in a chat-based format

## 16.4 Technical Platform

- Telegram Mini App (frontend) + Telegram bot (notifications, commands)

- Backend server with PostgreSQL (economy, players, spells already partially built)

- Gemini API for spell resolution, combat orchestration, and narrative generation

- Starsector-style map rendered in the Mini App

- Text-based event system for all non-map interactions
