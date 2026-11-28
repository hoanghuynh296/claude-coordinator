#!/usr/bin/env python3
"""Merge the kit's lean agent tool set into a project .claude/settings.json.

Usage: lean-tools.py [--adopt-existing] <agent-tools.json> <settings.json> "<groups to keep>"

Every group of agent-tools.json that is not kept is turned off; a kept group is turned back on.
The script records exactly what it added in lean-tools.lock.json next to settings.json (commit
both) and only ever removes those entries. An entry that was already there before (a deny rule,
a skill override, a plugin setting, a boolean setting) is never removed or overwritten: an
identical one is left alone, a different value (for example a skill set to "name-only") is
kept with a warning. A re-run with the same groups changes nothing. Called by
install-guards.sh --tools.

The lock is written before settings.json, and when settings.json cannot be written the old lock
is put back, so the lock always lists every entry the kit added. When the lock is missing but
settings.json already holds entries that match the catalog exactly, they are kept as the
user's and a warning names them: if the lock was lost, --adopt-existing records every exact
catalog match as the kit's (so keeping its group removes it again).

Output contract (both runtimes): stdout is one word, "written" or "unchanged"; warnings go to
stderr as "lean-tools: warning: ..."; on an error stderr says "lean-tools: ..." and the exit
code is 1 with settings.json and the lock as they were.
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


def _write_json(path, data):
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


def write_json(path, data, what):
    try:
        _write_json(path, data)
    except OSError as e:
        raise WriteError("cannot write %s %s (%s)" % (what, path, e.strerror or e))


def remove_file(path):
    target = os.path.realpath(path)
    try:
        if os.path.exists(target):
            os.unlink(target)
    except OSError as e:
        raise WriteError("cannot remove lock %s (%s)" % (path, e.strerror or e))


def read_text(path):
    """The file's text, or None when it does not exist (to put it back after a failed write)."""
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


def restore_text(path, text):
    target = os.path.realpath(path)
    if text is None:
        if os.path.exists(target):
            os.unlink(target)
        return
    with open(target, "w", encoding="utf-8") as f:
        f.write(text)


class WriteError(Exception):
    pass


def main():
    args = sys.argv[1:]
    adopt = "--adopt-existing" in args
    args = [a for a in args if a != "--adopt-existing"]
    if len(args) != 3 or any(a.startswith("--") for a in args):
        fail("usage: lean-tools.py [--adopt-existing] <agent-tools.json> <settings.json> "
             "\"<groups to keep>\"")
    catalog_path, settings_path, keep_arg = args
    with open(catalog_path, encoding="utf-8") as f:
        groups = json.load(f)["groups"]
    keep = [g for g in keep_arg.replace(",", " ").split() if g != "none"]
    unknown = [g for g in keep if g not in groups]
    if unknown:
        fail("unknown tool group(s): %s (known: %s)" % (" ".join(unknown), " ".join(groups)))
    lock_path = os.path.join(os.path.dirname(settings_path) or ".", LOCK_NAME)

    settings = load_json(settings_path, "settings")
    lock_missing = not os.path.exists(lock_path)
    lock = load_json(lock_path, "lock")
    old_lock_text = read_text(lock_path)
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
    unowned = []  # exact catalog entries present without a lock
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
            if same and not was_mine and name in collect(groups, field):
                if adopt:
                    was_mine = True
                elif lock_missing:
                    unowned.append("%s %r" % (kind, name))
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

    if unowned:
        warn("%s is missing but %s already holds %d entr%s the kit's catalog sets exactly: %s. "
             "They are kept as yours and never removed. If the kit added them (the lock was "
             "lost), re-run with --adopt-existing (install-guards.sh --tools \"<groups>\" "
             "--adopt-existing <repo>) to record them as the kit's, then commit "
             ".claude/settings.json and %s together"
             % (lock_path, settings_path, len(unowned), "y" if len(unowned) == 1 else "ies",
                ", ".join(unowned[:6]) + (" and %d more" % (len(unowned) - 6)
                                           if len(unowned) > 6 else ""), LOCK_NAME))

    after = (json.dumps(settings, sort_keys=True), json.dumps(new_lock, sort_keys=True))
    if after == before and (os.path.exists(settings_path) or not settings):
        print("unchanged")
        return
    # Lock first: at every moment the lock lists every entry the kit added to settings.json.
    try:
        if new_lock:
            write_json(lock_path, new_lock, "lock")
        else:
            remove_file(lock_path)
    except WriteError as e:
        fail("%s; nothing written" % e)
    if settings or os.path.exists(settings_path):
        try:
            write_json(settings_path, settings, "settings")
        except WriteError as e:
            try:
                restore_text(lock_path, old_lock_text)
            except OSError as e2:
                fail("%s; and the old lock could not be put back (%s): restore %s from git"
                     % (e, e2.strerror or e2, lock_path))
            fail("%s; lock put back, nothing written" % e)
    print("written")


if __name__ == "__main__":
    main()
