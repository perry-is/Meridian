# Balance helper: scale a faction's non-worker unit costs (run from repo root). Usage: python3 tools_rescale.py <faction-file> <mult>
import json, sys
p = 'MeridianCore/Sources/MeridianCore/Data/' + sys.argv[1]
m = float(sys.argv[2])
us = json.load(open(p))
for u in us:
    if u['role'] == 'worker': continue
    for k in ('iron', 'wood', 'gold'):
        u['cost'][k] = int(round(u['cost'][k] * m / 5) * 5)
json.dump(us, open(p, 'w'), indent=1)
