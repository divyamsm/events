# Backend Schema Overview

This document captures the initial Firestore data model that the StepOut
experience depends on. It is intentionally scoped to features that can ship
before we integrate Apple-only capabilities (phone auth, APNs).

## Collections

### `users` (collection)
| Field | Type | Notes |
| --- | --- | --- |
| `displayName` | string | User facing name. |
| `phoneNumber` | string? | Optional until phone auth lands. |
| `email` | string? | Present when using email Auth. |
| `photoURL` | string? | HTTPS URL to avatar in Storage. |
| `onboarded` | boolean | Controls default app entry point. |
| `theme` | string | `"system"`, `"light"`, `"dark"`. |
| `interests` | array<string> | Tags used to personalize feeds. |
| `createdAt`, `updatedAt` | timestamp | Server timestamps. |
| `pushTokens` | array<string> | FCM device tokens (future use). |

Security: document owner can read/write; public read is denied.

### `events` (collection)
| Field | Type | Notes |
| --- | --- | --- |
| `ownerId` | reference(`users/{id}`) | Author of the event. |
| `title` | string | 120 char max. |
| `description` | string? | Markdown permitted. |
| `startAt`, `endAt` | timestamp | Calendar window. |
| `location` | string | Display friendly. |
| `geo` | geopoint? | Optional for geo queries. |
| `visibility` | string | `"public"` or `"invite-only"`. |
| `maxGuests` | int? | Null for unlimited. |
| `coverImagePath` | string? | Storage path `event-media/{eventId}/cover.jpg`. |
| `createdAt`, `updatedAt` | timestamp | Server timestamps. |
| `canceled` | boolean | Soft delete toggle. |

### `eventMembers` (collection group)
Documents stored as `events/{eventId}/members/{userId}`.

| Field | Type | Notes |
| --- | --- | --- |
| `userId` | reference(`users/{id}`) | |
| `status` | string | `"going"`, `"interested"`, `"declined"`. |
| `arrivalAt` | timestamp? | Optional arrival ETA. |
| `role` | string | `"host"`, `"attendee"`, `"admin"`. |
| `updatedAt` | timestamp | Server timestamp. |

### `invites` (collection)
Stored as top-level documents to avoid deep queries.

| Field | Type | Notes |
| --- | --- | --- |
| `eventId` | reference(`events/{id}`) | |
| `senderId` | reference(`users/{id}`) | |
| `recipientPhone` | string | Used for SMS/email invites. |
| `recipientUserId` | reference? | Filled once user registers. |
| `status` | string | `"sent"`, `"accepted"`, `"declined"`. |
| `createdAt`, `updatedAt` | timestamp | Server timestamps. |

### `widgetSnapshots` (collection)
| Field | Type | Notes |
| --- | --- | --- |
| `userId` | reference | Owner. |
| `entries` | array<object> | Mirrors `WidgetEventSummary` structure. |
| `generatedAt` | timestamp | Last refresh. |

## Planned Indexes
1. `events` composite index on (`visibility`, `startAt`, `canceled`).
2. `events` composite index on (`ownerId`, `startAt desc`).
3. Collection group `eventMembers`: index on (`userId`, `status`, `updatedAt`).
4. `invites`: single field `eventId`, `recipientPhone`.

## Storage Layout
- `event-media/{eventId}/cover.{jpg|heic|png}` — Event hero images.
- `user-media/{userId}/avatar.jpg` — Profile pictures.

Metadata to embed (as Storage custom metadata):
- `eventId`, `uploadedBy`, `width`, `height`.

---
This schema is flexible enough to power the iOS experience now and can evolve
once phone auth and APNs go live.
