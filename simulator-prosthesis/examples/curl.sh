#!/usr/bin/env sh
# Ejemplos con curl / curl examples.  BASE=http://192.168.1.50:8000 ./curl.sh
BASE="${BASE:-http://localhost:8000}"

post() { curl -sS -X POST "$BASE$1" -H 'Content-Type: application/json' -d "$2" -w '  [HTTP %{http_code}]\n'; }

post /api/command '{"command": "C"}'          ; sleep 1   # cierra la mano / closes the hand
post /api/command '{"command": "O"}'          ; sleep 1   # abre / opens
post /api/command '{"command": "A320,D180"}'  ; sleep 1   # meñique e índice / little and index
post /api/command '{"command": "C400"}'       ; sleep 1   # dedo medio a 400 / middle finger to 400
post /api/command '{"command": "A900"}'                   # 422 range/OUT_OF_RANGE
post /api/command '{"command": "S,A320"}'                 # 422 exclusivity/EXCLUSIVE_COMMAND
post /api/profile '{"profile": "INTERSECTION"}'           # no mueve la mano / does not move the hand
post /api/profile '{"profile": "TABLE_5_V3"}'
curl -sS "$BASE/api/state"; echo
