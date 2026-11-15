# Review checklist

Used by the Reviewer subagent and by the coordinator's own skim. Report only real findings,
ranked by severity (high / medium / low), each with file:line and a concrete fix.

## Security (always for auth, tenancy, money, AI write tools)
- AuthN: every new route/handler requires authentication; no debug bypass; tokens validated
  (signature, expiry, audience); sessions invalidated on logout/password change.
- AuthZ: permission checked server-side on every read and write, not only in the UI; no
  insecure direct object references (IDs from the client checked against the caller).
- Tenancy: every query scoped by tenant; no cross-tenant joins, caches, file paths or queues;
  tenant from the authenticated context, never from the request body.
- Input: validation at the boundary; parameterised queries; no shell/eval with user input;
  file uploads limited and type-checked; SSRF on user-supplied URLs.
- Secrets: none in code, tests, fixtures, logs or error messages.
- Money: integer minor units or decimal, never float; idempotency keys on payments and
  webhooks; webhook signatures verified; amounts and currency from the server.
- AI write tools: the model can only call tools the user may call; destructive actions need
  confirmation; tool arguments validated like user input; prompt injection from data cannot
  escalate privileges; actions logged with the acting user.
- Logging: no PII or secrets; security-relevant events logged.

## Correctness
- Acceptance criteria of the ticket met; edge cases (empty, large, concurrent, error paths).
- Tests exercise the behaviour, including the failure paths; not only the happy path.
- Migrations reversible or safe on existing data; no data loss.
- Contract followed exactly; no silent contract changes.

## Scope
- Diff only touches the ticket's allowed paths and the lane's owned paths.
- No unrelated refactors, no shared/root files unless the PR is Platform's.

## No customer hard-coding
- No design-partner names, domain terms, IDs, URLs, or `if tenant == ...` special cases.
- Variation lives in per-tenant configuration with neutral defaults.
- Fixtures/tests cover at least 3 domains with fictional data.
