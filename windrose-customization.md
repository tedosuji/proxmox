# Windrose Server — What We Can Customize

Reference for **VindicatorsWindrose** (private, 6 players, password + invite code `32daf320`).

**How changes are applied:** the server has to be **stopped, edited, and restarted** (a ~1 minute blip — world saves are preserved). Tell Scoot what you want and he'll have it changed. Difficulty changes apply to the **world**, so anyone online just reconnects after.

> Note: as soon as *any* custom value below is set, the world's preset flips from Easy/Medium/Hard to **"Custom"** and keeps your exact values.

---

## 1. Server settings (operator-level — Scoot's side)

From `ServerDescription.json`. Mostly set-and-forget:

| Field | What it does | Current |
|---|---|---|
| `ServerName` | Display name | VindicatorsWindrose |
| `Password` / `IsPasswordProtected` | Join password | on |
| `InviteCode` | Code friends use to connect | `32daf320` |
| `MaxPlayerCount` | Max simultaneous players | 6 |
| `UserSelectedRegion` | `EU` (covers EU+NA), `SEA`, `CIS`, or blank = auto-pick by latency | auto |
| `UseDirectConnection` / `DirectConnectionServerPort` | Direct IP join | on, port 7777 |

---

## 2. Difficulty presets (the quick knob)

Pick one baseline, then optionally fine-tune individual values below.

| Setting | Easy | Medium (default) | Hard |
|---|---|---|---|
| Enemy health | 0.7× | 1.0× | 1.5× |
| Enemy damage | 0.6× | 1.0× | 1.25× |
| Enemy ship health | 0.7× | 1.0× | 1.5× |
| Enemy ship damage | 0.6× | 1.0× | 1.25× |
| Boarding difficulty | 0.7× | 1.0× | 1.5× |
| Combat difficulty | Easy | Normal | Hard |

---

## 3. Fine-tune knobs (request any of these individually)

From `WorldDescription.json`. Plain-English meaning, default, and allowed range:

| Knob | What it changes | Default | Range |
|---|---|---|---|
| **Enemy Health** | How tanky land enemies are | 1.0 | 0.2 – 5.0 |
| **Enemy Damage** | How hard enemies hit | 1.0 | 0.2 – 5.0 |
| **Enemy Ship Health** | How tanky enemy ships are | 1.0 | 0.4 – 5.0 |
| **Enemy Ship Damage** | How hard enemy ships hit | 1.0 | 0.2 – 2.5 |
| **Boarding Difficulty** | How many enemy sailors you must beat to win a boarding | 1.0 | 0.2 – 5.0 |
| **Combat Difficulty** | Boss difficulty + general enemy aggression | Normal | Easy / Normal / Hard |
| **Co-op Scaling (enemies)** | Auto-scales enemy health/posture to player count | 1.0 | 0.0 – 2.0 |
| **Co-op Scaling (ships)** | Auto-scales enemy ship health to player count | 0.0 | 0.0 – 2.0 |
| **Shared Quests** | One player finishing a co-op quest completes it for everyone who has it active | On | On / Off |
| **Immersive Exploration** | Turns OFF point-of-interest map markers → harder to find things (the "EasyExplore" flag; name is backwards) | Off | On / Off |

### Common requests, translated
- *"Enemies are too tough"* → lower **Enemy Health** / **Enemy Damage** (e.g. 0.7 / 0.6)
- *"We want a brutal run"* → Combat Difficulty **Hard** + Enemy Health/Damage 1.5 / 1.25
- *"Naval fights are too punishing"* → lower **Enemy Ship Damage** (e.g. 0.6)
- *"Boarding takes forever"* → lower **Boarding Difficulty**
- *"Make exploring more hardcore"* → turn **Immersive Exploration** On (removes map markers)

---

*Anything not listed here isn't currently exposed by the dedicated server (Early Access). The game has no in-game admin/console commands yet — all tuning is via these files.*
