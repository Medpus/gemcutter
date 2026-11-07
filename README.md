# Gemcutter

Et avslappet match-3-spill for World of Warcraft: Forever, laget for lange flight paths. Du åpner
brettet fra minimap-knappen, bytter steiner til du lander og lukker det igjen. Brettet lagres, så du
fortsetter der du slapp på neste flytur. Alt du spiller gir XP til en kontobred progresjon.

## Installering

Addonet ligger i `Gemcutter/`. Kopier eller symlink mappen til Forever-installasjonen:

```sh
ln -s "$PWD/Gemcutter" ".../World of Warcraft/_forever_/Interface/AddOns/Gemcutter"
```

Start spillet på nytt eller skriv `/reload` hvis du allerede er inne.

## Bruk

- Klikk på minimap-knappen (blå safir) eller i addon-menyen ved minimap for å åpne og lukke brettet.
- Bytt to steiner ved å dra en stein mot naboen, eller klikke på begge.
- Esc lukker vinduet. Vinduet lukkes også når du går i kamp eller får en ready check.
- Etter åtte sekunder uten trekk pulserer et mulig trekk.

Kommandoer: `/gemcutter` (eller `/gc`) åpner og lukker brettet.

| Kommando | Virkning |
|---|---|
| `/gemcutter minimap` | skjuler eller viser minimap-knappen |
| `/gemcutter scale 0.5-2` | endrer størrelsen på vinduet |
| `/gemcutter sound` | slår lyd av eller på |
| `/gemcutter reset` | sletter all progresjon (spør først) |

## Regler

Tre eller flere like på rad eller i kolonne forsvinner. Nye steiner faller ned, og hver kaskade gir
høyere multiplikator. Spesialsteiner:

- Fire på rad lager en ladet stein som tømmer hele raden eller kolonnen når den forsvinner.
- L-, T- eller kryssform lager en ustabil stein som sprenger 3x3 rundt seg.
- Fem på rad lager et prisme. Bytt det med en stein, så forsvinner alle steiner med den fargen.
  To prismer tømmer hele brettet.

Spillet tar aldri slutt. Er det ingen trekk igjen, stokkes brettet. «New board» starter et nytt brett
og nullstiller bare brettpoengene.

## Progresjon

Progresjonen gjelder hele kontoen, ikke én karakter. Hvert trekk gir XP etter poengsum. Nivå 1–60
gir en ny rangtittel hvert tiende nivå, fra Novice Gemcutter til Grand Master Gemcutter. 18
achievements gir ekstra XP, og fremdriftspanelet viser statistikk som beste trekk, lengste kjede og
antall flyturer du har spilt på. En simulering anslår nivå 10 etter rundt en halvtime og nivå 60
etter rundt 16 timers spill.

## Utvikling

Spillogikken (`Core.lua`, `Progression.lua`) er ren Lua 5.1 uten WoW-API og testes direkte.
`tests/ui_smoke.lua` laster hele addonet mot en streng mock av WoW-API-et og spiller 400 trekk med
musehendelser og animasjoner.

```sh
luajit tests/run.lua
luajit tests/ui_smoke.lua
```

Ikke laget ennå: Blitz-modus med tidsfrist, daglig utfordring med samme brett for alle, alternative
steinsett, valgfri automatisk åpning ved flight path og poengtavle for venner og guild.

Alle steiner er spillets egne item-ikoner, og lydene er spillets egne SOUNDKIT-lyder. Addonet har
ingen egen grafikk eller lyd.
