# Drive Iframe POC — Local-First Implementation Plan

## Goal
Add "Attach from Drive" button to TMail Flutter composer (web) that opens an iframe with a simulated Drive file picker. The picker returns file metadata (name, size, contentType, link) via `postMessage`. Runs locally with `fvm flutter run`.

## Scope
- **Use Case A only** — Attach a file from Drive into mail (simplified)
- **No Docker** — local dev, Drive picker served by a simple static file server
- **No backend token service** — POC focuses on iframe ↔ Flutter postMessage communication
- **Web only** — iframe is a web-only concept

## Architecture

```
┌─────────────────────────────────────────────┐
│  TMail Flutter Web (localhost:port)         │
│                                             │
│  Composer Bottom Bar                        │
│  ┌──────┐ ┌──────┐ ┌──────────────┐       │
│  │Attach│ │Image │ │Attach from   │       │
│  │File  │ │      │ │Drive (NEW)   │       │
│  └──────┘ └──────┘ └──────┬───────┘       │
│                           │                 │
│              ┌────────────▼──────────┐     │
│              │  Dialog/Overlay       │     │
│              │  ┌──────────────────┐ │     │
│              │  │ IFrame           │ │     │
│              │  │ (Drive Picker)   │ │     │
│              │  │ localhost:8081   │ │     │
│              │  └──────────────────┘ │     │
│              └───────────────────────┘     │
│                                             │
│  postMessage listener ◄── file-selected     │
│  { name, size, contentType, link }          │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Drive Picker (static HTML/JS)              │
│  Served at localhost:8081                   │
│                                             │
│  - Shows fake file list                     │
│  - User clicks a file                       │
│  - Sends postMessage to parent:             │
│    { type: "file-selected",                 │
│      metadata: { name, size, contentType }, │
│      contentUrl: "https://..." }            │
│  - Validates event.origin                   │
└─────────────────────────────────────────────┘
```

## Phases

| # | Phase | Status | Effort |
|---|-------|--------|--------|
| 1 | [Drive Picker Static App](phase-01-drive-picker-static-app.md) | TODO | Small |
| 2 | [Flutter Iframe Widget + postMessage Bridge](phase-02-flutter-iframe-bridge.md) | TODO | Medium |
| 3 | [Composer Integration](phase-03-composer-integration.md) | TODO | Medium |

## Key Constraints (from RFC docs)
- **Origin validation**: Both sides MUST validate `event.origin`
- **postMessage for metadata**: JSON with `type` field
- **Platform-injected URL**: Drive picker URL configurable (env/config)
- **CSP**: `frame-ancestors` on Drive picker, iframe-src restriction on TMail side

## Key Codebase Integration Points
- `BottomBarComposerWidget` — add new button after attach/image buttons
- `ComposerController` — add method to open Drive picker dialog
- `HtmlElementView.fromTagName(tagName: 'iframe')` — existing pattern in `html_content_viewer_on_web_widget.dart`
- `universal_html` package — already used for HTML element manipulation
- `window.addEventListener('message', ...)` — existing postMessage pattern in `HtmlInteraction`

## Out of Scope
- Use Cases B (insert link) and C (save to drive)
- Docker Compose setup
- Backend token generation
- Real Drive API integration
- Mobile/tablet support (web only)
- File download/binary transfer
