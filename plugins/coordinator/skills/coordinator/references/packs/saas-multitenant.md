# Pack: multi-tenant SaaS

Switch on in the profile when the product serves several customers from one deployment,
especially when the first customer is a design partner.

## Rule: no customer hard-coding

The first customer's needs become generic features that are configurable per tenant, with
neutral defaults. No customer names, domain terms, ids, URLs or `if tenant == ...` in code,
seeds, prompts or tests. A hard-coded first customer makes the second customer a rewrite.

- Plans and issues describe the generic feature; the design partner appears by alias only.
- Fixtures and tests use fictional data from at least three domains (for example retail,
  clinic, logistics).

## Reviewer is mandatory for

Auth, sessions, permissions, tenancy and tenant scoping, money and billing, AI tools that
write data, secrets and crypto.

## Checklist (adds to the core checklist)

- **AuthN:** every new route requires authentication; no debug bypass; tokens validated
  (signature, expiry, audience); sessions invalidated on logout and password change.
- **AuthZ:** permission checked on the server for every read and write; ids from the client
  are checked against the caller.
- **Tenancy:** every query scoped by tenant; no cross-tenant joins, caches, file paths or
  queues; the tenant comes from the authenticated context, never from the request body.
- **Input:** parameterised queries; uploads limited and type-checked; SSRF on user-supplied
  URLs.
- **Money:** integer minor units or decimal, never float; idempotency keys on payments and
  webhooks; webhook signatures verified; amounts and currency from the server.
- **AI write tools:** the model can only call tools the user may call; destructive actions
  need confirmation; tool arguments validated like user input; data cannot escalate
  privileges through prompt injection; actions logged with the acting user.
- **Logging:** no PII or secrets; security-relevant events logged.
- **Hard-coding:** no design-partner names, terms or special cases; variation lives in
  per-tenant configuration.

## Usual profile choices

`single-repo` with lanes; Platform and QA switched on; `milestone` cadence with a staging
environment; a contract-first issue (`docs/contracts/`) at the start of each milestone.
