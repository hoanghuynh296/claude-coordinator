#!/usr/bin/env python3
"""Merge the kit's lean agent tool set into a project .claude/settings.json.

Usage: lean-tools.py <agent-tools.json> <settings.json> "<groups to keep>"

Every group of agent-tools.json that is not kept is turned off; a kept group is turned back on.
Only the entries the catalog lists are touched (permissions.deny rules, skillOverrides set to
"off", enabledPlugins set to false, boolean settings set to true); every other key and value in
the file is kept as it is. A re-run with the same groups changes nothing. Called by
install-guards.sh --tools.
"""
import json
import os
import sys


def fail(msg):
    sys.stderr.write("lean-tools: %s\n" % msg)
    sys.exit(1)


def main():
    if len(sys.argv) != 4:
        fail("usage: lean-tools.py <agent-tools.json> <settings.json> \"<groups to keep>\"")
    catalog_path, settings_path, keep_arg = sys.argv[1:]
    with open(catalog_path) as f:
        groups = json.load(f)["groups"]
    keep = [g for g in keep_arg.replace(",", " ").split() if g != "none"]
    unknown = [g for g in keep if g not in groups]
    if unknown:
        fail("unknown tool group(s): %s (known: %s)" % (" ".join(unknown), " ".join(groups)))

    settings = {}
    if os.path.exists(settings_path):
        try:
            with open(settings_path) as f:
                text = f.read()
            settings = json.loads(text) if text.strip() else {}
        except ValueError as e:
            fail("%s is not valid JSON (%s); fix it first, nothing written" % (settings_path, e))
        if not isinstance(settings, dict):
            fail("%s is not a JSON object; nothing written" % settings_path)
    before = json.dumps(settings, sort_keys=True)

    off = [g for g in groups if g not in keep]

    def collect(names, field):
        out = []
        for g in names:
            for item in groups[g].get(field, []):
                if item not in out:
                    out.append(item)
        return out

    # permissions.deny: drop the catalog's rules for kept groups, add the ones for groups off.
    owned = set(collect(groups, "deny"))
    want = collect(off, "deny")
    perms = settings.get("permissions")
    if perms is None:
        perms = {}
    if not isinstance(perms, dict):
        fail("permissions in %s is not an object; nothing written" % settings_path)
    deny = perms.get("deny", [])
    if not isinstance(deny, list):
        fail("permissions.deny in %s is not a list; nothing written" % settings_path)
    deny = [r for r in deny if r not in owned or r in want]
    deny += [r for r in want if r not in deny]
    if deny:
        perms["deny"] = deny
    else:
        perms.pop("deny", None)
    if perms:
        settings["permissions"] = perms
    else:
        settings.pop("permissions", None)

    def merge_map(key, field, off_value):
        cur = settings.get(key)
        if cur is None:
            cur = {}
        if not isinstance(cur, dict):
            fail("%s in %s is not an object; nothing written" % (key, settings_path))
        want_off = set(collect(off, field))
        for name in collect(groups, field):
            if name in want_off:
                cur[name] = off_value
            elif cur.get(name) == off_value:
                del cur[name]
        if cur:
            settings[key] = cur
        else:
            settings.pop(key, None)

    merge_map("skillOverrides", "skillsOff", "off")
    merge_map("enabledPlugins", "pluginsOff", False)

    want_on = set(collect(off, "settingsOn"))
    for name in collect(groups, "settingsOn"):
        if name in want_on:
            settings[name] = True
        elif settings.get(name) is True:
            del settings[name]

    if json.dumps(settings, sort_keys=True) == before and (os.path.exists(settings_path) or not settings):
        print("unchanged")
        return
    os.makedirs(os.path.dirname(settings_path) or ".", exist_ok=True)
    tmp = settings_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.replace(tmp, settings_path)
    print("written")


if __name__ == "__main__":
    main()
