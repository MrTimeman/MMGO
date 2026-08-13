# Arena rework — working plan

A handoff for a later sitting (or another coding agent). Read `AGENTS.md` first.

Shipped as `0.1.0-alpha.11`.

## Where the code stands

Released as alpha.11. `mix precommit` passes at **910** tests.

Do not commit `.gitea/ISSUE_TEMPLATE/` — it is the user's, and untracked on purpose.

### Built and tested

| Area | State |
|---|---|
| `Arena.Ladder` | 8 divisions, asymmetric K-factors, demotion buffer, placement multiplier |
| `Arena.Titles` / `Arena.TitleSeat` | Champion + Deputy seats, appointment, coup, idle rules |
| `Arena.TitleChallenge` | The gauntlet: Deputy fight, expiring right, cooldown, 7-day claim |
| Multiple arena profiles | Unique index dropped, picker screen, session switch |
| Craft → power → rank | `Spells.Compiler.craft_ceiling/2`, `power_budget/1`, `Ladder.division_for_power/1` |
| Grimoire capacity | Arena 45→8, world tiers 3/5/8/12 |
| Mana | Pools by division and seat, regen, insufficient checks, upkeep, earth locking |
| Melee | Accuracy roll, mana cost, terrain modifiers, creature autoattack roll |
| Active defence | `parry` / `block`, per-source efficiency, distinct from passive absorption |
| `Arena.RoomRules` | Custom-room toggles: grimoire, mana, rank, rank cap |
| `Arena.History` | Match history, turn-by-turn replay, 30-day retention job |
| `Arena.Seasons` | Season records, roll-over, awards, soft reset, placements |
| `Arena.Quests` | Daily/weekly quests, day streaks, nightly sweep, notifications |
| Arena UI | Fold fix, profile picker, seats, history, replay, result, quest board |
| Spell wipe | Release migration deletes every spell and re-issues starters |

---

## Design decisions already settled

Do not relitigate these; they were decided deliberately during the design pass.

### Craft sets power, rank sets access

A spell's power budget is earned by the **formula**, never by the caster.
`Spells.Compiler.craft_ceiling/2`:

- Seals filled → ceiling: 1→3, 2→4, 3→5, 4→15, 5→30, 6→50.
- Refining from a `base_spell` lineage → ceiling of `ancestor + 5`.
- Whatever the model proposes is clamped to that ceiling, then **every**
  magnitude (intensity, duration, variance, fatigue, cooldown) is rescaled to
  the clamped value via `power_budget/1`.

The result: a lazy three-seal formula is weak no matter who writes it; the top
of the range needs a full, coherent six-seal formula or patient lineage
refinement. **Being top rank must not by itself grant top spells.**

That earned number is the spell's **power**, and `Ladder.division_for_power/1`
turns it into the **rank requirement**. Rank decides who may wield it; craft
decides how strong it is. The column is `spells.power` — the old
`level_requirement` name is gone, along with the grimoire level band.

### The ladder

`lib/mmgo/arena/ladder.ex`. Rating start is 1000 → Bronze.

| Division | Floor | Win K | Loss K | Mana | Power gate |
|---|---|---|---|---|---|
| Initiate | 0 | +56 | −16 | 100 | 0 |
| Bronze | 900 | +48 | −20 | 115 | 4 |
| Silver | 1150 | +40 | −26 | 130 | 6 |
| Gold | 1400 | +34 | −30 | 150 | 11 |
| Platinum | 1650 | +28 | −28 | 170 | 16 |
| Diamond | 1900 | +22 | −24 | 190 | 23 |
| Archmage | 2150 | +16 | −20 | 215 | 31 |
| Champion | 2500 | +12 | −18 | 260 | 43 |

The Deputy's seat carries 240 mana: above every ordinary division, below the
Champion's.

Asymmetry is the point: early divisions sort fast and forgivingly, rates cross
at Platinum, then invert so holding the top costs more than reaching it.
Promotion is immediate on touching a floor; demotion needs a fall of 40 below it
so players do not flicker. The held division is stored on the profile
(`arena_profiles.division`), not derived from rating.

### Champion and Deputy

`lib/mmgo/arena/titles.ex`. Champion tier is **two named seats**, not a band.

- Gauntlet: beat the Deputy → earn an expiring right to challenge the Champion →
  beat them and take the seat.
- A coup vacates **both** seats; the deposed Champion falls to Archmage; the new
  Champion appoints fresh.
- The Deputy may **never** challenge — they defend only.
- A Champion with no Deputy is **frozen out of ranked play** and simultaneously
  unchallengeable. Refusing to appoint ends your season rather than protecting it.
- Idle Champion → the Deputy acts in their place and may appoint their own
  deputy, making an absent Champion easier to depose.
- Idle Deputy → the Champion's call whether to replace them.
- Title challenges **cannot be declined**; a challenge unanswered for **7 days**
  is claimed by the challenger.
- One seat per **account**, enforced by a partial unique index on
  `arena_title_seats(season, account_id) WHERE status = 'held'` — a player with
  several arena characters still cannot hold both seats.

### Mana is the economy

Everyone has a pool. Spells, swings and guards are paid out of it; standing
manifestations drain it each turn; earth manifestations lock the mana that made
them instead of draining. An emptying pool taxes accuracy, so spending the last
of it is a decision rather than a formality. Regen is 10% of the pool per turn,
floored at 8.

Cost is deliberately steeper than the pools widen: the strongest spell a rank
may legally wield costs about a sixth of an Initiate's pool and better than a
third of a Champion's. `test/mmgo/combat/mana_test.exs` holds that curve.

### Rules live in data, not in the mode

`Arena.RoomRules` resolves a host's settings once, and the resolved set is
copied into combat metadata when the fight starts. Ranked play is always the
ordinary arena; a friendly room may free the grimoire, free rank, cap rank, or
lift mana entirely. A title bout is a `:custom` match that explicitly asks for
ordinary rules — it moves no rating, because the stake is the seat.

---

## Work remaining

### 1. Declinable ordinary duels

The design pairs "title challenges cannot be declined" with "ordinary duels
become declinable". The first half is built (`Titles.decline_challenge/1`
refuses by name, and an unanswered challenge is claimed after 7 days). The
second half has nothing to attach to: the arena's ordinary paths are a queue and
open rooms, neither of which is an invitation, so there is no decline to offer.
Building it means adding arena duel invitations first — a feature in its own
right, not a flag on an existing one.

### 2. Deploying again

Follow `docs/DEPLOY_CONTINUATION.md`. Use a clean detached worktree; the main
worktree has untracked `.gitea` files.

The spell wipe is split in two on purpose. The migration
`20260813145307_wipe_spells_and_reissue_starters` only deletes, in raw SQL —
a migration runs against the schema as it stood at its own point in the
sequence, while the structs it would need are always at their newest, so an
earlier version crashed on `arena_profiles.placements_remaining`. Re-stocking
happens in the seed via `Arena.restock_empty_arena_books/0`, which runs after
every migration and only fills books that are empty, so repeating it is safe.
`down` leaves the spells deleted; there is nothing to restore them from.

Known trap: macOS `mktemp` does not expand non-trailing `X`s, so an interrupted
`just deploy` leaves `$TMPDIR/mmgo-<version>-<sha>.XXXXXX.tgz` behind and every
later deploy fails with `File exists`. Delete that file, or fix the template in
`justfile` (~line 273) to put the `X`s last.

### 3. Tuning, once it is played

The numbers are all in one place each and are meant to move:

- `Arena.Ladder` — floors, K-factors, mana pools, power gates.
- `Spells.Compiler` — seal ceilings and `power_budget/1`.
- `Combat.Engine` — melee accuracy and terrain table, guard costs, upkeep.
- `Arena.ActionSnapshot` — guard efficiency per source.
- `Arena.Seasons` — reward table, placement count, reset pull.
- `Arena.Quests` — goals and rewards.

---

## Where things live

| Concern | Module |
|---|---|
| Divisions, K-factors, mana, power gates | `MMGO.Arena.Ladder` |
| The rank a character carries into a fight | `MMGO.Arena.Ranks` |
| Seats and the gauntlet | `MMGO.Arena.Titles`, `.TitleSeat`, `.TitleChallenge` |
| Custom-room rules | `MMGO.Arena.RoomRules` |
| Seasons and awards | `MMGO.Arena.Seasons`, `.Season`, `.SeasonAward` |
| Quests and streaks | `MMGO.Arena.Quests`, `.QuestProgress` |
| History and replays | `MMGO.Arena.History` |
| Mana, melee, guards, upkeep | `MMGO.Combat.Engine` |
| What a client may ask for | `MMGO.Combat.ActionSnapshot` |

The Arena's exemption from the no-navigation rule in `docs/UI_DESIGN_BRIEF.md`
is documented there, in "The Arena exception".
