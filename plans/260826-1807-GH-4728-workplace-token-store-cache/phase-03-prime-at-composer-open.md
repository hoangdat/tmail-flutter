---
phase: 3
title: "Prime at plugin inject"
status: pending
priority: P1
effort: "1h"
dependencies: [2]
---

# Phase 3: Prime at plugin inject

## Overview

Prime once when the keepAlive `WorkplaceComposerAttachmentExtension` is
**constructed**, not once per composer widget. Force that construct from
`ComposerController.onInit` so native is not stuck on attach-menu. Also prime
when `workplaceUri` goes `null → non-null`. Prime is `token_exchange`. Refresh
stays on Expired `/intents`.

## Requirements

- Functional: first composer `onInit` constructs the plugin and starts one
  exchange; later composers only `read` keepAlive (zero extra exchange); native
  primes at composer open, not attach-menu open. Late fqdn still primes.
- Non-functional: no warmup widget, no `onComposerOpened` on the plugin
  interface, no toast, no `setState`, no side effect in
  `DrivePickerStateMixin.initState`. Do not construct the plugin at login.

## Architecture

The plugin is **lazy**. Today the registry is first watched from:

- Web: `ExternalAttachmentComposerButton` at composer open
- Native: `_pickAttachmentsActionTiles` (attach-menu only — too late)

Constructor prime without a first `read` does not fix native.

Team suggestion, made precise:

1. Prime in the extension constructor + `workplaceUri` listener.
2. `ComposerController.onInit` already exists (`composer_controller.dart` ~333)
   and already uses `appProviderContainer.read`. Add:

   ```dart
   appProviderContainer.read(composerAttachmentExtensionRegistryProvider);
   ```

   First composer: provider runs, constructs the plugin, constructor primes.
   Later composers: keepAlive hit, constructor does not run, no extra exchange.

3. Do **not** watch the registry from mailbox/login. That exchanges for users
   who never compose.

No `ComposerAttachmentWarmupWidget`. No layout-branch pin. No plugin callback.

```dart
WorkplaceComposerAttachmentExtension({...}) {
  workplaceUri.addListener(_primeIfReady);
  _primeIfReady();
}

void _primeIfReady() {
  unawaited(_tokenStore.prime(
    platformUrl: workplaceUri.value,
    oidcIdToken: oidcTokenGetter(),
  ));
}
```

`prime` no-ops on null uri/oidc. Listener covers fqdn arriving after construct.

`oidcTokenGetter` is a GetX getter, not a `ValueListenable`. Typical order is
token then userinfo/fqdn. Residual: uri set and oidc still null — tap-path
`obtain()` still exchanges. Do not poll GetX.

Closing a composer must not drop the session.

## Related Code Files

- Modify: `workplace/lib/presentation/extension/workplace_composer_attachment_extension.dart`
- Modify: `lib/features/composer/presentation/composer_controller.dart`
- Do **not** modify `composer_view.dart` / `composer_view_web.dart` for warmup.
- Do **not** add `onComposerOpened` to `core/.../composer_attachment_plugin.dart`.

## Implementation Steps

1. Constructor: `addListener(_primeIfReady)` then `_primeIfReady()`.

2. `ComposerController.onInit`: `read` the registry provider. Do not `watch`.
   Do not put this in `_injectBinding` (that is autocomplete only).

3. Confirm nothing else constructs a second `WorkplaceComposerAttachmentExtension`.

4. `fvm flutter analyze` on `workplace`, `lib`.

## Success Criteria

- [ ] Native composer open (no attach menu) triggers one `token_exchange`.
- [ ] Web composer `onInit` triggers prime (not only toolbar mount).
- [ ] Second composer `onInit` issues **zero** additional exchanges.
- [ ] `workplaceUri` null at construct, then non-null: `prime` runs; first Drive
      tap is a cache hit.
- [ ] Failed prime: no toast, no zone error; later tap still reports the real
      failure.
- [ ] `DrivePickerSession` and `DrivePickerStateMixin` unchanged.
- [ ] No warmup widget in composer views.

## Risk Assessment

- `read` in `onInit` is the existing GetX + Riverpod pattern (`appProviderContainer`).
- If someone later `watch`es a changing value inside the registry provider, it
  would reconstruct the extension and drop the cache. Today it watches the
  `ValueNotifier` object (`driveAttachmentUriValueProvider`), which is keepAlive
  and stable. Do not switch that `watch` to the uri **value**.
- Wasted exchange if user opens composer and never uses Drive: accepted.
- Login-time inject: rejected. Extra exchanges for non-composers.
