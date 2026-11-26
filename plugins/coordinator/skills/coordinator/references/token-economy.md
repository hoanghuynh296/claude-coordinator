# Token economy

Rules that keep a coordinated project effective while spending fewer tokens. They come from
measuring real sessions (`scripts/token-report.py`) and hold for every project. A project's
own numbers and exceptions go into its profile (section 8, "Token economy"), not here.

## What tokens are spent on

Every model call re-reads the whole context; prompt caching makes a re-read cheap, but not
free, and a cache miss rewrites it in full. So the cost of a session is roughly
**(number of calls) × (context size)**, plus what is written into the context once. In the
first measured project (one release, 13 builders, 13 reviews, one coordinator):

- cache reads were about 70% of the cost; the coordinator alone was 30%, because its context
  grew all day and it made about 750 calls, 1 000 of them polls across all sessions;
- builders were about 63%; three of them paid 1.4–1.6M tokens of cache rewrites each because
  they were resumed after a usage-limit pause;
- the largest single inputs were screenshots and full test-suite logs (0.25–1.3M characters);
- reviews were about 6% and caught a blocking bug in 7 of 13 PRs: they are worth it.

## The rules

1. **Fewer, bigger calls.** Do the work of a step in one script or command: gather what the
   next decision needs, act, and return a summary. Wait for a long command inside that same
   call (a timeout long enough for the build or test), never in a loop of short polls. When
   nothing needs doing, end the turn: a finished background job wakes the session.
2. **Keep big outputs out of the context.** Test runs, builds and API dumps return a summary
   (counts, the failing names, the last lines), never the full log. Measure pages as numbers
   (sizes, colours from computed style); look at a screenshot only when the decision needs
   pixels, and then one, cropped.
3. **Local gate = the affected checks.** An agent runs the unit's fast gate plus the tests of
   what it touched before "PR ready". The full suite is the CI's job; an agent runs it locally
   only when CI cannot (and says so). Never paste a full suite's output.
4. **Never idle past the prompt cache.** A pause longer than the cache lifetime (minutes)
   turns the next call into a full rewrite. Agents never wait for CI (unit brief rule 4); the
   coordinator watches it in the background. A session stopped for hours (a usage limit) is
   resumed only if its context is small (under half its soft threshold); otherwise a fresh
   agent gets the PR link and a short brief.
5. **Brief what is already known.** The brief has a "Known" section: flaky tests and how to
   treat them, tool limits (for example, `gh` cannot upload images: put numbers and local
   paths in the PR instead), ports, accounts, the local test commands. An agent should never
   rediscover what the coordinator knew.
6. **Pre-flight before fan-out.** Before starting several agents, check once that one of them
   can do the riskiest step (write in its worktree, push, open a PR). A guard or permission
   that blocks every agent wastes every brief.
7. **Mechanical work is a script.** A change applied the same way to many files (an
   attribute on every component, a rename) is a codemod in one PR, written and run by one
   agent, not hand edits.
8. **Model by task type.** The profile names a model per kind of task: the strongest model for
   behaviour, layout, contracts and anything a reviewer must catch; a cheaper one for
   re-reviews of small fix commits, release bumps, generated docs, codemods and probes.
9. **Review where it pays.** The independent Reviewer stays mandatory where the profile says
   so. A small fix commit after review is checked by the coordinator from its diff (and the
   CI) unless it touches a risk area; then the Reviewer re-reviews only that range.
10. **Rotate before it gets expensive.** The coordinator's context is re-read on every call, so
    it rotates at its soft threshold (handover), not when it is full. One working day or one
    release per coordinator session is a good default.
11. **Measure and improve.** Run the token audit (`references/procedures/token-audit.md`) at
    every release or milestone close, and whenever a session feels slow or costly. A pattern
    that holds beyond the project becomes a rule here; the rest goes into the profile.
