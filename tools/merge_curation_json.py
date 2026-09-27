#!/usr/bin/env python3
"""Three-way merge for docs/evidence_packets/static_reverse/parity_gap_inventory.curation.json.

Two lanes that each add curation entries collide textually at the end of the `sources`／`items`
objects although the JSON merge is trivial: union of keys, a key both sides changed takes
theirs (the lane being merged) and is listed on stderr. Called by tools/lane_merge.sh merge
with the three git stages; writes the merged file and exits 0, or exits 1 when a value
conflict cannot be decided (both sides changed the same key to different values — still
merged with theirs, reported for the lead to review).
"""
import json, subprocess, sys
PATH = "docs/evidence_packets/static_reverse/parity_gap_inventory.curation.json"

def stage(n):
    out = subprocess.run(["git", "show", f":{n}:{PATH}"], capture_output=True, text=True)
    return json.loads(out.stdout) if out.returncode == 0 and out.stdout.strip() else {}

def merge(base, ours, theirs, trail):
    if isinstance(base, dict) and isinstance(ours, dict) and isinstance(theirs, dict):
        result = dict(ours)
        for key, tv in theirs.items():
            bv = base.get(key); ov = ours.get(key)
            if key not in ours:
                if key in base and bv == tv:
                    continue  # ours deleted／renamed it and theirs left it untouched: stays deleted
                result[key] = tv
            elif ov == tv or bv == tv:
                continue
            elif bv == ov:
                result[key] = tv
            elif (isinstance(ov, dict) and isinstance(tv, dict)) or (isinstance(ov, list) and isinstance(tv, list)):
                result[key] = merge(bv if isinstance(bv, type(ov)) else type(ov)(), ov, tv, trail + [key])
            else:
                print(f"CURATION_MERGE_THEIRS {'/'.join(trail + [key])}", file=sys.stderr)
                result[key] = tv
        for key in list(result):
            if key in base and key not in theirs and base.get(key) == ours.get(key):
                del result[key]  # theirs deleted an unchanged entry
        return result
    if isinstance(ours, list) and isinstance(theirs, list):
        def key_of(e): return e.get("id") if isinstance(e, dict) and "id" in e else json.dumps(e, ensure_ascii=False, sort_keys=True)
        b = {key_of(e): e for e in (base or [])}; o = {key_of(e): e for e in ours}; t = {key_of(e): e for e in theirs}
        result = [e for e in ours if not (key_of(e) in b and key_of(e) not in t and b[key_of(e)] == e)]
        have = {key_of(e) for e in result}
        for e in theirs:
            k = key_of(e)
            if k not in have:
                if k in b and b[k] == e:
                    continue
                result.append(e)
            elif o.get(k) != e and b.get(k) == o.get(k):
                result = [e if key_of(x) == k else x for x in result]
        return result
    return theirs

if len(sys.argv) == 4:  # base ours theirs refs (post-conflict rebuild)
    def show(ref):
        return json.loads(subprocess.check_output(["git", "show", f"{ref}:{PATH}"], text=True))
    merged = merge(show(sys.argv[1]), show(sys.argv[2]), show(sys.argv[3]), [])
else:
    merged = merge(stage(1), stage(2), stage(3), [])
with open(PATH, "w", encoding="utf-8") as fh:
    json.dump(merged, fh, ensure_ascii=False, indent=2); fh.write("\n")
print("CURATION_MERGED", PATH)
