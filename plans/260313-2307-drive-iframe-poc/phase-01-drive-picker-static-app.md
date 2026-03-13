# Phase 1 — Drive Picker Static App

## Overview
- **Priority**: High
- **Status**: TODO
- **Description**: Create a minimal static HTML/JS app that simulates a Drive file picker. Served locally, loaded inside TMail's iframe.

## Requirements
- Show a list of fake files with name, size, contentType
- User clicks a file → sends `postMessage` to parent with metadata
- Validate `event.origin` before processing any incoming message
- Listen for `init` message from parent to confirm handshake
- Respond to `cancelled` when user closes without selecting

## File Structure

```
drive-integration-poc/
├── drive-picker/
│   ├── index.html       # File picker UI
│   └── serve.sh         # Simple HTTP server script (python -m http.server 8081)
```

## postMessage Contract

### Incoming (from TMail parent)
```json
{ "type": "init", "mode": "file-picker" }
```

### Outgoing (to TMail parent)
```json
{
  "type": "file-selected",
  "metadata": {
    "name": "report.pdf",
    "size": 1048576,
    "contentType": "application/pdf"
  },
  "contentUrl": "https://drive.example.com/download/file123"
}
```

```json
{ "type": "cancelled" }
```

## Implementation Steps

1. Create `drive-integration-poc/drive-picker/index.html`:
   - HTML page with a styled file list (3-5 hardcoded fake files)
   - Each file row shows: icon, name, size, type
   - Click handler on each file → `window.parent.postMessage(...)` with `TMAIL_ORIGIN` as target
   - "Cancel" button → sends `{ type: "cancelled" }`
   - On load, listen for `message` event, validate `event.origin`, handle `init` message
   - Store `TMAIL_ORIGIN` from URL param or hardcode for POC (`http://localhost:port`)

2. Create `drive-integration-poc/drive-picker/serve.sh`:
   - `python3 -m http.server 8081 --directory .`

## Security
- `event.origin` validation on incoming messages
- Only `postMessage` to specific parent origin (not `"*"`)

## Success Criteria
- [ ] Static page loads at `http://localhost:8081`
- [ ] Clicking a file sends correct postMessage to parent
- [ ] Origin validation works (rejects messages from wrong origin)
- [ ] Cancel button sends cancelled message

## Todo
- [ ] Create index.html with fake file list
- [ ] Add postMessage send on file click
- [ ] Add origin validation on incoming messages
- [ ] Create serve.sh
- [ ] Test manually in browser (open in iframe via browser console)
