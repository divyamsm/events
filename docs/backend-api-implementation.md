# Backend API Implementation Notes

This document tracks the callable Cloud Functions that still need to be exposed
to support the StepOut iOS app. The existing surface already covers
`createEvent`, `listFeed`, and `rsvpEvent`. The next milestones are the edit and
delete flows so hosts can manage their events from the app.

Auth is intentionally deferred (see `backend/TODO.md`). Every function described
here must accept unauthenticated requests for now; once the full auth flow is
ready we will re-enable enforcement.

---

## `updateEvent`

**Type:** HTTPS callable (`onCall`)  
**Path:** `https://<region>-<project>.cloudfunctions.net/updateEvent`

### Request

```jsonc
{
  "eventId": "UUID string",
  "title": "New title",                  // optional
  "description": "Plain text or markdown", // optional
  "startAt": "ISO-8601 datetime",        // optional
  "endAt": "ISO-8601 datetime",          // optional, must be > startAt
  "location": "Display address",         // optional
  "visibility": "public" | "invite-only",// optional
  "maxGuests": 120,                      // optional, null => unlimited
  "geo": { "lat": 37.7749, "lng": -122.4194 }, // optional
  "coverImagePath": "event-media/<eventId>/cover.jpg", // optional
  "sharedInviteFriendIds": ["UUID", ...] // optional, defaults to existing list
}
```

**Validation:**
- `eventId` required; must resolve to an existing Firestore document
  (`events/{eventId}`).
- At least one mutable field must be provided.
- `startAt` / `endAt` must both be present when updating the schedule; `endAt`
  must be strictly later than `startAt`.
- `geo` requires both latitude and longitude and must fall within valid ranges.
- `maxGuests` must be positive.

### Behaviour
- Load `events/{eventId}`; return `not-found` if missing.
- Build an update object that only includes provided fields.
- Update `updatedAt` with `Timestamp.now()`.
- When `sharedInviteFriendIds` is supplied, overwrite the stored value with the
  de-duplicated list.
- Persist with `merge: true` so unspecified fields remain untouched.

### Response

```json
{ "eventId": "<stored event document ID>" }
```

Return the stored document ID (new events use uppercase UUID strings). No payload on failure; rely on
standard `HttpsError` codes (`invalid-argument`, `not-found`, `internal`).

---

## `deleteEvent`

**Type:** HTTPS callable (`onCall`)  
**Path:** `https://<region>-<project>.cloudfunctions.net/deleteEvent`

### Request

```jsonc
{
  "eventId": "UUID string",
  "hardDelete": false // optional (default false)
}
```

### Behaviour

- Grab `events/{eventId}`; `not-found` if it does not exist.
- When `hardDelete` is truthy:
  - Delete the event document.
  - Delete the entire `events/{eventId}/members` subcollection.
  - (Future: remove cover image assets from Storage.)
- When `hardDelete` is false (default):
  - Update the doc with `canceled: true`, `updatedAt: Timestamp.now()`.
  - Leave member docs intact.

The callable should return `{ "eventId": "<event document ID>", "hardDelete": false }`.

### Considerations

- Soft cancel keeps the event around for auditing and allows clients to filter.
- We will re-check authorization when auth is restored; for now everything
  remains public per the TODO list.

---

## Follow-up

- Update `functions/src/schema.ts` with zod schemas for the new requests.
- Wire entry points in `functions/src/index.ts`.
- Add integration tests (emulator-based) once the testing harness is in place.
- Extend the iOS `FirebaseEventBackend` to call the new functions.
