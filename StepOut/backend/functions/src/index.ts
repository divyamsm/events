import * as admin from "firebase-admin";
import { DocumentData, DocumentReference, DocumentSnapshot, Timestamp } from "firebase-admin/firestore";
import { randomUUID } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { CallableRequest } from "firebase-functions/v2/https";
import {
  EventCreatePayload,
  EventDeletePayload,
  EventUpdatePayload,
  FeedQuery,
  RSVPCallPayload,
  eventDeleteSchema,
  eventSchema,
  eventUpdateSchema,
  feedQuerySchema,
  rsvpRequestSchema
} from "./schema";
import { parseRequest } from "./validators";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

function requireAuth<T>(request: CallableRequest<T>): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  return uid;
}

async function resolveEventDocument(
  eventId: string,
  variants: string[] = []
): Promise<{ ref: DocumentReference<DocumentData>; snap: DocumentSnapshot<DocumentData>; canonicalId: string }> {
  const candidateIds = Array.from(new Set([eventId, ...variants, eventId.toUpperCase(), eventId.toLowerCase()]));
  for (const candidateId of candidateIds) {
    const ref = db.collection("events").doc(candidateId);
    const snap = await ref.get();
    if (snap.exists) {
      console.log("[Function] resolveEventDocument hit", { requested: eventId, candidateId, canonicalId: snap.id });
      return { ref, snap, canonicalId: snap.id };
    }
  }
  throw new HttpsError("not-found", "Event does not exist.");
}

export const createEvent = onCall(async (request) => {
  const payload: EventCreatePayload = parseRequest(eventSchema, request.data);
  console.log("[Function] createEvent payload", payload);

  const uid = payload.ownerId ?? request.auth?.uid;
  if (!uid) {
    throw new HttpsError("invalid-argument", "ownerId must be provided.");
  }
  if (payload.endAt <= payload.startAt) {
    throw new HttpsError("invalid-argument", "endAt must be after startAt.");
  }

  const now = Timestamp.now();
  const eventId = randomUUID().toUpperCase();
  const eventRef = db.collection("events").doc(eventId);
  const eventDoc = {
    ownerId: uid,
    title: payload.title,
    description: payload.description ?? null,
    startAt: Timestamp.fromDate(payload.startAt),
    endAt: Timestamp.fromDate(payload.endAt),
    location: payload.location,
    visibility: payload.visibility,
    maxGuests: payload.maxGuests ?? null,
    geo: payload.geo ?? null,
    coverImagePath: payload.coverImagePath ?? null,
    createdAt: now,
    updatedAt: now,
    canceled: false
  };

  const batch = db.batch();
  batch.set(eventRef, eventDoc);
  batch.set(eventRef.collection("members").doc(uid), {
    userId: uid,
    status: "going",
    arrivalAt: null,
    role: "host",
    updatedAt: now
  });

  await batch.commit();
  console.log("[Function] createEvent returning", eventId);
  return { eventId };
});

export const listFeed = onCall(async (request) => {
  const authUid = request.auth?.uid ?? null;
  console.log("[Function] listFeed query", request.data);
  const queryParams = parseRequest(feedQuerySchema, request.data ?? {}) as FeedQuery;

  let query = db
    .collection("events")
    .where("canceled", "==", false)
    .orderBy("startAt", "asc");

  if (queryParams.visibility) {
    query = query.where("visibility", "==", queryParams.visibility);
  }
  if (queryParams.from) {
    query = query.where("startAt", ">=", Timestamp.fromDate(new Date(queryParams.from)));
  }
  if (queryParams.to) {
    query = query.where("startAt", "<=", Timestamp.fromDate(new Date(queryParams.to)));
  }
  if (queryParams.startAfter) {
    const doc = await db.collection("events").doc(queryParams.startAfter).get();
    if (doc.exists) {
      query = query.startAfter(doc);
    }
  }

  const snap = await query.limit(queryParams.limit).get();
  const attendeeIds = new Set<string>();
  const events = await Promise.all(
    snap.docs.map(async (doc) => {
      const data = doc.data();
      const membersSnap = await doc.ref.collection("members").get();

      const attendingFriendIds: string[] = [];
      const arrivalTimes: Record<string, number> = {};
      let attending = false;

      membersSnap.forEach((memberDoc) => {
        const memberData = memberDoc.data();
        const memberId = memberDoc.id;
        const status = memberData.status as string | undefined;
        if (status === "going") {
          attendingFriendIds.push(memberId);
        }
        if (memberData.arrivalAt instanceof Timestamp) {
          arrivalTimes[memberId] = (memberData.arrivalAt as Timestamp).toMillis();
        }
        attendeeIds.add(memberId);
        if (authUid && memberId === authUid && status === "going") {
          attending = true;
        }
      });

      attendeeIds.add(data.ownerId);

      return {
        id: doc.id,
        title: data.title,
        location: data.location,
        startAt: data.startAt instanceof Timestamp ? data.startAt.toMillis() : null,
        endAt: data.endAt instanceof Timestamp ? data.endAt.toMillis() : null,
        coverImagePath: data.coverImagePath ?? null,
        visibility: data.visibility,
        ownerId: data.ownerId,
        attending,
        attendingFriendIds,
        invitedFriendIds: data.invitedFriendIds ?? [],
        sharedInviteFriendIds: data.sharedInviteFriendIds ?? [],
        arrivalTimes,
        geo: data.geo ?? null
      };
    })
  );

  if (authUid) {
    attendeeIds.delete(authUid);
  }
  const friendDocs = await Promise.all(
    Array.from(attendeeIds).map(async (friendId) => {
      const snap = await db.collection("users").doc(friendId).get();
      if (!snap.exists) {
        return null;
      }
      const userData = snap.data() ?? {};
      return {
        id: friendId,
        displayName: userData.displayName ?? "Friend",
        photoURL: userData.photoURL ?? null
      };
    })
  );

  const friends = friendDocs.filter((doc): doc is { id: string; displayName: string; photoURL: string | null } => doc !== null);

  return { events, friends };
});

export const rsvpEvent = onCall(async (request) => {
  const payload = parseRequest(rsvpRequestSchema, request.data) as RSVPCallPayload;
  console.log("[Function] rsvpEvent payload", payload);

  const uid = payload.userId ?? request.auth?.uid;
  if (!uid) {
    throw new HttpsError("invalid-argument", "userId must be provided.");
  }

  const { ref: eventRef, snap: eventSnap } = await resolveEventDocument(payload.eventId, payload.eventIdVariants);

  const now = Timestamp.now();
  await eventRef.collection("members").doc(uid).set(
    {
      userId: uid,
      status: payload.status,
      arrivalAt: payload.arrivalAt ? Timestamp.fromDate(new Date(payload.arrivalAt)) : null,
      role: uid === eventSnap.data()?.ownerId ? "host" : "attendee",
      updatedAt: now
    },
    { merge: true }
  );

  return { ok: true };
});

export const updateEvent = onCall(async (request) => {
  const payload: EventUpdatePayload = parseRequest(eventUpdateSchema, request.data);
  console.log("[Function] updateEvent payload", payload);

  const { ref: eventRef, canonicalId } = await resolveEventDocument(payload.eventId);

  const updates: Record<string, unknown> = {
    updatedAt: Timestamp.now()
  };

  if (payload.title !== undefined) {
    updates.title = payload.title;
  }
  if (payload.description !== undefined) {
    updates.description = payload.description ?? null;
  }
  if (payload.startAt !== undefined && payload.endAt !== undefined) {
    updates.startAt = Timestamp.fromDate(payload.startAt);
    updates.endAt = Timestamp.fromDate(payload.endAt);
  }
  if (payload.location !== undefined) {
    updates.location = payload.location;
  }
  if (payload.visibility !== undefined) {
    updates.visibility = payload.visibility;
  }
  if (payload.maxGuests !== undefined) {
    updates.maxGuests = payload.maxGuests ?? null;
  }
  if (payload.geo !== undefined) {
    updates.geo = payload.geo ?? null;
  }
  if (payload.coverImagePath !== undefined) {
    updates.coverImagePath = payload.coverImagePath ?? null;
  }
  if (payload.sharedInviteFriendIds !== undefined) {
    const normalized = Array.from(new Set(payload.sharedInviteFriendIds.map((id) => id.toUpperCase())));
    updates.sharedInviteFriendIds = normalized;
  }

  console.log("[Function] updateEvent applying", { canonicalId, updates });

  await eventRef.set(updates, { merge: true });
  console.log("[Function] updateEvent wrote", { eventId: canonicalId });
  return { eventId: canonicalId, appliedKeys: Object.keys(updates) };
});

export const deleteEvent = onCall(async (request) => {
  const rawPayload = parseRequest(eventDeleteSchema, request.data);
  const payload: EventDeletePayload = {
    eventId: rawPayload.eventId,
    hardDelete: rawPayload.hardDelete ?? false
  };
  console.log("[Function] deleteEvent payload", payload);

  const { ref: eventRef, canonicalId } = await resolveEventDocument(payload.eventId);
  console.log("[Function] deleteEvent resolved", { eventId: canonicalId, hardDelete: payload.hardDelete });

  if (payload.hardDelete) {
    const membersSnap = await eventRef.collection("members").get();
    const batch = db.batch();
    membersSnap.forEach((memberDoc) => {
      batch.delete(memberDoc.ref);
    });
    batch.delete(eventRef);
    await batch.commit();
    console.log("[Function] deleteEvent hard deleted", { eventId: canonicalId });
    return { eventId: canonicalId, hardDelete: true };
  }

  await eventRef.set(
    {
      canceled: true,
      updatedAt: Timestamp.now()
    },
    { merge: true }
  );
  console.log("[Function] deleteEvent canceled", { eventId: canonicalId });
  return { eventId: canonicalId, hardDelete: false };
});
