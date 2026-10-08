#!/usr/bin/env python3
"""CARBON text-fidelity checker (spec section 20, acceptance test 13).

Diffs the exact game text printed in CARBON_SPEC.md against every string in
the /data JSON files, after substituting the test token values on both sides.
Standard library only.

    python3 tools/check_text.py [--data-dir DIR] [--spec FILE] [--list]

Prints one PASS/FAIL line per spec line checked, then the first 40 failures in
full, then "TEXT FIDELITY: N checked, M failed". Exit 0 when M == 0, else 1.
A missing, unreadable or malformed data file is a failure, never a crash.
--list prints the extracted spec lines (section, kind, match mode) and exits.
"""

import argparse
import difflib
import json
import os
import re
import sys
from collections import Counter

DEFAULT_DATA_DIR = "/home/user/Carbon/data"
DEFAULT_SPEC = "/home/user/Carbon/CARBON_SPEC.md"

# Files the brief requires. Every other *.json in the data directory is also read.
REQUIRED_DATA_FILES = [
    "strings.json", "endings.json", "layouts.json",
    "day1.json", "day2.json", "day3.json", "day4.json", "day5.json",
    "credits.json",
]
MAX_FAILURES_SHOWN = 40
LINE_WIDTH = 100

# Test values from the brief. Substituted into the spec and into every data string,
# so template slots such as {X}, {OWNER}, {n}, {total} and {k} are compared with the
# same test value on both sides.
TEST_TOKENS = {
    "{PLAYER_NAME}": "TEST PLAYER",
    "{PLAYER_NAME_TC}": "Test Player",
    "{PLAYER_FIRST_NAME}": "TEST",
    "{PLAYER_FIRST_NAME_TC}": "Test",
    "{NEXT_OF_KIN}": "TEST KIN",
    "{NEXT_OF_KIN_TC}": "Test Kin",
    "{FOND_WORD}": "LANTERN",
    "{DAYNAME}": "MONDAY",
    "{occupied}": "11",
    "{RE}": "",
    "{CARRIED_IDS}": "",
    "{CARRIED_BLOCK}": "",
    "{P1_Q4}": "YES",
    "{SIGNATURE_MATCHES}": "TRUE",
    "{name}": "TEST NAME",
    "{reg}": "1234567",
    "{ward}": "IV",
    "{date}": "03.XI",
    "{X}": "T",
    "{OWNER}": "THE CLERK'S",
    "{n}": "1",
    "{total}": "3",
    "{k}": "1",
}

# Section scopes (section ids match by prefix: "14" covers 14.1 to 14.13).
FENCE_SCOPE = ("8.11", "14", "15", "16")          # printed documents, boards, title
QUOTE_SCOPE = ("14",)                             # handwritten blockquotes
INLINE_SCOPE = ("8.1", "8.4", "8.14", "10.3", "13.1", "14.4", "14.5", "14.6", "14.7",
                "14.8", "14.9", "14.10", "14.11", "15", "16")
TABLE_SCOPE = ("16.3",)                           # settings names (column 1)
ANY_ALLCAPS_WORD_SCOPE = ("16",)                  # menu labels such as YES / NO
WEEKDAYS_AND_STAMPS = {"MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY",
                       "APPROVED", "DENIED", "PROCESSED"}

HEADING_RE = re.compile(r"^#{2,3}\s+(\d+(?:\.\d+)?)\.?\s")
SPAN_RE = re.compile(r"`([^`]+)`")
BARE_TOKEN_RE = re.compile(r"\{[^{}]+\}")          # a lone token is notation, not text
TRANSCRIPTION_ID_RE = re.compile(r"(?<=\s)X(?=:)")  # "TRANSCRIPTION X:" / "BATCH X:" slot
ALLCAPS_RE = re.compile(r"[A-Z]+")
PHRASE_RE = re.compile(r"[A-Z0-9 .,:'\-—()/&!?]+")
OWNER_ONLY_RE = re.compile(r"THE (?:CITIZEN|BUREAU|CLERK)'S")   # a value fragment
CREDITS_RE = re.compile(r"exactly one line: `([^`]+)`")
# Lines that quote a heading or a source rather than printing game text.
REFERENCE_LINE_RE = re.compile(r"Transcription source|is excluded")
MEMO_HEADER_START = "BUREAU OF CONTINUITY — REGISTRY, HALL C"
LAYOUT_FILE = "layouts.json"


def under(sec, scopes):
    """True when section id sec is one of scopes or a subsection of one."""
    return any(sec == s or sec.startswith(s + ".") for s in scopes)


def subst(text):
    """Apply the test token map."""
    for token, value in TEST_TOKENS.items():
        text = text.replace(token, value)
    return text


def key(text):
    """Normalise a line: runs of spaces become one space, trailing space is removed."""
    return re.sub(" +", " ", text).rstrip()


def flatten(obj):
    """All string values of a JSON document, in order. Keys are not text."""
    if isinstance(obj, str):
        return [obj]
    if isinstance(obj, list):
        out = []
        for item in obj:
            out.extend(flatten(item))
        return out
    if isinstance(obj, dict):
        out = []
        for value in obj.values():
            out.extend(flatten(value))
        return out
    return []


def make_item(sec, kind, text, mode, lineno, pool=None):
    return {"sec": sec, "kind": kind, "text": text, "mode": mode,
            "lineno": lineno, "pool": pool}


def make_result(sec, kind, text, mode, ok, closest=None):
    return {"sec": sec, "kind": kind, "text": text, "mode": mode,
            "ok": ok, "closest": closest}


def classify_span(sec, span, line, lineno):
    """Decide whether one backtick span in the spec is checkable game text."""
    raw = span.strip()
    if BARE_TOKEN_RE.fullmatch(raw):
        return None                                   # bare token: notation
    text = subst(TRANSCRIPTION_ID_RE.sub("{X}", raw)).strip()
    if not text or text.endswith(":") or OWNER_ONLY_RE.fullmatch(text):
        return None                                   # a value fragment, not a line
    if ALLCAPS_RE.fullmatch(text):
        if text in WEEKDAYS_AND_STAMPS or under(sec, ANY_ALLCAPS_WORD_SCOPE):
            return make_item(sec, "inline", text, "exact", lineno)
        return None
    if " " in text and PHRASE_RE.fullmatch(text) and sum(c.isalpha() for c in text) >= 2:
        # Surnames quoted in the ghost-typing list of 15.3 appear as they do on the
        # orders, so they are matched as fragments of a data string.
        mode = "frag" if under(sec, ("15",)) and "entity" in line else "exact"
        return make_item(sec, "inline", text, mode, lineno)
    return None


def fence_items(sec, block, lineno):
    if not under(sec, FENCE_SCOPE):
        return []
    pool = LAYOUT_FILE if (sec == "14.4" and "FORM R-2" in "\n".join(block)) else None
    return [make_item(sec, "fence", ln.rstrip(), "exact", lineno, pool)
            for ln in block if ln.strip()]


def parse_spec(spec_text):
    """Return (items, fences). fences is a list of (section, lines) for code blocks."""
    items, fences = [], []
    section = "0"
    in_fence = False
    fence_indent = 0
    fence_sec = "0"
    fence_start = 0
    fence_block = []
    for lineno, raw in enumerate(spec_text.split("\n"), 1):
        stripped = raw.strip()
        if in_fence:
            if stripped == "```":
                in_fence = False
                fences.append((fence_sec, fence_block))
                items.extend(fence_items(fence_sec, fence_block, fence_start))
            else:
                cut = 0
                while cut < fence_indent and cut < len(raw) and raw[cut] == " ":
                    cut += 1
                fence_block.append(raw[cut:])
            continue
        if stripped.startswith("```"):
            in_fence = True
            fence_indent = len(raw) - len(raw.lstrip(" "))
            fence_sec = section
            fence_start = lineno
            fence_block = []
            continue
        heading = HEADING_RE.match(raw)
        if heading:
            section = heading.group(1)
            continue
        if raw.startswith(">") and under(section, QUOTE_SCOPE):
            body = re.sub(r"^>\s?", "", raw).rstrip()
            if body.strip():
                items.append(make_item(section, "quote", body, "frag", lineno))
            continue
        if raw.startswith("|") and under(section, TABLE_SCOPE):
            cells = [c.strip() for c in raw.strip().strip("|").split("|")]
            name = cells[0] if cells else ""
            if name and name != "Setting" and not set(name) <= set("-: "):
                items.append(make_item(section, "table", name, "exact", lineno))
            continue
        if under(section, INLINE_SCOPE) and not REFERENCE_LINE_RE.search(raw):
            for match in SPAN_RE.finditer(raw):
                item = classify_span(section, match.group(1), raw, lineno)
                if item is not None:
                    items.append(item)
    return items, fences


class Pool:
    """Data-side strings, normalised: whole strings and their individual lines."""

    def __init__(self, strings):
        self.fulls = []
        lines = set()
        for text in strings:
            self.fulls.append(key(text))
            for ln in text.split("\n"):
                lines.add(key(ln))
        self.lines = lines
        self.line_list = sorted(lines)


def closest_match(want, candidates):
    hits = difflib.get_close_matches(want, candidates, n=1, cutoff=0.5)
    return hits[0] if hits else "(nothing similar in /data)"


def check_items(items, pools):
    results = []
    for it in items:
        pool = pools[LAYOUT_FILE] if it["pool"] == LAYOUT_FILE else pools["all"]
        want = key(subst(it["text"]))
        if not want.strip():
            continue                      # blank after substitution (e.g. empty carried block)
        if it["mode"] == "frag":
            ok = any(want in full for full in pool.fulls)
            closest = None if ok else closest_match(want, pool.fulls)
        else:
            ok = want in pool.lines
            closest = None if ok else closest_match(want, pool.line_list)
        results.append(make_result(it["sec"], it["kind"], it["text"], it["mode"], ok, closest))
    return results


def value_lines(value):
    """Normalised lines of a data value (string or list of strings)."""
    if isinstance(value, list):
        text = "\n".join(v for v in value if isinstance(v, str))
    elif isinstance(value, str):
        text = value
    else:
        return None
    return [key(subst(ln)) for ln in text.split("\n")]


def memo_results(raw_json, fences):
    """Reverse check: strings.json memo_header and memo_re_line against section 14.4."""
    header = next((blk for sec, blk in fences
                   if sec == "14.4" and blk and blk[0].startswith(MEMO_HEADER_START)), None)
    if header is None:
        return [make_result("14.4", "reverse", "memo header block not found in spec",
                            "reverse", False)]
    re_index = next((i for i, ln in enumerate(header) if ln.startswith("RE:")), len(header) - 1)
    spec_header = [key(subst(ln)) for ln in header[:re_index] if ln.strip()]
    spec_re = key(subst(header[re_index]))
    strings = raw_json.get("strings.json")
    results = []
    for label, expected in (("memo_header", spec_header), ("memo_re_line", [spec_re])):
        text = f"data/strings.json {label} equals the section 14.4 memo header"
        if not isinstance(strings, dict) or label not in strings:
            results.append(make_result("14.4", "reverse", text, "reverse", False,
                                       "(strings.json or this key is missing)"))
            continue
        got = value_lines(strings[label])
        got = [ln for ln in got if ln.strip()] if got is not None else None
        ok = got == expected
        results.append(make_result("14.4", "reverse", text, "reverse", ok,
                                   None if ok else f"found {got!r}, expected {expected!r}"))
    return results


def credits_result(raw_json, spec_text):
    if "credits.json" not in raw_json:
        return None                       # already reported as a missing file
    match = CREDITS_RE.search(spec_text)
    if match is None:
        return make_result("15.4", "credits", "credits line not found in spec", "exact", False)
    want = key(subst(match.group(1)).strip())
    got = [key(s) for s in flatten(raw_json["credits.json"]) if s.strip()]
    ok = got == [want]
    return make_result("15.4", "credits",
                       f"credits.json holds exactly one line: {want}", "exact", ok,
                       None if ok else f"found {got!r}")


def load_data(data_dir):
    """Read every JSON file in data_dir. Returns (strings per file, parsed JSON, problems)."""
    names = list(REQUIRED_DATA_FILES)
    try:
        for extra in sorted(os.listdir(data_dir)):
            if extra.endswith(".json") and extra not in names:
                names.append(extra)
    except OSError:
        pass                              # missing directory: each required file is reported
    file_data, raw_json, problems = {}, {}, []
    short_dir = os.path.basename(os.path.normpath(data_dir)) or data_dir
    for fname in names:
        path = os.path.join(data_dir, fname)
        shown = f"{short_dir}/{fname}"
        if not os.path.isfile(path):
            if fname in REQUIRED_DATA_FILES:
                problems.append(f"DATA FILE MISSING: {shown}")
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                obj = json.load(fh)
        except (OSError, ValueError) as exc:
            problems.append(f"DATA FILE UNREADABLE: {shown}: {exc}")
            continue
        raw_json[fname] = obj
        file_data[fname] = [subst(s) for s in flatten(obj)]
    return file_data, raw_json, problems


def shorten(text):
    return text if len(text) <= LINE_WIDTH else text[:LINE_WIDTH - 3] + "..."


def main(argv=None):
    parser = argparse.ArgumentParser(description="CARBON text-fidelity checker (test 13).")
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR)
    parser.add_argument("--spec", default=DEFAULT_SPEC)
    parser.add_argument("--list", action="store_true",
                        help="print the extracted spec lines and exit")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    try:
        with open(args.spec, encoding="utf-8") as fh:
            spec_text = fh.read()
    except OSError as exc:
        print(f"FAIL  spec unreadable: {args.spec}: {exc}")
        print("TEXT FIDELITY: 0 checked, 1 failed")
        return 1

    items, fences = parse_spec(spec_text)
    if args.list:
        for it in items:
            print(f"{it['sec']:<6} {it['kind']:<8} {it['mode']:<8} {it['text']}")
        print(f"{len(items)} spec lines extracted")
        return 0

    file_data, raw_json, problems = load_data(args.data_dir)
    everything = [s for strings in file_data.values() for s in strings]
    pools = {"all": Pool(everything),
             LAYOUT_FILE: Pool(file_data.get(LAYOUT_FILE, []))}

    results = [make_result("-", "file", msg, "file", False) for msg in problems]
    results += check_items(items, pools)
    results += memo_results(raw_json, fences)
    credit = credits_result(raw_json, spec_text)
    if credit is not None:
        results.append(credit)

    kinds = Counter(r["kind"] for r in results)
    print("BY KIND: " + ", ".join(f"{k}={kinds[k]}" for k in sorted(kinds)))
    for r in results:
        status = "PASS" if r["ok"] else "FAIL"
        print(f"{status}  {r['sec']:<6} {r['kind']:<8} {shorten(r['text'])}")

    fails = [r for r in results if not r["ok"]]
    if fails:
        print("")
        print(f"FAILURES (first {min(len(fails), MAX_FAILURES_SHOWN)} of {len(fails)}):")
        for n, r in enumerate(fails[:MAX_FAILURES_SHOWN], 1):
            print(f"[{n}] section {r['sec']} | {r['kind']} | {r['mode']}")
            print(f"    spec:    {r['text']}")
            print(f"    closest: {r['closest'] or '(none)'}")
    print(f"TEXT FIDELITY: {len(results)} checked, {len(fails)} failed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
