# Agentnotater for GemFlight

- Målet er World of Warcraft: Forever. TOC-en bruker `## Interface: 16001`. Klienten er den moderne
  (Mainline-familien) med `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`, ikke Classic. Modern API
  (`C_Timer`, `BackdropTemplate`, `SOUNDKIT`, addon compartment) virker.
- Lokal installasjon hos Håkon:
  `~/.local/share/Steam/steamapps/compatdata/2709027739/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/`.
  `GemFlight` der er en symlink til repoets `GemFlight/`.
- `Core.lua` og `Progression.lua` skal være ren Lua 5.1 uten WoW-globaler. Bruk ikke `math.random`
  der (WoW har ingen `math.randomseed`); brettet har egen Park–Miller-RNG.
- `tests/wow_mock.lua` er streng: ukjente metoder med stor forbokstav og ukjente globaler gir feil.
  Når du tar i bruk et nytt WoW-API, legg det til i mocken bare hvis du vet at det finnes i
  den moderne klienten.
- Kjør `luajit tests/run.lua` og `luajit tests/ui_smoke.lua` før commit. LuaJIT godtar `goto`, men WoW
  gjør det ikke, så addonfilene må holde seg til Lua 5.1.
