#!/usr/bin/env python3
"""rushlib - stdlib-only Python helpers for Rush DevKit's bash scripts.

This module does the parsing work that bash is bad at (JSON, Markdown
sections, task lists, dependency graphs) so `.rush/scripts/*.sh` stay
thin process/git glue. No third-party dependencies: only the Python 3
standard library, so the kit never needs a package manager to run its
own harness.

Usable two ways:

1. As a library from other Python code (e.g. a heredoc embedded in a
   bash script)::

       sys.path.insert(0, ".rush/scripts/lib")
       import rushlib
       tasks = rushlib.parse_tasks(open("tasks.md").read())

2. As a CLI, so bash can call it directly::

       python3 .rush/scripts/lib/rushlib.py tasks-list specs/007-x/tasks.md
       python3 .rush/scripts/lib/rushlib.py json-get .rush/config.json triage.max_files_for_S --default 3

Run `python3 rushlib.py <subcommand> --help` for the exact flags of each
subcommand.

Exit code convention (matches the rest of the kit): 0 success / found,
1 valid negative result (not found, cycle detected, task id unknown),
2 usage or internal error (bad arguments, malformed input file).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from typing import Any, Dict, List, Optional, Tuple

# --------------------------------------------------------------------------
# JSON files with dotted-path access
# --------------------------------------------------------------------------

#: Sentinel distinguishing "key absent" from a real JSON null.
_MISSING = object()


def load_json_file(path: str) -> Any:
    """Read and parse a JSON file. Raises OSError / json.JSONDecodeError."""
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def dump_json_file(path: str, data: Any) -> None:
    """Write `data` as pretty JSON to `path` atomically (temp file + rename).

    Creates parent directories if needed. 2-space indent, trailing
    newline, UTF-8, key order preserved as given (never re-sorted, so
    hand-authored config.json ordering survives a patch).
    """
    directory = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".rushlib-tmp-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp_path, path)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def get_path(data: Any, dotted: str) -> Any:
    """Resolve a dotted path ("a.b.c") against nested dicts.

    Returns `_MISSING` (not None) when any segment is absent, so callers
    can distinguish "not set" from "set to null".
    """
    if dotted in ("", "."):
        return data
    cur = data
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return _MISSING
    return cur


def set_path(data: Dict[str, Any], dotted: str, value: Any) -> None:
    """Set `data` at a dotted path, creating intermediate objects as needed.

    Raises TypeError if an intermediate segment exists and is not itself
    an object (refuses to clobber e.g. a list or string with a dict).
    """
    parts = dotted.split(".")
    cur = data
    for part in parts[:-1]:
        nxt = cur.get(part, _MISSING)
        if nxt is _MISSING:
            nxt = {}
            cur[part] = nxt
        elif not isinstance(nxt, dict):
            raise TypeError(
                "cannot set '%s': '%s' is not an object (got %s)"
                % (dotted, part, type(nxt).__name__)
            )
        cur = nxt
    cur[parts[-1]] = value


def list_keys(data: Any, dotted: str) -> List[str]:
    """Keys of the object at `dotted`, or [] if missing / not an object."""
    value = get_path(data, dotted)
    if isinstance(value, dict):
        return list(value.keys())
    return []


def _format_scalar(value: Any) -> str:
    """Render a JSON value the way a shell variable should see it."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return json.dumps(value)
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False)


# --------------------------------------------------------------------------
# Fenced ```json blocks in Markdown
# --------------------------------------------------------------------------

_FENCE_OPEN_RE = re.compile(r"^(```|~~~)\s*([A-Za-z0-9_+-]*)\s*$")


def extract_json_block(text: str, index: int = 0) -> Optional[str]:
    """Return the raw text of the Nth fenced ```json (or ~~~json) block.

    `index` is 0-based across all fenced-json blocks in the document, in
    document order. Returns None if there is no such block. An
    unterminated fence at end-of-file is still returned (best effort);
    validating that it parses as JSON is the caller's job.
    """
    lines = text.splitlines()
    blocks: List[str] = []
    i, n = 0, len(lines)
    while i < n:
        m = _FENCE_OPEN_RE.match(lines[i].strip())
        if m and m.group(2).lower() == "json":
            fence = m.group(1)
            body: List[str] = []
            i += 1
            while i < n and lines[i].strip() != fence:
                body.append(lines[i])
                i += 1
            if i < n:
                i += 1  # consume closing fence
            blocks.append("\n".join(body))
            continue
        i += 1
    if 0 <= index < len(blocks):
        return blocks[index]
    return None


# --------------------------------------------------------------------------
# Markdown headings -> section map
# --------------------------------------------------------------------------

_HEADING_RE = re.compile(r"^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
_FENCE_TOGGLE_RE = re.compile(r"^(```|~~~)")


def parse_headings(text: str) -> List[Dict[str, Any]]:
    """Parse ATX (`#`) headings into a flat section list.

    Each entry: {"level": int, "title": str, "line": int (1-based),
    "content": str} where `content` is everything between this heading
    and the next heading of equal-or-lower level (exclusive of both
    heading lines). Headings inside fenced code blocks are ignored.
    """
    lines = text.splitlines()
    headings: List[Dict[str, Any]] = []
    in_fence = False
    fence_marker = ""
    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        fm = _FENCE_TOGGLE_RE.match(stripped)
        if fm:
            marker = fm.group(1)
            if not in_fence:
                in_fence = True
                fence_marker = marker
            elif stripped.startswith(fence_marker):
                in_fence = False
                fence_marker = ""
            continue
        if in_fence:
            continue
        hm = _HEADING_RE.match(line)
        if hm:
            headings.append({"level": len(hm.group(1)), "title": hm.group(2).strip(), "line": idx})

    result: List[Dict[str, Any]] = []
    for i, h in enumerate(headings):
        end = len(lines)
        for j in range(i + 1, len(headings)):
            if headings[j]["level"] <= h["level"]:
                end = headings[j]["line"] - 1
                break
        content_lines = lines[h["line"]:end]
        result.append(
            {
                "level": h["level"],
                "title": h["title"],
                "line": h["line"],
                "content": "\n".join(content_lines).strip("\n"),
            }
        )
    return result


# --------------------------------------------------------------------------
# Content-line counting for budget checks
# --------------------------------------------------------------------------


def count_content_lines(text: str) -> int:
    """Count lines that count toward a budget.

    Excludes fenced code blocks (both fence lines and their content) and
    HTML comments (`<!-- ... -->`, single- or multi-line). Everything
    else counts, including blank lines, matching how a human skims the
    file.
    """
    lines = text.splitlines()
    count = 0
    in_fence = False
    fence_marker = ""
    in_comment = False
    for line in lines:
        stripped = line.strip()
        if in_comment:
            if "-->" in stripped:
                in_comment = False
            continue
        fm = _FENCE_TOGGLE_RE.match(stripped)
        if fm:
            marker = fm.group(1)
            if not in_fence:
                in_fence = True
                fence_marker = marker
            elif stripped.startswith(fence_marker):
                in_fence = False
                fence_marker = ""
            continue
        if in_fence:
            continue
        if stripped.startswith("<!--"):
            if "-->" not in stripped[4:]:
                in_comment = True
            continue
        count += 1
    return count


# --------------------------------------------------------------------------
# tasks.md parsing / patching
# --------------------------------------------------------------------------

# Matches .rush/templates/tasks-template.md exactly:
#
#   ### T001 — Set up DB schema
#   - status: `pending`
#   - verify: `npm run test:db`
#
# The id/title separator is an em dash in the template but a plain
# hyphen or en dash is also accepted (hand-edited files vary). Anything
# other than the four known statuses is left as "pending" rather than
# rejected outright - a typo'd status shouldn't make the whole file
# unparseable.
_TASK_HEADING_RE = re.compile(r"^###\s+(\S+)\s*[—–-]\s*(.*?)\s*$")
_STATUS_LINE_RE = re.compile(r"^(\s*)-\s*status:\s*`?([A-Za-z_]+)`?\s*$", re.IGNORECASE)
_VERIFY_LINE_RE = re.compile(r"^\s*-\s*verify:\s*`([^`]*)`\s*$", re.IGNORECASE)
_ANY_HEADING_RE = re.compile(r"^#{1,6}\s+")

STATUS_CHOICES: Tuple[str, ...] = ("pending", "in_progress", "blocked", "done")
_CHAR_BY_STATUS = {"pending": " ", "in_progress": "~", "blocked": "!", "done": "x"}  # kept for compat


def _split_line_ending(line: str) -> Tuple[str, str]:
    for eol in ("\r\n", "\n", "\r"):
        if line.endswith(eol):
            return line[: -len(eol)], eol
    return line, ""


def parse_tasks(text: str) -> List[Dict[str, Any]]:
    """Parse a tasks.md (### id — title / - status: / - verify: format).

    Each entry: {"id": str, "title": str, "status": one of
    STATUS_CHOICES (default "pending" if the status line is missing or
    unrecognised), "verify": str|None, "line": int (1-based, the heading
    line)}.
    """
    lines = text.splitlines()
    tasks: List[Dict[str, Any]] = []
    i, n = 0, len(lines)
    while i < n:
        m = _TASK_HEADING_RE.match(lines[i])
        if not m:
            i += 1
            continue
        task_id = m.group(1)
        title = m.group(2).strip()
        line_no = i + 1
        status = "pending"
        verify: Optional[str] = None
        j = i + 1
        while j < n and not _TASK_HEADING_RE.match(lines[j]) and not _ANY_HEADING_RE.match(lines[j]):
            sm = _STATUS_LINE_RE.match(lines[j])
            if sm:
                candidate = sm.group(2).lower()
                if candidate in STATUS_CHOICES:
                    status = candidate
            vm = _VERIFY_LINE_RE.match(lines[j])
            if vm:
                verify = vm.group(1).strip()
            j += 1
        tasks.append(
            {"id": task_id, "title": title, "status": status, "verify": verify, "line": line_no}
        )
        i = j
    return tasks


def set_task_status(text: str, task_id: str, status: str) -> Tuple[str, bool]:
    """Return (new_text, found) with `task_id`'s `- status:` line rewritten.

    Only that one line changes (its status token and its own line
    ending are preserved as closely as possible); everything else -
    title, verify line, indentation, other tasks - is untouched. If the
    task heading exists but has no `- status:` line, one is inserted
    right after the heading rather than silently doing nothing.
    """
    if status not in STATUS_CHOICES:
        raise ValueError("unknown status: %r (expected one of %s)" % (status, STATUS_CHOICES))
    lines = text.splitlines(keepends=True)
    n = len(lines)
    found = False
    i = 0
    while i < n:
        body, _ = _split_line_ending(lines[i])
        m = _TASK_HEADING_RE.match(body)
        if m and m.group(1) == task_id:
            found = True
            j = i + 1
            status_idx = None
            while j < n:
                b2, _ = _split_line_ending(lines[j])
                if _TASK_HEADING_RE.match(b2) or _ANY_HEADING_RE.match(b2):
                    break
                if _STATUS_LINE_RE.match(b2):
                    status_idx = j
                    break
                j += 1
            if status_idx is not None:
                b2, e2 = _split_line_ending(lines[status_idx])
                indent = _STATUS_LINE_RE.match(b2).group(1)
                lines[status_idx] = "%s- status: `%s`%s" % (indent, status, e2 or "\n")
            else:
                _, e1 = _split_line_ending(lines[i])
                lines.insert(i + 1, "- status: `%s`%s" % (status, e1 or "\n"))
            break
        i += 1
    return "".join(lines), found


# --------------------------------------------------------------------------
# Topological sort with cycle detection
# --------------------------------------------------------------------------


class CycleError(Exception):
    """Raised by topo_sort when the graph is not a DAG."""

    def __init__(self, cycle: List[str]):
        super().__init__("dependency cycle: " + " -> ".join(cycle))
        self.cycle = cycle


def topo_sort(graph: Dict[str, List[str]]) -> List[str]:
    """Dependency-first topological sort.

    `graph[node]` lists the nodes that must come *before* `node` (its
    dependencies) — matching "provider before consumer" semantics.
    Nodes that only appear as a dependency (not as a key) are included
    with an empty dependency list. Deterministic: ties are broken by
    sorting node names. Raises CycleError with the offending cycle path
    on a cycle.
    """
    nodes = set(graph.keys())
    for deps in graph.values():
        nodes.update(deps)
    ordered_nodes = sorted(nodes)
    adj = {n: sorted(set(graph.get(n, []))) for n in ordered_nodes}

    UNVISITED, VISITING, DONE = 0, 1, 2
    state: Dict[str, int] = {}
    order: List[str] = []
    path: List[str] = []

    def visit(node: str) -> None:
        st = state.get(node, UNVISITED)
        if st == DONE:
            return
        if st == VISITING:
            idx = path.index(node)
            raise CycleError(path[idx:] + [node])
        state[node] = VISITING
        path.append(node)
        for dep in adj.get(node, []):
            visit(dep)
        path.pop()
        state[node] = DONE
        order.append(node)

    for n in ordered_nodes:
        if state.get(n, UNVISITED) == UNVISITED:
            visit(n)
    return order


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def _read_file(path: str) -> Optional[str]:
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def cmd_json_get(args: argparse.Namespace) -> int:
    if not os.path.isfile(args.file):
        return _print_default(args)
    try:
        data = load_json_file(args.file)
    except (OSError, json.JSONDecodeError) as e:
        print("rushlib: cannot parse %s: %s" % (args.file, e), file=sys.stderr)
        return 2
    value = get_path(data, args.path)
    if value is _MISSING:
        return _print_default(args)
    if args.type == "bool":
        if isinstance(value, bool):
            print("true" if value else "false")
        elif isinstance(value, str) and value.strip().lower() in ("true", "false"):
            print(value.strip().lower())
        else:
            print("true" if value else "false")
        return 0
    if args.type == "lines":
        if not isinstance(value, list):
            print("rushlib: value at '%s' is not a list" % args.path, file=sys.stderr)
            return 2
        for item in value:
            print(item if isinstance(item, str) else json.dumps(item, ensure_ascii=False))
        return 0
    print(_format_scalar(value))
    return 0


def _print_default(args: argparse.Namespace) -> int:
    if args.type == "bool":
        d = (args.default or "false").strip().lower()
        print(d if d in ("true", "false") else "false")
    elif args.type == "lines":
        for item in (args.default or "").split("\n"):
            if item != "":
                print(item)
    else:
        print(args.default)
    return 0


def cmd_json_set(args: argparse.Namespace) -> int:
    if os.path.isfile(args.file):
        try:
            data = load_json_file(args.file)
        except (OSError, json.JSONDecodeError) as e:
            print("rushlib: cannot parse %s: %s" % (args.file, e), file=sys.stderr)
            return 2
        if not isinstance(data, dict):
            print("rushlib: %s root is not a JSON object" % args.file, file=sys.stderr)
            return 2
    else:
        data = {}
    if args.raw:
        value: Any = args.value
    else:
        try:
            value = json.loads(args.value)
        except json.JSONDecodeError as e:
            print(
                "rushlib: VALUE is not valid JSON (use --raw for a literal string): %s" % e,
                file=sys.stderr,
            )
            return 2
    try:
        set_path(data, args.path, value)
    except TypeError as e:
        print("rushlib: %s" % e, file=sys.stderr)
        return 2
    try:
        dump_json_file(args.file, data)
    except OSError as e:
        print("rushlib: cannot write %s: %s" % (args.file, e), file=sys.stderr)
        return 2
    return 0


def cmd_json_list_append(args: argparse.Namespace) -> int:
    if os.path.isfile(args.file):
        try:
            data = load_json_file(args.file)
        except (OSError, json.JSONDecodeError) as e:
            print("rushlib: cannot parse %s: %s" % (args.file, e), file=sys.stderr)
            return 2
        if not isinstance(data, dict):
            print("rushlib: %s root is not a JSON object" % args.file, file=sys.stderr)
            return 2
    else:
        data = {}
    try:
        value = json.loads(args.value)
    except json.JSONDecodeError as e:
        print("rushlib: VALUE is not valid JSON: %s" % e, file=sys.stderr)
        return 2
    existing = get_path(data, args.path)
    if existing is _MISSING:
        existing = []
        set_path(data, args.path, existing)
    elif not isinstance(existing, list):
        print("rushlib: value at '%s' is not a list" % args.path, file=sys.stderr)
        return 2
    replaced = False
    if args.key and isinstance(value, dict) and args.key in value:
        for i, item in enumerate(existing):
            if isinstance(item, dict) and item.get(args.key) == value[args.key]:
                existing[i] = value
                replaced = True
                break
    if not replaced:
        existing.append(value)
    try:
        dump_json_file(args.file, data)
    except OSError as e:
        print("rushlib: cannot write %s: %s" % (args.file, e), file=sys.stderr)
        return 2
    return 0


def cmd_json_keys(args: argparse.Namespace) -> int:
    if not os.path.isfile(args.file):
        return 0
    try:
        data = load_json_file(args.file)
    except (OSError, json.JSONDecodeError) as e:
        print("rushlib: cannot parse %s: %s" % (args.file, e), file=sys.stderr)
        return 2
    for k in list_keys(data, args.path):
        print(k)
    return 0


def cmd_extract_json_block(args: argparse.Namespace) -> int:
    text = _read_file(args.file)
    if text is None:
        print("rushlib: file not found: %s" % args.file, file=sys.stderr)
        return 2
    block = extract_json_block(text, args.index)
    if block is None:
        print(
            "rushlib: no fenced ```json block (index %d) found in %s" % (args.index, args.file),
            file=sys.stderr,
        )
        return 1
    if args.validate:
        try:
            json.loads(block)
        except json.JSONDecodeError as e:
            print(
                "rushlib: fenced json block in %s is not valid JSON: %s" % (args.file, e),
                file=sys.stderr,
            )
            return 2
    print(block)
    return 0


def cmd_parse_headings(args: argparse.Namespace) -> int:
    text = _read_file(args.file)
    if text is None:
        print("rushlib: file not found: %s" % args.file, file=sys.stderr)
        return 2
    print(json.dumps(parse_headings(text), ensure_ascii=False))
    return 0


def cmd_count_lines(args: argparse.Namespace) -> int:
    text = _read_file(args.file)
    if text is None:
        print("rushlib: file not found: %s" % args.file, file=sys.stderr)
        return 2
    print(count_content_lines(text))
    return 0


def cmd_tasks_list(args: argparse.Namespace) -> int:
    text = _read_file(args.file)
    if text is None:
        print("rushlib: file not found: %s" % args.file, file=sys.stderr)
        return 2
    print(json.dumps(parse_tasks(text), ensure_ascii=False))
    return 0


def cmd_tasks_set(args: argparse.Namespace) -> int:
    text = _read_file(args.file)
    if text is None:
        print("rushlib: file not found: %s" % args.file, file=sys.stderr)
        return 2
    try:
        new_text, found = set_task_status(text, args.id, args.status)
    except ValueError as e:
        print("rushlib: %s" % e, file=sys.stderr)
        return 2
    if not found:
        print("rushlib: task '%s' not found in %s" % (args.id, args.file), file=sys.stderr)
        return 1
    try:
        dump_text_file(args.file, new_text)
    except OSError as e:
        print("rushlib: cannot write %s: %s" % (args.file, e), file=sys.stderr)
        return 2
    updated = next((t for t in parse_tasks(new_text) if t["id"] == args.id), None)
    print(json.dumps(updated, ensure_ascii=False))
    return 0


def dump_text_file(path: str, text: str) -> None:
    """Atomic write of plain text (temp file + rename), preserving bytes."""
    directory = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".rushlib-tmp-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.replace(tmp_path, path)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def cmd_topo_sort(args: argparse.Namespace) -> int:
    if args.file:
        raw = _read_file(args.file)
        if raw is None:
            print("rushlib: file not found: %s" % args.file, file=sys.stderr)
            return 2
    else:
        raw = sys.stdin.read()
    try:
        graph = json.loads(raw)
    except json.JSONDecodeError as e:
        print("rushlib: invalid JSON graph: %s" % e, file=sys.stderr)
        return 2
    if not isinstance(graph, dict) or not all(isinstance(v, list) for v in graph.values()):
        print(
            "rushlib: graph must be a JSON object mapping node -> [dependency, ...]",
            file=sys.stderr,
        )
        return 2
    try:
        order = topo_sort(graph)
    except CycleError as e:
        print(json.dumps({"error": "cycle", "path": e.cycle}, ensure_ascii=False))
        return 1
    print(json.dumps(order, ensure_ascii=False))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="rushlib.py",
        description="Rush DevKit stdlib-only helper: JSON config, markdown sections, "
        "task lists, dependency graphs.",
    )
    sub = p.add_subparsers(dest="command", required=True)

    sp = sub.add_parser("json-get", help="Read a value at a dotted path from a JSON file.")
    sp.add_argument("file")
    sp.add_argument("path")
    sp.add_argument("--default", default="", help="printed when the file/key is absent")
    sp.add_argument("--type", choices=["auto", "bool", "lines"], default="auto")
    sp.set_defaults(func=cmd_json_get)

    sp = sub.add_parser(
        "json-set", help="Set a value at a dotted path in a JSON file (creates file/parents)."
    )
    sp.add_argument("file")
    sp.add_argument("path")
    sp.add_argument("value", help="JSON-encoded value, e.g. '\"text\"', '42', 'true', '{}'")
    sp.add_argument("--raw", action="store_true", help="treat VALUE as a literal string")
    sp.set_defaults(func=cmd_json_set)

    sp = sub.add_parser(
        "json-list-append",
        help="Append an object to a list at a dotted path; upsert if --key matches.",
    )
    sp.add_argument("file")
    sp.add_argument("path")
    sp.add_argument("value", help="JSON-encoded object to append")
    sp.add_argument("--key", default="", help="dedupe field: replace an item whose field matches")
    sp.set_defaults(func=cmd_json_list_append)

    sp = sub.add_parser("json-keys", help="List the keys of the object at a dotted path.")
    sp.add_argument("file")
    sp.add_argument("path")
    sp.set_defaults(func=cmd_json_keys)

    sp = sub.add_parser(
        "extract-json-block", help="Extract the Nth fenced ```json block from a markdown file."
    )
    sp.add_argument("file")
    sp.add_argument("--index", type=int, default=0)
    sp.add_argument("--validate", action="store_true", help="also parse the block as JSON")
    sp.set_defaults(func=cmd_extract_json_block)

    sp = sub.add_parser("parse-headings", help="Parse ATX markdown headings into a JSON section list.")
    sp.add_argument("file")
    sp.set_defaults(func=cmd_parse_headings)

    sp = sub.add_parser(
        "count-lines", help="Count content lines, excluding fenced code blocks and HTML comments."
    )
    sp.add_argument("file")
    sp.set_defaults(func=cmd_count_lines)

    sp = sub.add_parser(
        "tasks-list", help="Parse tasks.md into a JSON array of {id,title,status,verify,line}."
    )
    sp.add_argument("file")
    sp.set_defaults(func=cmd_tasks_list)

    sp = sub.add_parser("tasks-set", help="Set one task's status in tasks.md, in place.")
    sp.add_argument("file")
    sp.add_argument("id")
    sp.add_argument("status", choices=list(STATUS_CHOICES))
    sp.set_defaults(func=cmd_tasks_set)

    sp = sub.add_parser(
        "topo-sort",
        help="Topologically sort a dependency graph (JSON object: node -> [deps]).",
    )
    sp.add_argument("--file", default="", help="read graph JSON from a file instead of stdin")
    sp.set_defaults(func=cmd_topo_sort)

    return p


def main(argv: List[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
