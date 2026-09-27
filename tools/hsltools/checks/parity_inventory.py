"""Parity gap inventory: every known difference between the original and the remake, in one list.

Lane R7-INV. The differences were scattered over module provenance headers, evidence packets,
the mechanics matrix and the R6-V2 recording reconciliation; this task gathers them from those
sources, joins them to a curated classification, and renders one ranked inventory.

  sources (measured from tracked files on every check)
    provenance  every `remake-invented` or `provisional` term of a game/**/*.gd `## provenance:`
                header, all five dimensions (parsed by hsltools.checks.provenance);
                key `provenance:<module>|<dimension>|<tag>|<path>` (path empty when the term names none)
    sentence    every evidence-packet sentence (or table cell) that says the original was not
                read / restored / recreated — GAP_PHRASES; key `sentence:<packet>#<sha1 of the
                normalised text, 10 hex>`; the packet header line and this task's own outputs excluded.
                Advisory: the inventory renders the classified sentences of the curation file (text
                from there), so rewording a packet sentence never fails the check (see below)
    scope       every `provisional` / `negative-evidence` tier of an evidence-packet header line
                (hsltools.evidence.index); key `scope:<packet>|<tier>|<scope>` (scope empty when unscoped)
    matrix      every row of docs/MECHANICS_EVIDENCE_MATRIX.md's mechanic table; key `matrix:<Mechanic>`
    video       the 13 classes of lane R6-V2's recording reconciliation (report §6, kept outside the
                repository, so the class list itself lives in the curation file); key `video:<N>`
  curated     docs/evidence_packets/static_reverse/parity_gap_inventory.curation.json
                items    one entry per player-visible (or deliberately invisible) difference: id,
                         difference, original + original_evidence (paths), remake + remake_code
                         (`path` or `path:function`, the function must be defined there),
                         original_status, visibility, effort, category, optional in_progress / decision
                sources  every live source key -> {"item": id or [ids]} | {"no_visible_effect": reason} |
                         {"resolved": where it was closed}; sentence entries also carry "text",
                         whose hash must equal the key's
  rendered    parity_gap_inventory.md (ranked top 20, counts, full list by category) and
              parity_gap_inventory.json (every item with its sources, every non-item disposition)

check fails when a provenance / scope / matrix / video source has no classification (a new
remake-invented header term, a new matrix row ...), when such a classification names a source that
no longer exists, when an item is malformed or unreferenced, or when the rendered files are stale.
Sentence sources only warn (PARITY_INVENTORY_WARN lines, `sentence_unclassified=` /
`sentence_gone=` on the PASS line): a new「未读」sentence nobody classified, or a classified
sentence that was reworded or deleted. `generate` drops the gone sentence classifications from the
curation file (keeping one that is an item's last reference, which stays a warning), so the
lead's `tools/lane_merge.sh merge` cleans them up; lanes do not hand-edit the curation for a
rewording (09-25 audit: 13 of 88 non-merge commits touched the curation, the item total stayed
107 -> 107). `PYTHONPATH=tools python3 -m hsltools.checks.parity_inventory --stubs` prints
ready-to-edit curation entries for every unclassified live source, sentences included.

Declared inputs: game/ (the headers are read from there), not docs/PROVENANCE.md, which is only
re-rendered at merge time and may lag behind the headers.
PASS line: PARITY_INVENTORY_PASS items=N sources=M unclassified=0 provenance=… layout_timing_modules=… …
[sentence_unclassified=… sentence_gone=…]
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

from hsltools.checks.provenance import DIMENSIONS, load_modules
from hsltools.data import json_bytes
from hsltools.evidence.index import HEADER_PREFIX, load_packets, packet_paths
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask

PACKET_DIR = Path("docs") / "evidence_packets" / "static_reverse"
CURATION = PACKET_DIR / "parity_gap_inventory.curation.json"
OUTPUT_DOC = PACKET_DIR / "parity_gap_inventory.md"
OUTPUT_JSON = PACKET_DIR / "parity_gap_inventory.json"
MATRIX = Path("docs") / "MECHANICS_EVIDENCE_MATRIX.md"
SCHEMA = "hsl_parity_gap_inventory.v1"

PROVENANCE_TAGS = ("remake-invented", "provisional")
SCOPE_TIERS = ("provisional", "negative-evidence")
GAP_PHRASES = re.compile(r"未复原|未还原|未复刻|未重制|未读|重制未做")
VIDEO_CLASSES = tuple(range(1, 14))
KINDS = ("provenance", "sentence", "scope", "matrix", "video")

ORIGINAL_STATUS = {
    "read_complete": "已读完只差照做",
    "read_partial": "读了一部分",
    "unread": "未读",
    "no_original_code": "原版无对应代码",
}
VISIBILITY = {
    "every_battle": "每场都看得到",
    "some_levels": "部分关卡",
    "rare": "少见",
    "invisible": "看不见",
}
EFFORT = ("S", "M", "L")
IN_PROGRESS_LANES = ("R7-TITLE", "R7-AI51", "R7-CAM")
DISPOSITIONS = ("item", "no_visible_effect", "resolved")
ITEM_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
ITEM_FIELDS = ("id", "difference", "original", "original_evidence", "remake", "remake_code",
               "original_status", "visibility", "effort", "category")
OPTIONAL_ITEM_FIELDS = ("in_progress", "decision")

# Ranking of the top list: visibility x "only needs doing" (read_complete first).
VISIBILITY_WEIGHT = {"every_battle": 4, "some_levels": 3, "rare": 2, "invisible": 1}
STATUS_WEIGHT = {"read_complete": 3, "read_partial": 2, "no_original_code": 2, "unread": 1}
EFFORT_ORDER = {"S": 0, "M": 1, "L": 2}
TOP_COUNT = 20


# --- sources -------------------------------------------------------------------------------

def _normalise(text: str) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"^(?:[-*>] |\d+\. )+", "", text).strip()
    return text


def sentence_hash(text: str) -> str:
    return hashlib.sha1(_normalise(text).encode("utf-8")).hexdigest()[:10]


def _sentences(line: str) -> list[str]:
    """A line split into cells (table rows) and then sentences, each normalised."""
    stripped = line.strip()
    cells = [cell for cell in stripped.strip("|").split("|")] if stripped.startswith("|") else [stripped]
    parts: list[str] = []
    for cell in cells:
        parts.extend(re.split(r"(?<=[。；！？])", cell))
    return [text for text in (_normalise(part) for part in parts) if text]


def provenance_sources(root: Path) -> dict[str, dict]:
    modules, missing, invalid = load_modules(root)
    if missing or invalid:
        raise CheckFailed("PARITY_INVENTORY_FAIL provenance headers invalid — run `hsl check provenance`\n"
                          + "\n".join(missing + invalid))
    sources: dict[str, dict] = {}
    for module in modules:
        for dimension in DIMENSIONS:
            for term in module["dimensions"][dimension]:
                if term["tag"] not in PROVENANCE_TAGS:
                    continue
                key = f"provenance:{module['path']}|{dimension}|{term['tag']}|{term['path'] or ''}"
                sources[key] = {"kind": "provenance", "module": module["path"], "dimension": dimension,
                                "tag": term["tag"], "note": term["note"] or ""}
    return sources


def sentence_sources(root: Path) -> dict[str, dict]:
    sources: dict[str, dict] = {}
    own = {OUTPUT_DOC.as_posix()}
    for path in packet_paths(root):
        if path.as_posix() in own:
            continue
        in_code = False
        for line in (root / path).read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith("```"):
                in_code = not in_code
                continue
            if in_code or line.startswith(HEADER_PREFIX):
                continue
            for text in _sentences(line):
                if GAP_PHRASES.search(text):
                    key = f"sentence:{path.as_posix()}#{sentence_hash(text)}"
                    sources.setdefault(key, {"kind": "sentence", "packet": path.as_posix(), "text": text})
    return sources


def scope_sources(root: Path) -> dict[str, dict]:
    packets, errors = load_packets(root)
    if errors:
        raise CheckFailed("PARITY_INVENTORY_FAIL evidence packet headers invalid — run `hsl check evidence_index`\n"
                          + "\n".join(errors))
    sources: dict[str, dict] = {}
    for packet in packets:
        if packet["path"] == OUTPUT_DOC.as_posix():
            continue
        for term in packet["evidence"]:
            if term["tier"] in SCOPE_TIERS:
                key = f"scope:{packet['path']}|{term['tier']}|{term['scope'] or ''}"
                sources[key] = {"kind": "scope", "packet": packet["path"], "tier": term["tier"], "scope": term["scope"] or ""}
    return sources


def matrix_sources(root: Path) -> dict[str, dict]:
    lines = (root / MATRIX).read_text(encoding="utf-8").splitlines()
    header = next((index for index, line in enumerate(lines) if line.startswith("| Mechanic |")), None)
    if header is None:
        raise CheckFailed(f"PARITY_INVENTORY_FAIL {MATRIX.as_posix()}: no '| Mechanic |' table")
    sources: dict[str, dict] = {}
    for line in lines[header + 2:]:
        if not line.startswith("|"):
            break
        mechanic = line.strip().strip("|").split("|")[0].strip()
        key = f"matrix:{mechanic}"
        if key in sources:
            raise CheckFailed(f"PARITY_INVENTORY_FAIL {MATRIX.as_posix()}: mechanic {mechanic!r} appears twice")
        sources[key] = {"kind": "matrix", "mechanic": mechanic}
    return sources


def video_sources(curation: dict) -> dict[str, dict]:
    classes = curation.get("video_diff_classes")
    if not isinstance(classes, dict) or sorted(int(number) for number in classes) != list(VIDEO_CLASSES):
        raise CheckFailed(f"PARITY_INVENTORY_FAIL {CURATION.as_posix()}: video_diff_classes must hold exactly the R6-V2 classes 1..13")
    return {f"video:{int(number)}": {"kind": "video", "class": int(number), "title": entry["title"]}
            for number, entry in sorted(classes.items(), key=lambda pair: int(pair[0]))}


def curated_sentence_sources(curation: dict) -> dict[str, dict]:
    """The sentence sources the curation file classifies, text taken from there (not re-read from the packets)."""
    table = curation.get("sources")
    if not isinstance(table, dict):
        return {}
    return {key: {"kind": "sentence", "packet": key[len("sentence:"):].rpartition("#")[0], "text": entry.get("text", "")}
            for key, entry in table.items() if key.startswith("sentence:") and isinstance(entry, dict)}


def strict_sources(root: Path, curation: dict) -> dict[str, dict]:
    sources: dict[str, dict] = {}
    for part in (provenance_sources(root), scope_sources(root), matrix_sources(root), video_sources(curation)):
        sources.update(part)
    return sources


def live_sources(root: Path, curation: dict) -> dict[str, dict]:
    """The sources the inventory is built from: provenance / scope / matrix / video measured from the
    repository, sentences as classified in the curation file (sentence_warnings compares them with the packets)."""
    return {**strict_sources(root, curation), **curated_sentence_sources(curation)}


def sentence_drift(root: Path, curation: dict) -> tuple[dict[str, dict], list[str], list[str]]:
    """(packet sentences, unclassified packet sentence keys, classified sentence keys no longer in any packet)."""
    packet = sentence_sources(root)
    curated = curated_sentence_sources(curation)
    return packet, sorted(key for key in packet if key not in curated), sorted(key for key in curated if key not in packet)


def prune_gone_sentences(root: Path) -> tuple[list[str], list[str]]:
    """Drop the classifications of sentences no longer in any packet from the curation file.
    (dropped keys, kept keys: an item's last reference stays, so the item never goes unreferenced)."""
    curation = load_curation(root)
    _, _, gone = sentence_drift(root, curation)
    if not gone:
        return [], []
    table = curation["sources"]
    references = Counter(target for entry in table.values() if isinstance(entry, dict) for target in item_targets(entry))
    dropped: list[str] = []
    kept: list[str] = []
    for key in gone:
        targets = item_targets(table[key])
        if any(references[target] <= 1 for target in targets):
            kept.append(key)
            continue
        references.subtract(targets)
        del table[key]
        dropped.append(key)
    if dropped:
        (root / CURATION).write_bytes(json_bytes(curation))
    return dropped, kept


def source_location(key: str, source: dict) -> str:
    """The repository file a source lives in (for links); video classes have none."""
    return {"provenance": source.get("module"), "sentence": source.get("packet"), "scope": source.get("packet"),
            "matrix": MATRIX.as_posix()}.get(source["kind"]) or ""


# --- curation ------------------------------------------------------------------------------

def load_curation(root: Path) -> dict:
    try:
        return json.loads((root / CURATION).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise CheckFailed(f"PARITY_INVENTORY_FAIL {CURATION.as_posix()}: {error}") from error


def _code_ref_error(root: Path, ref: str) -> str | None:
    path, _, function = ref.partition(":")
    target = root / path
    if not path or not target.is_file():
        return f"remake_code {ref!r}: file does not exist"
    if function:
        text = target.read_text(encoding="utf-8")
        if not re.search(rf"^\s*(?:static\s+)?(?:func|def|class)\s+{re.escape(function)}\b", text, re.M):
            return f"remake_code {ref!r}: {function!r} is not defined in {path}"
    return None


def validate_items(root: Path, curation: dict) -> tuple[list[dict], list[str]]:
    errors: list[str] = []
    items = curation.get("items")
    if not isinstance(items, list) or not items:
        return [], ["items must be a non-empty list"]
    seen: set[str] = set()
    for item in items:
        label = item.get("id", "?")
        unknown = set(item) - set(ITEM_FIELDS) - set(OPTIONAL_ITEM_FIELDS)
        if unknown:
            errors.append(f"item {label}: unknown field(s) {', '.join(sorted(unknown))}")
        missing = [field for field in ITEM_FIELDS if field not in item or item[field] in ("", None)]
        if missing:
            errors.append(f"item {label}: missing {', '.join(missing)}")
            continue
        if not ITEM_ID.match(item["id"]):
            errors.append(f"item {label}: id must be lowercase words joined by '-'")
        if item["id"] in seen:
            errors.append(f"item {label}: duplicate id")
        seen.add(item["id"])
        if item["original_status"] not in ORIGINAL_STATUS:
            errors.append(f"item {label}: original_status {item['original_status']!r} not in {', '.join(ORIGINAL_STATUS)}")
        if item["visibility"] not in VISIBILITY:
            errors.append(f"item {label}: visibility {item['visibility']!r} not in {', '.join(VISIBILITY)}")
        if item["effort"] not in EFFORT:
            errors.append(f"item {label}: effort {item['effort']!r} not in {', '.join(EFFORT)}")
        if item.get("in_progress") not in (None, *IN_PROGRESS_LANES):
            errors.append(f"item {label}: in_progress {item['in_progress']!r} not in {', '.join(IN_PROGRESS_LANES)}")
        for field in ("original_evidence", "remake_code"):
            if not isinstance(item[field], list) or not item[field]:
                errors.append(f"item {label}: {field} must be a non-empty list")
        for path in item.get("original_evidence") or []:
            if not (root / path.partition("#")[0]).exists():
                errors.append(f"item {label}: original_evidence {path!r} does not exist")
        for ref in item.get("remake_code") or []:
            error = _code_ref_error(root, ref)
            if error:
                errors.append(f"item {label}: {error}")
    return items, errors


def item_targets(entry: dict) -> list:
    """The item ids a classification names: "item" is one id or a list (one note covering several differences)."""
    value = entry.get("item")
    if value is None:
        return []
    return list(value) if isinstance(value, list) else [value]


def classify(root: Path, curation: dict, sources: dict[str, dict], items: list[dict]) -> tuple[dict[str, dict], list[str], list[str]]:
    """(classification by key, unclassified keys, other errors)."""
    table = curation.get("sources")
    if not isinstance(table, dict):
        return {}, sorted(sources), ["sources must be an object"]
    item_ids = {item["id"] for item in items}
    errors: list[str] = []
    unclassified = sorted(key for key in sources if key not in table)
    orphans = sorted(key for key in table if key not in sources)
    for key in orphans:
        errors.append(f"classification for a source that no longer exists: {key}")
    for key, entry in table.items():
        if key not in sources:
            continue
        chosen = [name for name in DISPOSITIONS if name in entry]
        if len(chosen) != 1 or set(entry) - set(DISPOSITIONS) - {"text"}:
            errors.append(f"{key}: must hold exactly one of {', '.join(DISPOSITIONS)} (plus 'text' for sentences)")
            continue
        value = entry[chosen[0]]
        if chosen[0] == "item":
            targets = item_targets(entry)
            if not targets or any(not isinstance(target, str) for target in targets) or len(set(targets)) != len(targets):
                errors.append(f"{key}: item must be an id or a non-empty list of distinct ids")
            else:
                errors += [f"{key}: item {target!r} is not defined" for target in targets if target not in item_ids]
        elif not isinstance(value, str) or not value.strip():
            errors.append(f"{key}: {chosen[0]} must be a non-empty string")
        if sources[key]["kind"] == "sentence":
            if "text" not in entry or sentence_hash(entry["text"]) != key.rpartition("#")[2]:
                errors.append(f"{key}: 'text' must be the sentence whose hash the key carries")
        elif "text" in entry:
            errors.append(f"{key}: only sentence sources carry 'text'")
    referenced = {target for key, entry in table.items() if key in sources for target in item_targets(entry)}
    for item in items:
        if item["id"] not in referenced:
            errors.append(f"item {item['id']}: no source classifies into it")
    return table, unclassified, errors


def stub(key: str, source: dict) -> dict:
    entry: dict = {"item": "<item id>  (or \"no_visible_effect\": \"<reason>\", or \"resolved\": \"<where>\")"}
    if source["kind"] == "sentence":
        entry["text"] = source["text"]
    return entry


# --- rendering -----------------------------------------------------------------------------

def rank(items: list[dict]) -> list[dict]:
    return sorted(items, key=lambda item: (-VISIBILITY_WEIGHT[item["visibility"]] * STATUS_WEIGHT[item["original_status"]],
                                           -VISIBILITY_WEIGHT[item["visibility"]], EFFORT_ORDER[item["effort"]], item["id"]))


def _cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ").strip() or "—"


def _link(path: str) -> str:
    target, _, anchor = path.partition("#")
    name = Path(target).name
    if name in ("README.md", "manifest.json"):
        name = Path(target).parent.name + "/" + name
    relative = Path("../../..") / target
    return f"[{name}]({relative.as_posix()})" + (f" `#{anchor}`" if anchor else "")


def _code(ref: str) -> str:
    path, _, function = ref.partition(":")
    return _link(path) + (f" `{function}`" if function else "")


def _counter_rows(counter: Counter, labels: dict[str, str]) -> list[str]:
    return [f"| {labels[key]} | {counter.get(key, 0)} |" for key in labels]


def render(curation: dict, sources: dict[str, dict], table: dict[str, dict], items: list[dict]) -> tuple[str, dict]:
    by_item: dict[str, list[str]] = {item["id"]: [] for item in items}
    dispositions: dict[str, list[dict]] = {"no_visible_effect": [], "resolved": []}
    for key in sorted(sources):
        entry = table[key]
        if "item" in entry:
            for target in item_targets(entry):
                by_item[target].append(key)
        else:
            name = "no_visible_effect" if "no_visible_effect" in entry else "resolved"
            dispositions[name].append({"source": key, "reason": entry[name]})
    kind_counts = Counter(source["kind"] for source in sources.values())
    layout_timing = {source["module"] for source in sources.values()
                     if source["kind"] == "provenance" and source["dimension"] in ("layout", "timing")}
    status_counts = Counter(item["original_status"] for item in items)
    visibility_counts = Counter(item["visibility"] for item in items)
    category_counts = Counter(item["category"] for item in items)
    ranked = rank(items)
    counts = {
        "items": len(items),
        "sources": len(sources),
        "sources_by_kind": {kind: kind_counts.get(kind, 0) for kind in KINDS},
        "layout_timing_modules": len(layout_timing),
        "items_by_original_status": {key: status_counts.get(key, 0) for key in ORIGINAL_STATUS},
        "items_by_visibility": {key: visibility_counts.get(key, 0) for key in VISIBILITY},
        "items_by_category": dict(sorted(category_counts.items())),
        "in_progress": sum(1 for item in items if item.get("in_progress")),
        "no_visible_effect_sources": len(dispositions["no_visible_effect"]),
        "resolved_sources": len(dispositions["resolved"]),
    }
    data = {
        "schema": SCHEMA,
        "updated": curation["updated"],
        "generated_by": "python3 tools/hsl.py generate parity_inventory",
        "counts": counts,
        "top": [item["id"] for item in ranked[:TOP_COUNT]],
        "items": [{**{field: item[field] for field in ITEM_FIELDS + OPTIONAL_ITEM_FIELDS if field in item},
                   "sources": by_item[item["id"]]} for item in ranked],
        "video_diff_classes": {str(number): curation["video_diff_classes"][str(number)] for number in VIDEO_CLASSES},
        "dispositions": dispositions,
    }
    lines = [
        "# 原版与重制差异总清单（parity gap inventory）",
        "",
        f"> evidence: provisional: 归类、可见度与工作量是人工判断，原版证据在每条的链接里 · status: record-only · "
        f"tools: hsltools/checks/parity_inventory.py · updated: {curation['updated']}",
        "",
        "本页由 `python3 tools/hsl.py generate parity_inventory` 生成（lane R7-INV），全量数据在同名 "
        "[parity_gap_inventory.json](parity_gap_inventory.json)，人工归类在 "
        "[parity_gap_inventory.curation.json](parity_gap_inventory.curation.json)。汇报\"还剩多少\"按本页的总数。",
        "",
        "来源（每次 `hsl check parity_inventory` 重新从仓库量出）：game/ 模块 `## provenance:` 头里的每个 "
        "`remake-invented`／`provisional` 片段（五个维度）；证据包里写\"未读／未复原／未还原／未复刻／未重制\"的句子；"
        "证据包头的每个 `provisional`／`negative-evidence` 范围；[机制矩阵](../../MECHANICS_EVIDENCE_MATRIX.md) 每一行；"
        "R6-V2 录屏对账的 13 类差异（报告在仓库外 `ignored/lane-reports/R6-V2.md` §6，类目录存在归类文件里）。"
        "除句子外，新出现的来源没有归类（归进某一条、或写 `no_visible_effect` 理由、或写 `resolved` 出处）检查就失败；"
        "句子只提示：本页按归类文件里已归类的句子渲染，证据包改写或删掉句子时检查只打 `PARITY_INVENTORY_WARN`，"
        "`generate`（负责人 `tools/lane_merge.sh merge` 时）自动删掉已不存在的句子归类；"
        "`PYTHONPATH=tools python3 -m hsltools.checks.parity_inventory --stubs` 打印待填的条目。",
        "",
        "本页只说\"哪里不一样\"和\"原版读到哪一步\"，不升级任何证据等级；原版等价仍以各条链接的证据包为准。",
        "",
        "## 总数",
        "",
        f"共 **{len(items)}** 条差异（其中 {counts['in_progress']} 条本轮有 lane 进行中），来自 {len(sources)} 个来源条目："
        + "、".join(f"{kind} {kind_counts.get(kind, 0)}" for kind in KINDS)
        + f"；layout／timing 含 remake-invented／provisional 的模块 {len(layout_timing)} 个全部归类。"
        f"另有 {counts['no_visible_effect_sources']} 个来源判为玩家看不到、{counts['resolved_sources']} 个已做掉（句子是旧状态）。",
        "",
        "| 原版状态 | 条数 |",
        "| --- | --- |",
        *_counter_rows(status_counts, ORIGINAL_STATUS),
        "",
        "| 可见度 | 条数 |",
        "| --- | --- |",
        *_counter_rows(visibility_counts, VISIBILITY),
        "",
        "| 建议归入的类 | 条数 |",
        "| --- | --- |",
        *[f"| {category} | {count} |" for category, count in sorted(category_counts.items(), key=lambda pair: (-pair[1], pair[0]))],
        "",
        f"## 前 {TOP_COUNT} 条（按可见度 × 只差照做排序）",
        "",
        "排序：可见度（每场 4／部分关卡 3／少见 2／看不见 1）乘原版状态（已读完只差照做 3／读了一部分或原版无对应代码 2／未读 1），"
        "同分先可见度高、再工作量小。",
        "",
        "| # | 玩家看到的差异 | 原版状态 | 可见度 | 量 | 类 | 备注 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, item in enumerate(ranked[:TOP_COUNT], 1):
        remark = "；".join(part for part in (f"{item['in_progress']} 进行中" if item.get("in_progress") else "",
                                             item.get("decision", "")) if part)
        lines.append(f"| {index} | {_cell(item['difference'])} （`{item['id']}`） | {ORIGINAL_STATUS[item['original_status']]} | "
                     f"{VISIBILITY[item['visibility']]} | {item['effort']} | {_cell(item['category'])} | {_cell(remark)} |")
    lines += ["", "## 全量（按类）", ""]
    for category in sorted(category_counts, key=lambda name: (-category_counts[name], name)):
        rows = [item for item in ranked if item["category"] == category]
        lines += [f"### {category}（{len(rows)}）", "",
                  "| id | 玩家看到的差异 | 原版怎样 | 重制怎样 | 原版状态 | 可见度 | 量 | 来源 |",
                  "| --- | --- | --- | --- | --- | --- | --- | --- |"]
        for item in rows:
            original = _cell(item["original"]) + "<br>" + "、".join(_link(path) for path in item["original_evidence"])
            remake = _cell(item["remake"]) + "<br>" + "、".join(_code(ref) for ref in item["remake_code"])
            extra = []
            if item.get("in_progress"):
                extra.append(f"**{item['in_progress']} 进行中**")
            if item.get("decision"):
                extra.append(f"待定：{_cell(item['decision'])}")
            kinds = Counter(sources[key]["kind"] for key in by_item[item["id"]])
            source_text = "、".join(f"{kind} {kinds[kind]}" for kind in KINDS if kinds.get(kind))
            difference = _cell(item["difference"]) + ("<br>" + "；".join(extra) if extra else "")
            lines.append(f"| `{item['id']}` | {difference} | {original} | {remake} | {ORIGINAL_STATUS[item['original_status']]} | "
                         f"{VISIBILITY[item['visibility']]} | {item['effort']} | {source_text} |")
        lines.append("")
    lines += ["## R6-V2 录屏对账 13 类的去向", "",
              "| 类 | 名称 | 现状 | 去向 |", "| --- | --- | --- | --- |"]
    for number in VIDEO_CLASSES:
        entry = table[f"video:{number}"]
        target = "、".join(f"`{target}`" for target in item_targets(entry)) if "item" in entry else ("看不见：" + entry["no_visible_effect"] if "no_visible_effect" in entry else "已做掉：" + entry["resolved"])
        entry_class = curation["video_diff_classes"][str(number)]
        lines.append(f"| {number} | {_cell(entry_class['title'])} | {_cell(entry_class.get('summary', ''))} | {_cell(target)} |")
    lines += ["", "## 已做掉的来源（句子或类目仍写着旧状态）", "",
              "| 来源 | 出处 |", "| --- | --- |"]
    for entry in dispositions["resolved"]:
        lines.append(f"| `{_cell(entry['source'])}` | {_cell(entry['reason'])} |")
    lines += ["", f"玩家看不到的来源 {len(dispositions['no_visible_effect'])} 个（重制内部结构、原版调度顺序等），"
              "理由逐条在 JSON 的 `dispositions.no_visible_effect`。", ""]
    return "\n".join(lines), data


# --- task ----------------------------------------------------------------------------------

def sentence_warnings(root: Path, curation: dict) -> tuple[list[str], dict]:
    """Advisory lines for sentence drift and their counts (empty when the packets match the curation)."""
    packet, unclassified, gone = sentence_drift(root, curation)
    lines = [f"PARITY_INVENTORY_WARN unclassified sentence (advisory; --stubs prints an entry): {key}  {packet[key]['text']}"
             for key in unclassified]
    lines += [f"PARITY_INVENTORY_WARN classified sentence no longer in its packet (generate drops it): {key}" for key in gone]
    return lines, {"sentence_unclassified": len(unclassified), "sentence_gone": len(gone)}


def build(root: Path) -> tuple[dict[str, bytes], dict]:
    curation = load_curation(root)
    sources = live_sources(root, curation)
    items, item_errors = validate_items(root, curation)
    table, unclassified, errors = classify(root, curation, sources, items) if not item_errors else ({}, [], [])
    problems = item_errors + errors
    if unclassified or problems:
        lines = [f"PARITY_INVENTORY_FAIL items={len(items)} sources={len(sources)} unclassified={len(unclassified)} errors={len(problems)}"]
        lines += [f"unclassified source: {key}" for key in unclassified]
        lines += problems
        if unclassified:
            lines.append("classify each in " + CURATION.as_posix()
                         + " (`PYTHONPATH=tools python3 -m hsltools.checks.parity_inventory --stubs` prints entries to edit)")
        raise CheckFailed("\n".join(lines))
    document, data = render(curation, sources, table, items)
    rendered = {OUTPUT_DOC.as_posix(): document.encode("utf-8"), OUTPUT_JSON.as_posix(): json_bytes(data)}
    return rendered, data["counts"]


def summary_line(counts: dict, verdict: str, extra: dict | None = None) -> str:
    kinds = counts["sources_by_kind"]
    tail = "".join(f" {name}={value}" for name, value in (extra or {}).items() if value)
    return (f"PARITY_INVENTORY_{verdict} items={counts['items']} sources={counts['sources']} unclassified=0 "
            f"provenance={kinds['provenance']} layout_timing_modules={counts['layout_timing_modules']} "
            f"packet_sentences={kinds['sentence']} packet_scopes={kinds['scope']} matrix_rows={kinds['matrix']} "
            f"video_classes={kinds['video']}{tail}")


class ParityInventoryTask(GeneratedFilesTask):
    name = "parity_inventory"
    family = "checks"
    inputs = (CURATION.as_posix(), "game/", "docs/evidence_packets/", MATRIX.as_posix())
    outputs = (OUTPUT_DOC.as_posix(), OUTPUT_JSON.as_posix())
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ("tools/hsltools/checks/parity_inventory.py",)

    def render(self, ctx: Context) -> dict[str, bytes]:
        rendered, self.counts = build(ctx.root)
        lines, self.warnings = sentence_warnings(ctx.root, load_curation(ctx.root))
        for line in lines:
            print(line)
        return rendered

    def generate(self, ctx: Context) -> str:
        dropped, kept = prune_gone_sentences(ctx.root)
        self.dropped = len(dropped)
        for key in dropped:
            print(f"PARITY_INVENTORY_DROPPED {key}")
        for key in kept:
            print(f"PARITY_INVENTORY_WARN kept (last reference of its item; reclassify the item by hand): {key}")
        return super().generate(ctx)

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        if mode == "check":
            return summary_line(self.counts, "PASS", self.warnings)
        return summary_line(self.counts, "WRITTEN", {**self.warnings, "sentence_dropped": self.dropped})


def tasks() -> list[ParityInventoryTask]:
    return [ParityInventoryTask()]


def main(argv: list[str] | None = None) -> int:
    import argparse

    from hsltools.paths import ROOT

    parser = argparse.ArgumentParser(description="parity gap inventory helper — check／generate run through tools/hsl.py")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--stubs", action="store_true", help="print curation entries for every unclassified live source")
    group.add_argument("--list", action="store_true", help="print every live source key with its text")
    args = parser.parse_args(argv)
    curation = load_curation(ROOT)
    sources = {**strict_sources(ROOT, curation), **sentence_sources(ROOT)}  # sentences as the packets say them now
    if args.list:
        for key, source in sorted(sources.items()):
            text = source.get("note") or source.get("text") or source.get("scope") or source.get("title") or ""
            print(f"{key}\t{text}")
        return 0
    known = curation.get("sources") or {}
    stubs = {key: stub(key, source) for key, source in sorted(sources.items()) if key not in known}
    print(json.dumps(stubs, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
