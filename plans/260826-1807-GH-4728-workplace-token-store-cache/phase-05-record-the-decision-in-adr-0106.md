---
phase: 5
title: "Record the decision in ADR 0106"
status: pending
priority: P3
effort: "30m"
dependencies: [4]
---

# Phase 5: Record the decision in ADR 0106

## Overview

ADR 0095 is the only document describing the Drive `token_exchange` flow, and after
Phase 2 it describes a flow the code no longer follows. Record the change as a new
ADR rather than rewriting 0095, so the original integration decision stays legible.

Same numbering as the competing interceptor plan: `0106`. Only the decision list
differs. Do not implement both plans.

## Requirements

- Functional: a new `docs/adr/0106-*.md` capturing what changed and why.
- Non-functional: follow the existing ADR format in `docs/adr/`; no plan-artifact
  references in the text (no phase numbers, no finding codes).

## Architecture

Numbering note: `0103` is currently used twice
(`0103-attach-drive-file-as-attachment.md` and
`0103-urgent-exception-handling-for-riverpod-flows.md`), and the highest number in
use is `0105`. Take `0106` and do not attempt to renumber the existing collision.

## Related Code Files

- Create: `docs/adr/0106-drive-token-exchange-caching-and-prefetch.md`
- Modify: `docs/adr/0095-external-drive-file-picker-integration.md` — one line in its
  token-exchange section pointing forward to 0106. Do not rewrite its decision.

## Implementation Steps

1. Read `docs/adr/0105-attach-drive-file-via-jmap-mediated-upload.md` first to match
   the house format (section headings, status line, tone).

2. Write `0106`. The decisions worth recording, with their reasoning:

   - **Abstract `WorkplaceTokenStore` over a Dio interceptor.** Extension calls
     `obtain` / `recoverAfterUnauthorized` / `prime`. RAM + single-flight live in
     `InMemoryWorkplaceTokenStore`. `token_exchange` and `POST /auth/access_token`
     stay unauthenticated. Refresh is store logic, matching cozy-client `fetchJSON`.
   - **Cache seed is `(platformUrl, oidcIdToken)`.** Invalidation on re-login,
     account switch and OIDC refresh falls out. Cost: an OIDC refresh discards a
     still-valid Drive token.
   - **No TTL.** cozy-stack omits `expires_in`. Cache until Drive returns
     Expired/Invalid token (or HTTP 401).
   - **`recoverAfterUnauthorized` + OAuth refresh grant.** Same-seed joiners share
     one HTTP Future. Prefer `POST /auth/access_token`; fall back to
     `token_exchange`. Write the cache only if that flight is still current.
     Not AppToken `GET /?refreshToken`.
   - **Prime when the keepAlive plugin is constructed**, from
     `ComposerController.onInit` `read`, plus `workplaceUri` null → non-null.
     Not a per-composer warmup widget. Not at login.

3. Mark it as a workaround with an explicit exit condition — persist the OAuth
   client across process death, or drop the fallback exchange if refresh is
   guaranteed.

4. Add the forward pointer in 0095.

## Success Criteria

- [ ] `docs/adr/0106-drive-token-exchange-caching-and-prefetch.md` exists and matches
      the format of the surrounding ADRs.
- [ ] All decisions above are recorded with reasoning, not just outcomes.
- [ ] Its workaround status and exit condition are stated.
- [ ] ADR 0095 points forward to 0106; its original decision is otherwise untouched.
- [ ] No phase numbers, finding codes, or plan paths appear in the ADR text.

## Risk Assessment

- ADR drifts from the code if Phases 1–4 change during implementation. Write this
  phase last, from the merged code, not from the plan.
