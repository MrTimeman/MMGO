# Academy & Academia Deep Dive — GDD §9 Rewrite

## Context

GDD §9 currently describes the Academy at a single page: three tracks, three durations, a brief Academia path, and a one-paragraph mention of clubs. The Elixir side already ships the skeleton — `MMGO.Academy` (enrollment lifecycle, specialization school-locking, Oban completion jobs), `MMGO.Academia` (time-based research projects → auto-published works, professor appointments, course publishing), and `MMGO.Clubs` (schema + memberships) — but the *experience* of attending school is absent: no activities during the timer, no student-facing course enrollment, no exams, no club events, no play UI.

The problem: 10 game years of basic education compress into 10 real days (the Travel.Clock gives 364 game days / real day). As currently designed a student enrolls, waits 10 days, collects 100 XP, and graduates. That's not education — it's a kitchen timer. We want those 10 days to feel like 10 memorable *years* of compressed school life: lectures, exams, club nights, duels at dawn, a thesis defense that can actually fail.

User direction (confirmed):
- Output is a **GDD §9 rewrite** (not code yet).
- **Required weekly check-ins** — real consequences for absence, not AFK-safe.
- **Seeded defaults + professor overlays** — NPC curriculum ships at launch; player-authored courses layer on top.
- Social focus: **Clubs**, **professor–student ties**, **grades/rankings/rivalries**. (Cohorts/study-groups intentionally de-prioritized.)

## Target File

`docs/MMGO_GDD.md` — replace §9 (lines ~524–611) with the expanded section below. Keep all surrounding section numbering intact.

## The Rewrite — §9 Academy (replaces current §9)

### 9.0 The Term System (new)

The Academy's time backbone is the **term**. One term = one game year = roughly one real day. Every enrollment is divided into terms; each term has a fixed rhythm of scheduled events that the player must engage with. Terms are the unit of attendance, grading, and social life.

Each term contains, in order:
1. **Enrollment window** (first game-month of term) — choose courses from the bulletin board.
2. **Lecture phase** — 2–3 lecture events become available across the term.
3. **Club window** — clubs host events; attendance opens friendships and training.
4. **Midterm check-in** — optional formative exam (partial credit toward final grade).
5. **Final exam** — mandatory; graded.
6. **Term break** — short, free time for travel, light dungeon runs, base work.

Durations (unchanged, reaffirmed from existing code):
| Program | Game-years | Real-days | Terms |
|---|---|---|---|
| Basic Education | 10 | 10 | 10 |
| Academy Core | 3 | 3 | 3 |
| Extended Study | 2 | 2 | 2 |
| Academia coursework | 4 | 4 | 4 |
| Thesis | variable | variable | n/a |

### 9.1 Basic Education (mandatory, 10 terms)

Free, universal. Curriculum is seeded and NPC-taught: history of the realm, elemental literacy, overworld survival, economic basics, civic law, Latin fundamentals (practical for incantation writing later).

**Required per term:** one final exam. Missing it counts as a failed term.
**Optional per term:** 2 lectures (+knowledge XP), 1 midterm (boosts final grade ceiling), 1–2 club events.

**Grading:** each term exam scored 0–100. A running **GPA** is stored on the enrollment's metadata and visible on the bulletin board.

**Consequences of absence:**
- Fail ≤ 3 terms → graduate as Pass.
- Fail 4–6 terms → graduate on Probation (reduced starter spell set, no scholarship eligibility).
- Fail ≥ 7 terms → Expulsion. Character can re-enroll after a game-year cooldown, losing the charity-fund slot.

**Outcome tiers (set at graduation):**
- **Distinction** (GPA ≥ 85, ≤ 1 failed term) → merit scholarship offer + bonus starter spells + Academy Honors title.
- **Pass** → standard admission eligibility, self-funded by default.
- **Probation** → admission eligibility only with professor endorsement (see 9.8).

### 9.2 Admission to the Academy

Unchanged in principle; clarified:
- **Merit grant** — awarded to Distinction graduates and the top 25% of Pass graduates per cohort, funded from the Charity Fund. Covers tuition.
- **Self-funded** — Pass graduates and below pay out of pocket.
- **Professor endorsement** — a Probation graduate may enter if a Professor signs a recommendation letter (new mechanic, see 9.8).

### 9.3 Specialization Tracks (3 terms)

Same three tracks: **Wizardry**, **Alchemy**, **Mastery**. Each track is structured as three year-long terms:

**Year 1 — Fundamentals.** Seeded NPC courses introduce tools of the trade. For Wizards: the two chosen schools, incantation construction. For Alchemists: ingredients taxonomy, basic brewing. For Masters: materials, basic forging.

**Year 2 — Practice.** Coursework is applied: wizards compile their first three **starter spells** (which enter their library on graduation); alchemists develop three starter recipes; masters forge three starter tools. Quality of these starters depends on term grade.

**Year 3 — Thesis project (mini).** A term-long capstone — not the Academia thesis, but a scaled-down graded project. Pass is required to graduate.

**Required per term:** 1 midterm + 1 final.
**Optional per term:** seminars, club events, professor office hours.

**Retraining** (existing rule preserved): a graduate can re-enter Academy Core with a new track. Old specialization is retired; one school may overlap if retraining within Wizardry.

### 9.4 The Bulletin Board & Course Catalog (new)

The Academy lobby contains a persistent **bulletin board** — the student-facing UI. It lists:
- **Courses offered this term** — each row shows course title, professor (NPC or player), school/track, schedule, seat count, syllabus preview.
- **Exam schedule** — upcoming midterms and finals for enrolled courses.
- **Club events** — dueling tournaments, research symposiums, expedition briefings.
- **Cohort leaderboard** — live GPA rankings for the current graduating class.
- **Thesis defenses** — scheduled defense dates for senior Academia students (open to all students as audience).

**How courses populate the catalog:**
- **Seeded courses** are authored at realm creation and run every term — the floor of the curriculum. They are taught by NPC professors.
- **Professor-authored courses** (publications of kind `:course`) appear on the bulletin when a Professor schedules a term. A player-authored course covering the same material as a seeded course **replaces** the seeded section for that term — giving players who teach well real pedagogical power.
- **Prestige**: high-GPA students preferentially pick player-authored courses (if they know the professor or the professor has reputation), creating a reputation loop for Professors.

### 9.5 Lectures and Exams (new)

**Lectures** are short text-event interactions — a few paragraphs of in-world content followed by 2–3 comprehension questions. They award knowledge XP and raise the ceiling on the term's final exam score. Seeded lectures have static content; professor-authored lectures are written by the authoring player at course creation time.

**Exams** are timed text events — ~5 real minutes. Mix of:
- Multiple-choice knowledge questions (seeded from curriculum).
- Applied challenges: wizards write a compliant incantation under constraints; alchemists pick ingredients for a stated effect; masters choose materials for a stated tool.

Grading is deterministic where possible (MC answers, recipe matching) and uses the Spell Compiler output for wizardry applied questions — no live storyteller in the grading path. Exams produce a 0–100 score, stored as an `academy_term_result` row.

**Cheating / collaboration:** exams are individual. Party chat is locked during the 5-minute window. Possession of a prior student's exam notes (a looted "crib sheet" item) can grant a small grade boost but is detected with probability, producing a reputation hit and exam nullification.

### 9.6 Grades, Rankings, Valedictorians

Every term exam score feeds:
- **GPA**: running mean across the program.
- **Cohort rank**: position among all students graduating in the same term.

**Rewards at graduation:**
- **Valedictorian** (rank 1 per cohort per realm) — unique title, bonus starter spell of their choice, pinned on the bulletin board hall-of-fame for one real year.
- **Top 10%** — Distinction or Honors title (depending on program).
- **Merit scholarship for Academy Core** — top 25% of basic ed.
- **Advisor pick rights in Academia** — top 10% of Academy Core graduates may request any Professor as advisor; others are matched by availability.

Rankings are public on the bulletin board — a deliberate source of rivalry.

### 9.7 Clubs (expanded)

The existing `academy_clubs` schema gains event mechanics. Every club hosts at least one **club event** per term — a scheduled, joinable activity. Four club types, each with its own event loop:

- **General-interest clubs** — lore circles, exploration societies. Events are text-based social gatherings with small knowledge XP, faction reputation seeds, and friendship ties (recorded for future party bonus).
- **Dueling clubs** — friendly PvP with **no wager**. Uses the normal combat engine, but death is bloodless and loot is not transferred. Club ladder tracks wins/losses per term. Top duelists on the ladder earn prestige and unlock access to inter-club tournaments.
- **Research clubs** — shared notes. Members contribute partial research toward a group goal (e.g., "document a Life-school ward spell"). When one member discovers/completes the work in Academia later, all contributors receive a fraction of the project XP retroactively.
- **Expedition-planning clubs** — expedition briefings, route scouting, intended as the social origin point for later dungeon parties. Each meeting is a text-event where members discuss (in chat) a simulated dungeon map and submit a plan; good plans boost the next real dungeon run of the participating members.

**Founding a club** — any Academy Core student or Professor can found a club for a small fee. Clubs persist across the founder's graduation; alumni can remain members.

**Attendance consequences:** attending ≥ 1 club event per term is required to qualify for the Merit scholarship and for top-quartile rankings. This is the lever that makes school social rather than isolating.

### 9.8 Professor–Student Ties (new)

**Office hours.** Every Professor (player or NPC) schedules 1 office-hour event per term on their courses. Attending office hours boosts the attending student's grade ceiling in that course by 5 points and builds a relationship score.

**Advisors.** Upon entering Academia, a student selects an **advisor** from the Professor pool. The advisor relationship grants:
- +20% research project speed for the advised student.
- Advisor's published spells/potions/tools become available as base items for the student's research.
- Advisor can write a **recommendation letter** (a non-transferable item that unlocks specific gated paths: scholarship overrides, foreign-realm academic visits, special club invitations).

**Halo / reputation.** Professor reputation is a running score driven by students' outcomes:
- +reputation when an advised student publishes a thesis, becomes valedictorian, makes a notable discovery.
- −reputation when an advised student fails a thesis defense, drops out of Academia, or is caught cheating.
Reputation drives which students queue for a professor's courses next term (prestige loop) and eligibility for Academy Headship (see 9.10).

**Rivalry between professors.** Professors may mark another professor as a **rival**. Rivalry is visible on profiles and amplifies reputation effects in zero-sum events (shared cohort rankings, thesis defense panels).

### 9.9 Academia (research path, expanded)

The existing research-project schema is preserved. The new surface is **defense and peer review**:

**Publication is no longer automatic for thesis projects.** On thesis completion, a **Thesis Defense** is scheduled 3 game-days out, publicly announced on the bulletin board. The defense is a timed text event:
- The student defends their claimed contribution.
- A panel of 3 Professors (the advisor + 2 others, rival preferred by matching logic) pose structured questions.
- The panel votes: **Accept**, **Accept with Revisions**, **Reject**.
- Reject → thesis delayed one game-season for rework; two rejects in a row → thesis abandoned, character keeps Academia credentials but no Professor status.

Thesis defenses are **open audience** — any character in the city can spectate, generating social/theatrical stakes that justify the "historic moments" tone the GDD aims for.

Non-thesis projects (spell/potion/tool research) keep auto-publish; they are the bread-and-butter research output. Only thesis gates Professor status.

### 9.10 Careers After Graduation

Existing options (Graduate / Extended Study / Academia) are preserved. Three long-tail career states are added:

- **Professor** — publishes courses, takes advisees, gains reputation. Earns a stipend per term of active teaching, paid from tuition.
- **Academy Head** — realm has one at a time. Elected every ~10 real days by current Professors from among themselves by plurality vote. The Head sets seeded-curriculum overrides, admits Probation students, and manages the Charity Fund's scholarship allocation. Strong political hook.
- **Researcher Emeritus** — a retired Professor who stops teaching but retains publication rights and advisor-letter authority. Soft off-ramp for high-level players.

### 9.11 What Does Not Change

To keep scope honest, the following remain as specified earlier in the GDD:
- Three tracks (Wizardry / Alchemy / Mastery).
- Eight schools and the two-school Wizardry specialization rule.
- Existing durations (10 / 3 / 2 / 4 game years).
- Existing XP grants on program completion.
- Existing `school_permitted?/2` school-locking semantics.
- Charity Fund as the scholarship funding source.

## Implementation Notes (out of scope for this doc, but recorded for the follow-up)

For the code work that will follow this GDD update, the key additions will be:
- `academy_terms` (term_number, enrollment_id, started_at, ended_at, exam_score, status).
- `academy_courses` (realm_id, source `:seeded|:published`, publication_id nullable, track/school focus, syllabus json).
- `course_enrollments` (term_id, character_id, course_id, grade).
- `club_events` (club_id, scheduled_at, kind, result_metadata) and `club_event_attendance`.
- Advisor link — new column on `academia_projects` or a dedicated `advisor_relationships` table.
- Thesis defense scheduling: extend `academia_projects` with a `defense_scheduled_at` and a `defense_state`; a new Oban worker runs the defense.
- `professor_reputation` table (or a running metadata blob on `academia_professors`).
- LiveView pages: `StudyDeskLive` (demo exists at `lib/mmgo_web/live/hooks_demo_live.ex:173–189`), `BulletinBoardLive`, `ExamLive`, `ClubEventLive`.
- Wire `MMGO.Academy.complete_enrollment_by_id` to use the term-result aggregate (GPA, failed-term count) when deciding outcome tier — currently at `lib/mmgo/academy.ex:78–128`.

These are *not* part of this plan; they belong to the next planning pass after the GDD lands.

## Verification

- Read the rewritten §9 end-to-end; confirm it reads cleanly against §11 (XP), §12 (Economy/Charity Fund), §13 (Parties), and §6 (Inter-realm) with no contradictions.
- Confirm that every rule cited as "existing" matches current code: `lib/mmgo/academy.ex`, `lib/mmgo/academia.ex`, `lib/mmgo/clubs.ex`, `lib/mmgo/accounts/character.ex`, `lib/mmgo/travel/clock.ex`, migrations `20260327165015` and `20260328214438` and `20260328155324`.
- Sanity-check the term math: 10 terms × ~1 real day = 10 real days for basic ed ✓; 3 terms × 1 day = 3 real days for academy core ✓. Both match `default_duration/1` at `lib/mmgo/academy.ex:298–301`.
- Confirm no §9 rule requires a new state the engine doesn't already track (except the listed implementation-notes additions, which are flagged as future work).
