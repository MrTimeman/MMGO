# Spell & Ingredient Expansion — Design & Implementation Plan

## What we're building

Three additions that extend the existing magic and alchemy systems without breaking the current
combat-spell model.

---

## 1. Passive Spells

Passive spells are persistent auras the caster toggles on and off. They are not cast per-turn.
While active, they **reserve** a portion of the caster's max mana — reducing the pool available
for active spells. The tradeoff is always-on benefit at the cost of peak casting power.

**Model fields added to `Spell`:**
- `spell_type` enum — `:active` (default), `:passive`, `:utility`
- `mana_reservation` integer (default `0`) — amount subtracted from max mana while the passive
  is toggled on. Only meaningful for `:passive` spells; validated to be `0` for others.

**Mechanics:**
- Toggling costs one combat action.
- Passive effects use the existing `SpellEffect` structure, applying to `:caster` or
  `:environment` (never `:target` — passives cannot be aimed at enemies).
- Silenced state prevents toggling but does not deactivate an already-running passive.
- Max mana reduction is permanent while active — a caster running two passives on 30-mana
  reservation each has 60 less max mana for the entire fight.

**Examples:**
- A fire ward passive: applies `shielded` at low intensity to caster each turn, 30 mana reserved.
- A burning aura: applies `burning` to any enemy in zone each turn, 50 mana reserved.

---

## 2. Utility Spells

Utility spells are cast outside of combat. They affect the dungeon environment, provide
information, or alter the world state. They use the same incantation system as active spells but
their effects map to non-combat states.

**New states added to `SpellEffect`:**
- `"revealed"` — uncovers hidden paths, secret doors, invisible entities
- `"warded"` — marks a zone with an alarm or repulsion effect
- `"illuminated"` — lights a zone, removes environmental darkness penalties
- `"detected"` — marks the presence of creatures, traps, or magical signatures in range
- `"transmuted"` — alters the material or quality of an object or zone

**Mechanics:**
- `failure_profile` still applies — utility spells can fail or partially succeed.
- `fatigue_cost` still applies — casting outside combat still tires the caster.
- `targeting` modes `:self` and `:zone` are the only valid options for utility spells.
- Utility effects persist in the dungeon state across turns (they are environmental, not combat).

---

## 3. Base Ingredients

Ingredients now carry a `description` (flavour + hint at use) and a bounded list of `qualities`
that describe their alchemical properties. Qualities are a fixed vocabulary — the AI and future
recipe system select from them, same as spell effects select from `@supported_states`.

**Fields added to `ItemTemplate`:**
- `description` string — one or two sentences, flavour + practical hint
- `qualities` array of strings — validated against the vocabulary below

**Quality vocabulary (13 values):**

| Quality | Meaning |
|---|---|
| `fire_catalyst` | Amplifies fire-school effects in brews |
| `binding` | Extends effect durations |
| `volatile` | Increases intensity but raises variance and failure risk |
| `restorative` | Contributes to healing and regenerating effects |
| `numbing` | Suppresses active negative states |
| `purifying` | Cleanses debuffs and magical contamination |
| `toxic` | Applies damage-over-time effects (burning-adjacent) |
| `conductive` | Channels and amplifies magical energy |
| `stabilizing` | Reduces brew failure rates and variance |
| `soporific` | Induces staggered or incapacitated states |
| `luminous` | Illumination, revelation, and detection |
| `corrosive` | Degrades shielded state and armor durability |
| `arcane` | Pure magical amplifier, school-neutral |

---

## 4. Base Ingredient Seed Set (15 items)

### Fire
| Name | Qualities | Description |
|---|---|---|
| Ember Moss | `fire_catalyst`, `volatile` | A rust-red moss found near volcanic vents. Burns to the touch. Excellent catalyst for fire brews but notoriously unstable. |
| Magma Shard | `fire_catalyst`, `corrosive` | A crystallized fragment of cooled lava, still warm. Corrodes container walls if left unbound. |
| Searing Petal | `fire_catalyst`, `stabilizing` | Thin petals from a heat-resistant desert flower. Carries fire affinity but burns clean with no dangerous residue. |

### Restoration
| Name | Qualities | Description |
|---|---|---|
| Moonleaf | `restorative`, `purifying` | A soft silver-green leaf harvested at night. The base of most healing draughts, mild and reliable. |
| Healer's Root | `restorative`, `binding` | A dense fibrous root from the wetlands. Slow to process but provides sustained healing that holds with binding agents. |
| Dewdrop Fungus | `restorative`, `stabilizing` | A small white mushroom from cool cave systems. Extremely stable in solution — the alchemist's safety net. |

### Structure & Duration
| Name | Qualities | Description |
|---|---|---|
| Ironwood Bark | `binding`, `stabilizing` | Dried bark from an ironwood tree, dense and resinous. Unremarkable alone but indispensable in complex brews. |
| Spider Silk Extract | `binding`, `conductive` | A viscous extract from dungeon spider webs. Exceptional binding properties and unusual magical conductivity. |

### Arcane & Utility
| Name | Qualities | Description |
|---|---|---|
| Glowstone Dust | `luminous`, `conductive` | Ground from naturally occurring luminous mineral. Core ingredient for visibility potions and detection brews. |
| Witchwood Ash | `arcane`, `volatile` | Ash from a ritually burned witchwood branch. A potent magical amplifier, unpredictable without a stabilizer. |
| Nullweave Fiber | `purifying`, `stabilizing` | Pale fibers from a plant that grows only where old spells have faded. Suppresses magical contamination. |

### Offensive
| Name | Qualities | Description |
|---|---|---|
| Viper Venom | `toxic`, `volatile` | Extracted from overworld vipers. Potent in small doses but degrades quickly without a preserving stabilizer. |
| Thornwood Extract | `corrosive`, `binding` | A resin from thornwood branches. Corrodes soft materials slowly but binds well, useful in sustained corrosive brews. |
| Blacksalt | `toxic`, `numbing` | A black mineral salt from deep dungeon seams. Toxic in quantity, numbing in trace amounts. |

### Control
| Name | Qualities | Description |
|---|---|---|
| Dream Poppy | `soporific`, `numbing` | Dried petals from a rare flower found in sheltered dungeon alcoves. The primary ingredient in sleep preparations. |

---

## Implementation checklist

- [ ] Migration: add `spell_type`, `mana_reservation` to `spells`; add `description`, `qualities` to `item_templates`
- [ ] `Spell` schema: new fields + validation (reservation must be 0 for non-passive)
- [ ] `SpellEffect`: add 5 utility states
- [ ] `SpellCompilePrompt`: add spell_type + mana_reservation to schema and instructions
- [ ] `ItemTemplate`: add description + qualities with vocabulary validation
- [ ] Seeds: insert 15 base ingredients
