#!/usr/bin/env python3
"""Merge the kit's lean agent tool set into a project .claude/settings.json.

Usage: lean-tools.py <agent-tools.json> <settings.json> "<groups to keep>"

Every group of agent-tools.json that is not kept is turned off; a kept group is turned back on.
The script records exactly what it added in lean-tools.lock.json next to settings.json (commit
both) and only ever removes those entries. An entry that was already there before (a deny rule,
a skill override, a plugin setting, a boolean setting) is never removed or overwritten: an
identical one is left alone, a different value (for example a skill set to "name-only") is
kept with a warning. A re-run with the same groups changes nothing. Called by
install-guards.sh --tools.
"""
import json
import os
import stat
import sys
import tempfile

LOCK_NAME = "lean-tools.lock.json"
# lock section -> (catalog field, value the kit writes)
KINDS = (
    ("deny", "deny", None),
    ("skillOverrides", "skillsOff", "off"),
    ("enabledPlugins", "pluginsOff", False),
    ("settings", "settingsOn", True),
)


def fail(msg):
    sys.stderr.write("lean-tools: %s\n" % msg)
    sys.exit(1)


def warn(msg):
    sys.stderr.write("lean-tools: warning: %s\n" % msg)


def load_json(path, what):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        data = json.loads(text) if text.strip() else {}
    except ValueError as e:
        fail("%s is not valid JSON (%s); fix it first, nothing written" % (path, e))
    if not isinstance(data, dict):
        fail("%s is not a JSON object; nothing written" % path)
    return data


def write_json(path, data):
    """Write atomically to path (a symlink is resolved and its target written)."""
    target = os.path.realpath(path)
    folder = os.path.dirname(target) or "."
    os.makedirs(folder, exist_ok=True)
    mode = stat.S_IMODE(os.stat(target).st_mode) if os.path.exists(target) else 0o644
    fd, tmp = tempfile.mkstemp(prefix=".lean-tools.", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(tmp, mode)
        os.replace(tmp, target)
        tmp = None
    finally:
        if tmp is not None and os.path.exists(tmp):
            os.unlink(tmp)


def remove_file(path):
    target = os.path.realpath(path)
    if os.path.exists(target):
        os.unlink(target)


def main():
    if len(sys.argv) != 4:
        fail("usage: lean-tools.py <agent-tools.json> <settings.json> \"<groups to keep>\"")
    catalog_path, settings_path, keep_arg = sys.argv[1:]
    with open(catalog_path, encoding="utf-8") as f:
        groups = json.load(f)["groups"]
    keep = [g for g in keep_arg.replace(",", " ").split() if g != "none"]
    unknown = [g for g in keep if g not in groups]
    if unknown:
        fail("unknown tool group(s): %s (known: %s)" % (" ".join(unknown), " ".join(groups)))
    lock_path = os.path.join(os.path.dirname(settings_path) or ".", LOCK_NAME)

    settings = load_json(settings_path, "settings")
    lock = load_json(lock_path, "lock")
    before = (json.dumps(settings, sort_keys=True), json.dumps(lock, sort_keys=True))
    off = [g for g in groups if g not in keep]

    def collect(names, field):
        out = []
        for g in names:
            for item in groups[g].get(field, []):
                if item not in out:
                    out.append(item)
        return out

    def container(kind):
        """The dict or list in settings that holds entries of this kind (created on demand)."""
        if kind == "deny":
            perms = settings.get("permissions", {})
            if not isinstance(perms, dict):
                fail("permissions in %s is not an object; nothing written" % settings_path)
            deny = perms.get("deny", [])
            if not isinstance(deny, list):
                fail("permissions.deny in %s is not a list; nothing written" % settings_path)
            return perms, deny
        if kind == "settings":
            return None, settings
        cur = settings.get(kind, {})
        if not isinstance(cur, dict):
            fail("%s in %s is not an object; nothing written" % (kind, settings_path))
        return None, cur

    new_lock = {}
    for kind, field, value in KINDS:
        owned = lock.get(kind, [])
        if not isinstance(owned, list):
            fail("%s in %s is not a list; nothing written" % (kind, lock_path))
        want = collect(off, field)
        perms, cur = container(kind)
        mine = []
        for name in collect(groups, field) + [n for n in owned if n not in collect(groups, field)]:
            was_mine = name in owned
            if kind == "deny":
                present = name in cur
                same = present
            else:
                present = name in cur
                same = present and cur[name] == value
            if name in want:
                if not present:
                    if kind == "deny":
                        cur.append(name)
                    else:
                        cur[name] = value
                    mine.append(name)
                elif same:
                    if was_mine:
                        mine.append(name)
                else:
                    warn("%s %r is %r in %s; kept (the kit would set %r)"
                         % (kind, name, cur[name], settings_path, value))
            elif was_mine and same:
                if kind == "deny":
                    cur.remove(name)
                else:
                    del cur[name]
        if mine:
            new_lock[kind] = mine
        if kind == "deny":
            if cur:
                perms["deny"] = cur
            else:
                perms.pop("deny", None)
            if perms:
                settings["permissions"] = perms
            else:
                settings.pop("permissions", None)
        elif kind != "settings":
            if cur:
                settings[kind] = cur
            else:
                settings.pop(kind, None)

    after = (json.dumps(settings, sort_keys=True), json.dumps(new_lock, sort_keys=True))
    if after == before and (os.path.exists(settings_path) or not settings):
        print("unchanged")
        return
    if settings or os.path.exists(settings_path):
        write_json(settings_path, settings)
    if new_lock:
        write_json(lock_path, new_lock)
    else:
        remove_file(lock_path)
    print("written")


if __name__ == "__main__":
    main()
