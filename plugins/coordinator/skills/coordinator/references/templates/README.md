# {{PROJECT_NAME}}: coordinator state

Everything a coordinator session needs to continue, on this machine or another one.

## Read in this order

1. `../COORDINATION.md`: live state.
2. `PROFILE.md`: how this project runs (units, flow, gates, owner rules).
3. `ROADMAP.md`: what comes next, per unit; verification debt.
4. `handover/coordinator.md`: what the last coordinator session had in flight (if present).
5. `DECISIONS.md`: when you need to know why.
6. `memory/*.md`: the owner's preferences; copy into this machine's Claude memory folder.

Then register the session: `/coordinator:coordinator-register`.

## Units and repos

| Unit | Folder | Repo | Integration / release branch |
|---|---|---|---|
| <unit> | `<products/unit or ../repo>` | <https://github.com/owner/repo> | <develop / main> |

Clone them into exactly these folders, then check out the integration branch.

## Set-up notes

<Ports, required tools, how builds run (for example a self-hosted runner), what must stay
online. Nothing specific to one machine: no home paths, no local auth workarounds.>
