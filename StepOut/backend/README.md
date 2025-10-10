# StepOut Backend

This directory holds the Firebase backend scaffolding used by the StepOut iOS
app. It is intentionally lightweight so you can run everything against the
Firebase Emulator Suite while Apple-specific requirements are still pending.

## Structure

```
backend/
 ├─ firebase.json          # Emulator + deploy targets
 ├─ firestore.rules        # Firestore security rules
 ├─ storage.rules          # Storage security rules
 └─ functions/             # Cloud Functions (TypeScript)
     ├─ package.json
     ├─ tsconfig.json
     └─ src/
         ├─ index.ts       # Function entrypoints
         ├─ schema.ts      # Shared types & converters
         └─ validators.ts  # Request validation helpers
```

## Prerequisites

- Node.js 18+
- Firebase CLI (`npm i -g firebase-tools`)
- A Firebase project (or just use the emulator)

## Getting started

```bash
cd backend/functions
npm install
cd ..
firebase emulators:start
```

Then point the iOS app at the emulator by enabling the debug flag in
`FirebaseDebugSettings.swift` (to be added) or by using the default host/port.

## Deploy (once ready)

```bash
firebase deploy --only functions,firestore:rules,storage:rules
```

See `docs/backend-schema.md` for the Firestore layout that these functions
assume.

## Next steps / TODOs

- Configure the Firebase project ID inside `.firebaserc` (not committed yet) or
  supply `--project` when running the CLI.
- Deploy Firestore indexes via `firestore.indexes.json`:
  ```bash
  firebase deploy --only firestore:indexes --project <your-project-id>
  ```
- Wire the iOS client to call the callable functions (`createEvent`, `listFeed`,
  `rsvpEvent`) or point the app at the emulator for end-to-end testing.
- Seed sample data (optional) with `tools/seed.js`:
  ```bash
  cd tools
  npm install
  FIREBASE_PROJECT_ID=stepout-3db1a node seed.js
  ```
  For emulator seeding, also set `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` before running the script.

## Auth Mode

During development the callable APIs (`listFeed`, `createEvent`, `rsvpEvent`) are temporarily public to simplify end-to-end testing. Firestore rules now allow public reads of events and members. See `TODO.md` for the follow-up tasks to re-enable auth before launch.

## Example calls

```bash
curl -X POST https://us-central1-stepout-3db1a.cloudfunctions.net/createEvent   -H "Content-Type: application/json"   -d '{"data":{"ownerId":"B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942","title":"Test Event","description":"Created from curl","startAt":"2025-10-18T18:00:00Z","endAt":"2025-10-18T20:00:00Z","location":"San Francisco, CA","visibility":"public"}}'
```
