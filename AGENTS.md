# Agentnotater for Gemcutter

- Målet er World of Warcraft: Forever. TOC-en bruker `## Interface: 16001`. Klienten er den moderne
  (Mainline-familien) med `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`, ikke Classic. Modern API
  (`C_Timer`, `BackdropTemplate`, `SOUNDKIT`, addon compartment) virker.
- Lokal installasjon hos Håkon:
  `~/.local/share/Steam/steamapps/compatdata/2709027739/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/`.
  `Gemcutter` der er en symlink til repoets `Gemcutter/`.
- `Core.lua` og `Progression.lua` skal være ren Lua 5.1 uten WoW-globaler. Bruk ikke `math.random`
  der (WoW har ingen `math.randomseed`); brettet har egen Park–Miller-RNG.
- `tests/wow_mock.lua` er streng: ukjente metoder med stor forbokstav og ukjente globaler gir feil.
  Når du tar i bruk et nytt WoW-API, legg det til i mocken bare hvis du vet at det finnes i
  den moderne klienten.
- Kjør `scripts/check.sh` før commit og før release (tester, parse-sjekk og goto-sjekk). LuaJIT
  godtar `goto`, men WoW gjør det ikke, så addonfilene må holde seg til Lua 5.1.
- Hold GitHub Actions-bruken minimal. Alt som kan kjøres lokalt, kjøres lokalt. Den eneste
  workflowen er release ved `v*`-tagg, fordi pakking med externals og opplasting med secrets må
  skje der. Ikke legg til CI ved hver push, Dependabot eller tester i release-jobben.
- Bibliotekene (LibStub, CallbackHandler, LibDataBroker, LibDBIcon) er ikke i git. `.pkgmeta`
  henter dem som externals ved release; `scripts/fetch-libs.sh` henter de samme filene lokalt.
  Røyktesten bruker `tests/fake_libs.lua` i stedet for de ekte bibliotekene.
- Minimapknappen må gå via LibDBIcon. Leatrix Plus og andre knappesamlere avviser egne knapper.
- Ikonet er en kuttet rubin i flate fasetter, tegnet i `assets/icon.svg`. `scripts/make-icon.sh` lager
  CurseForge-logoen (med bakgrunn) og spillikonet (uten `bg` og `cutline`, gjennomsiktig). TGA-en
  skrives for hånd, fordi ImageMagick setter bunn-origo i headeren men skriver radene ovenfra.
  Unngå glans-ellipser, gnister og rutenett av steiner; det så AI-generert ut.
- Release: legg til `## vX.Y.Z` i `CHANGELOG.md`, push taggen `vX.Y.Z`. GitHub Actions kjører
  BigWigs-packageren, som gjenkjenner `16001` som Forever. CurseForge-opplasting krever
  `## X-Curse-Project-ID` i TOC-en og secret `CF_API_KEY`. Packageren er låst til en commit-SHA
  fordi den får CurseForge-nøkkelen; oppdater låsen for hånd ved behov.
- Packageren skriver zip-filen til den skjulte mappen `.release/`. Skal den lastes opp som
  artefakt, trenger `upload-artifact` `include-hidden-files: true`.
