#!/usr/bin/env bash
# Henter de samme bibliotekene som .pkgmeta tar med i release-zipen, til lokal utvikling.
set -euo pipefail
cd "$(dirname "$0")/.."
libs=Gemcutter/Libs
cf=https://repos.curseforge.com/wow
fetch() { mkdir -p "$(dirname "$2")"; curl -fsSL --max-time 60 -o "$2" "$1"; }
fetch "$cf/libstub/trunk/LibStub.lua" "$libs/LibStub/LibStub.lua"
fetch "$cf/callbackhandler/trunk/CallbackHandler-1.0/CallbackHandler-1.0.lua" "$libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"
fetch "$cf/callbackhandler/trunk/CallbackHandler-1.0/CallbackHandler-1.0.xml" "$libs/CallbackHandler-1.0/CallbackHandler-1.0.xml"
fetch "https://raw.githubusercontent.com/tekkub/libdatabroker-1-1/master/LibDataBroker-1.1.lua" "$libs/LibDataBroker-1.1/LibDataBroker-1.1.lua"
fetch "$cf/libdbicon-1-0/trunk/LibDBIcon-1.0/LibDBIcon-1.0.lua" "$libs/LibDBIcon-1.0/LibDBIcon-1.0.lua"
fetch "$cf/libdbicon-1-0/trunk/LibDBIcon-1.0/lib.xml" "$libs/LibDBIcon-1.0/lib.xml"
echo "Libs hentet til $libs"
