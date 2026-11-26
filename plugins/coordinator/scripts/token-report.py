#!/usr/bin/env python3
"""token-report: where did the tokens of a Claude Code coordination session go?

Usage: token-report.py <session.jsonl | project transcript dir> [--top N] [--json]

Reads the session transcript and its subagent transcripts (<session>/subagents/agent-*.jsonl,
with agent-*.meta.json for names), de-duplicates assistant messages by message id, and reports
per session / subagent:
  calls (assistant API calls), input, cache_write, cache_read, output tokens, a weighted
  "cost units" figure (input 1, cache write 1.25, cache read 0.1, output 5 relative weights;
  a ratio for comparing, not a bill), tool calls by tool, and the largest tool results.
Read-only. Python 3 standard library only.
"""
import json, os, sys, glob, collections

W = {"in": 1.0, "cw": 1.25, "cr": 0.1, "out": 5.0}

def load(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                pass
    return rows

def analyse(path, name):
    seen = {}
    tools = collections.Counter()
    big = []
    for r in load(path):
        m = r.get("message") or {}
        if m.get("role") == "assistant" and isinstance(m.get("usage"), dict):
            mid = m.get("id") or r.get("uuid")
            seen[mid] = m["usage"]  # last write wins (streamed duplicates carry the final usage)
        if m.get("role") == "assistant":
            for c in m.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tools[(c.get("name") or "?", c.get("id"))] += 1
        if m.get("role") == "user":
            content = m.get("content") if isinstance(m.get("content"), list) else []
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    body = c.get("content")
                    size = len(json.dumps(body)) if not isinstance(body, str) else len(body)
                    big.append((size, (str(body)[:90]).replace("\n", " ")))
    t = {"in": 0, "cw": 0, "cr": 0, "out": 0}
    for u in seen.values():
        t["in"] += u.get("input_tokens", 0) or 0
        t["cw"] += u.get("cache_creation_input_tokens", 0) or 0
        t["cr"] += u.get("cache_read_input_tokens", 0) or 0
        t["out"] += u.get("output_tokens", 0) or 0
    by_tool = collections.Counter()
    for k in tools:
        if isinstance(k, tuple):
            by_tool[k[0]] += 1
    big.sort(reverse=True)
    units = sum(t[k] * W[k] for k in t)
    return {"name": name, "calls": len(seen), **t, "units": round(units), "tools": dict(by_tool.most_common(8)),
            "biggest_results": [{"chars": s, "head": h} for s, h in big[:5]]}

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    top = 5
    if "--top" in sys.argv:
        top = int(sys.argv[sys.argv.index("--top") + 1])
        args = [a for a in args if a != str(top)]
    if not args:
        print(__doc__); sys.exit(2)
    target = args[0]
    sessions = [target] if target.endswith(".jsonl") else sorted(glob.glob(os.path.join(target, "*.jsonl")))
    report = []
    for s in sessions:
        report.append(analyse(s, "session " + os.path.basename(s)[:8]))
        sub = os.path.join(s[:-6], "subagents")
        for a in sorted(glob.glob(os.path.join(sub, "agent-*.jsonl"))):
            meta = a[:-6] + ".meta.json"
            label = os.path.basename(a)[6:14]
            if os.path.exists(meta):
                try:
                    mj = json.load(open(meta))
                    label = (mj.get("description") or label) + " [" + (mj.get("agentType") or "").split(":")[-1] + ", " + (mj.get("model") or "") + "]"
                except Exception:
                    pass
            report.append(analyse(a, label))
    if "--json" in sys.argv:
        print(json.dumps(report, indent=1)); return
    total = sum(r["units"] for r in report) or 1
    report.sort(key=lambda r: -r["units"])
    print(f"{'share':>6} {'units':>12} {'calls':>6} {'cache_read':>12} {'cache_write':>11} {'output':>8}  name")
    for r in report:
        print(f"{100*r['units']/total:5.1f}% {r['units']:>12,} {r['calls']:>6} {r['cr']:>12,} {r['cw']:>11,} {r['out']:>8,}  {r['name']}")
    print("\nTool calls (all):", dict(sum((collections.Counter(r["tools"]) for r in report), collections.Counter()).most_common(10)))
    print("\nLargest tool results:")
    allbig = sorted(((b["chars"], r["name"], b["head"]) for r in report for b in r["biggest_results"]), reverse=True)[:top]
    for c, n, h in allbig:
        print(f"  {c:>9,} chars  {n[:40]:40}  {h}")

if __name__ == "__main__":
    main()
