# Hotfix Plan — Friendly Error for Password-Protected PDF (Web, tmail-only)

## Goal
Ship a fast, low-risk hotfix: when a user previews an **encrypted (password-required)**
PDF on web, show a **friendly localized message** instead of pdfrx's raw blue debug box.
No password entry yet — that's the separate full feature
(`../260702-1659-pdf-password-preview-web/`), which supersedes this later.

## Why tmail-only is possible (verified)
- `PreviewerTemplateWidget` is a `switch` on `previewerState`: `success → pdfrx child`,
  `failure → Text(errorMessage)`. pdfrx (`PdfViewer.data`) is **only built on `success`**.
  (`twake .../core/widgets/previewer_template_widget.dart`)
- => If we route encrypted PDFs to `PreviewerState.failure` **before** handing bytes to
  pdfrx, the blue box never renders. **No package change / no ref bump.** Single repo.
- Dismissal already works: in non-success state `TwakePdfPreviewer` falls back to
  `TopBarWidget(closeAction: onClose)`, which always renders a close (back-arrow) button.
  (`twake_pdf_previewer.dart` topBarChild fallback + `top_bar_widget.dart`) — **no barrier/toast change needed.**

## Decisions (confirmed)
- **Approach:** tmail-only byte-sniff for the PDF `/Encrypt` marker → failure state.
  (Alternative — package `errorBannerBuilder` — is more robust for corrupt/unsupported PDFs
  but needs a cross-repo release; deferred to the full plan's Phase 1.)
- **Dismiss UX:** none needed — existing fallback top bar already has a close button.
- **Message copy (confirmed):** EN = "This PDF is password-protected, so it can't be previewed. Download it to open."
  Added via the intl pipeline (getter → `extract_to_arb` → `generate_from_arb`) so it's translatable;
  non-EN locales fall back to the EN default until translated.
- **Branch:** implement directly on `pdf_password` (current branch).
- **Test data:** synthetic byte strings inline in the test — no committed PDF fixture (detector is regex-only, never parses a real PDF).

## Detection
New helper `isEncryptedPdf(Uint8List bytes)`:
- Match `RegExp(r'/Encrypt\s+\d+\s+\d+\s+R')` over `latin1.decode(bytes, allowInvalid: true)`.
- The `/Encrypt` entry is (in practice always) an **indirect ref** `N G R`; this pattern is
  far more specific than a bare `/Encrypt` substring → near-zero false positives.
- Trade-offs: false positive downgrades an openable PDF to the friendly message (annoying,
  rare); false negative (direct-dict `/Encrypt`, very rare) falls back to today's blue box.

## Files
### Create
- `lib/features/email/presentation/widgets/pdf_viewer/pdf_encryption_detector.dart`
  - Top-level `bool isEncryptedPdf(Uint8List bytes)` (small, unit-testable). Descriptive comment on the heuristic + its limits.

### Modify
- `lib/features/download/domain/exceptions/download_attachment_exceptions.dart`
  - Add `EncryptedPdfException extends AppBaseException` (matches existing pattern).
- `lib/features/email/presentation/widgets/pdf_viewer/pdf_viewer.dart`
  - Unify the two success paths (`_initialStreamListener` + interactor `.listen`) into one
    `_handleViewState(Either<Failure,Success>)` (DRY).
  - In it: `if (success is DownloadAttachmentForWebSuccess && isEncryptedPdf(success.bytes))`
    → `_pdfViewStateNotifier.value = DownloadAttachmentForWebFailure(exception: EncryptedPdfException())`;
    else pass `success` through.
  - In `build`, compute `errorMessage` from viewState:
    - `DownloadAttachmentForWebFailure(exception: EncryptedPdfException())` →
      `AppLocalizations.of(context).pdfPasswordProtectedPreviewUnavailable`
    - else → `noPreviewAvailable` (unchanged). Pass into `PreviewerOptions.errorMessage`.
  - Do NOT log the bytes/message content.
- `lib/main/localizations/app_localizations.dart`
  - Add `Intl.message` getter `pdfPasswordProtectedPreviewUnavailable`
    (EN e.g. "This PDF is password-protected, so it can't be previewed. Download it to open.").

### Regenerate (do not hand-edit)
- `./setup_local prod` (or `scripts/prebuild.sh`) to extract ARB + regenerate `messages_*.dart`.

## Implementation Steps
1. Add `isEncryptedPdf` detector file.
2. Add `EncryptedPdfException`.
3. Refactor `pdf_viewer.dart` success handling → `_handleViewState`; add encryption branch + dynamic `errorMessage`.
4. Add l10n getter; run `./setup_local prod`.
5. `fvm flutter analyze` touched files.

## Todo
- [ ] `pdf_encryption_detector.dart` created
- [ ] `EncryptedPdfException` added
- [ ] `pdf_viewer.dart` unified handler + encryption branch + dynamic errorMessage
- [ ] l10n getter + regen (`./setup_local prod`)
- [ ] `fvm flutter analyze` clean

## Testing
- Unit: `test/.../pdf_encryption_detector_test.dart` — uses **inline synthetic byte strings**
  (no committed fixture): encrypted sample bytes containing `/Encrypt 12 0 R` → true;
  plain `%PDF-1.7` bytes with no `/Encrypt` → false; empty/garbage bytes → false.
- Run: `fvm flutter test test/features/email/.../pdf_encryption_detector_test.dart`.
- Manual (web): encrypted PDF → friendly message + close button (no blue box); normal PDF →
  previews as before; close button dismisses.

## Success Criteria
- Encrypted PDF on web → friendly localized message, dismissible, no pdfrx blue box.
- Normal PDF unaffected. Single-repo change, no package/ref bump.

## Handoff to full feature
When `../260702-1659-pdf-password-preview-web/` lands, the encryption branch here is
**replaced** by the password prompt (pdfrx `passwordProvider`). Keep `isEncryptedPdf` only if
still useful as a fast-path; otherwise remove. Note this so the two don't conflict.

## Open Questions
- None — copy confirmed, in-test synthetic bytes (no fixture), branch `pdf_password`.
