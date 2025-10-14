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
  ProfileAttendedPayload,
  ProfileRequestPayload,
  ProfileUpdatePayload,
  RSVPCallPayload,
  ShareEventPayload,
  FriendInvitePayload,
  ListFriendsPayload,
  FriendDoc,
  FriendInviteDoc,
  UserDoc,
  eventDeleteSchema,
  eventSchema,
  eventUpdateSchema,
  profileAttendedSchema,
  profileRequestSchema,
  profileUpdateSchema,
  feedQuerySchema,
  rsvpRequestSchema,
  shareEventSchema,
  friendInviteSchema,
  listFriendsSchema
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

async function fetchAttendedEvents(userId: string, limit: number) {
  const memberSnap = await db
    .collectionGroup("members")
    .where("userId", "==", userId)
    .where("status", "==", "going")
    .get();

  const events = await Promise.all(
    memberSnap.docs.map(async (memberDoc) => {
      const eventRef = memberDoc.ref.parent.parent;
      if (!eventRef) {
        return null;
      }
      const eventSnap = await eventRef.get();
      if (!eventSnap.exists) {
        return null;
      }

      const eventData = eventSnap.data() ?? {};
      const startAt = eventData.startAt instanceof Timestamp ? (eventData.startAt as Timestamp).toDate().toISOString() : null;
      const endAt = eventData.endAt instanceof Timestamp ? (eventData.endAt as Timestamp).toDate().toISOString() : null;

      return {
        eventId: eventSnap.id,
        title: eventData.title ?? "Untitled",
        location: eventData.location ?? "",
        startAt,
        endAt,
        coverImagePath: eventData.coverImagePath ?? null,
        visibility: eventData.visibility ?? "public"
      };
    })
  );

  const filtered = events.filter((value): value is NonNullable<typeof value> => value !== null);
  filtered.sort((a, b) => {
    const aTime = a.startAt ? Date.parse(a.startAt) : 0;
    const bTime = b.startAt ? Date.parse(b.startAt) : 0;
    return bTime - aTime;
  });

  return filtered.slice(0, limit);
}

async function buildProfilePayload(userId: string) {
  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    console.log("[Function] buildProfilePayload no profile found, returning defaults", userId);
    return {
      profile: {
        userId,
        displayName: "Friend",
        username: null,
        bio: null,
        photoURL: null,
        joinDate: null,
        primaryLocation: null,
        stats: {
          hostedCount: 0,
          attendedCount: 0,
          friendCount: 0,
          invitesSent: 0
        }
      },
      friends: [],
      pendingInvites: [],
      attendedEvents: []
    };
  }

  const data = userSnap.data() ?? {};
  const displayName = data.displayName ?? "Friend";
  const username = data.username ?? null;
  const bio = data.bio ?? null;
  const photoURL = data.photoURL ?? null;
  const joinDate = data.createdAt instanceof Timestamp ? (data.createdAt as Timestamp).toDate().toISOString() : null;
  const primaryLocation = data.primaryLocation ?? null;

  const [friendsSnap, outgoingInvitesSnap, incomingInvitesSnap, hostedSnap, attendedEvents] = await Promise.all([
    db.collection("friends").where("userId", "==", userId).where("status", "==", "active").get(),
    db.collection("friendInvites").where("senderId", "==", userId).where("status", "==", "pending").get(),
    db.collection("friendInvites").where("recipientUserId", "==", userId).where("status", "==", "pending").get(),
    db.collection("events").where("ownerId", "==", userId).get(),
    fetchAttendedEvents(userId, 12)
  ]);

  // Fetch friend details
  const friendIds = friendsSnap.docs.map(doc => doc.data().friendId);
  const friendPromises = friendIds.map(async (friendId) => {
    const friendDoc = await db.collection("users").doc(friendId).get();
    if (!friendDoc.exists) return null;
    const friendData = friendDoc.data() ?? {};
    return {
      id: friendId,
      displayName: friendData.displayName ?? "Friend",
      photoURL: friendData.photoURL ?? null,
      status: "on-app"
    };
  });
  const friendsWithDetails = await Promise.all(friendPromises);
  const friends = friendsWithDetails.filter(f => f !== null);

  // Fetch sender details for incoming invites
  const incomingInvitePromises = incomingInvitesSnap.docs.map(async (doc) => {
    const invite = doc.data() ?? {};
    const senderDoc = await db.collection("users").doc(invite.senderId).get();
    const senderData = senderDoc.exists ? senderDoc.data() : null;
    return {
      id: doc.id,
      direction: "received" as const,
      displayName: senderData?.displayName ?? "Friend",
      contact: invite.recipientPhone ?? invite.recipientEmail ?? null
    };
  });

  const pendingInvites = [
    ...outgoingInvitesSnap.docs.map((doc) => {
      const invite = doc.data() ?? {};
      return {
        id: doc.id,
        direction: "sent" as const,
        displayName: invite.recipientPhone ?? invite.recipientEmail ?? "Friend",
        contact: invite.recipientPhone ?? invite.recipientEmail ?? null
      };
    }),
    ...(await Promise.all(incomingInvitePromises))
  ];

  const attendedEventIds = new Set(attendedEvents.map((event) => event.eventId));

  return {
    profile: {
      userId,
      displayName,
      username,
      bio,
      photoURL,
      joinDate,
      primaryLocation,
      stats: {
        hostedCount: hostedSnap.size,
        attendedCount: attendedEventIds.size,
        friendCount: friends.length,
        invitesSent: outgoingInvitesSnap.size
      }
    },
    friends,
    pendingInvites,
    attendedEvents
  };
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
  // Support both authenticated users and explicit userId parameter (for dev/testing without Firebase Auth)
  const authUid = request.auth?.uid ?? (request.data?.userId as string | undefined) ?? null;
  console.log("[Function] listFeed query", request.data, "authUid:", authUid);
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
  // Fetch the user's actual friends from the friends collection
  let friendsList: Array<{ id: string; displayName: string; photoURL: string | null }> = [];

  if (authUid) {
    const friendsQuery = await db.collection("friends")
      .where("userId", "==", authUid)
      .where("status", "==", "active")
      .get();

    const friendIds = friendsQuery.docs.map(doc => (doc.data() as any).friendId);

    const friendPromises = friendIds.map(async (friendId) => {
      const userSnap = await db.collection("users").doc(friendId).get();
      if (!userSnap.exists) return null;
      const userData = userSnap.data() ?? {};
      return {
        id: friendId,
        displayName: userData.displayName ?? "Friend",
        photoURL: userData.photoURL ?? null
      };
    });

    const friendDocs = await Promise.all(friendPromises);
    friendsList = friendDocs.filter((doc): doc is { id: string; displayName: string; photoURL: string | null } => doc !== null);
  }

  // If no friends found or user not authenticated, include attendees as fallback
  if (friendsList.length === 0) {
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
    friendsList = friendDocs.filter((doc): doc is { id: string; displayName: string; photoURL: string | null } => doc !== null);
  }

  return { events, friends: friendsList };
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

export const getProfile = onCall(async (request) => {
  const payload: ProfileRequestPayload = parseRequest(profileRequestSchema, request.data);
  console.log("[Function] getProfile payload", payload);

  try {
    const response = await buildProfilePayload(payload.userId);
    console.log("[Function] getProfile response summary", {
      userId: response.profile.userId,
      friends: response.friends.length,
      pendingInvites: response.pendingInvites.length,
      attendedEvents: response.attendedEvents.length
    });
    return response;
  } catch (error) {
    console.error("[Function] getProfile error", error);
    throw new HttpsError("internal", (error as Error).message ?? "Failed to load profile.");
  }
});

export const updateProfile = onCall(async (request) => {
  const payload: ProfileUpdatePayload = parseRequest(profileUpdateSchema, request.data);
  console.log("[Function] updateProfile payload", payload);

  try {
    const userRef = db.collection("users").doc(payload.userId);
    const userSnap = await userRef.get();

    const updates: Record<string, unknown> = {
      updatedAt: Timestamp.now()
    };

    if (payload.displayName !== undefined) {
      updates.displayName = payload.displayName.trim();
    }
    if (payload.username !== undefined) {
      const normalized = payload.username.toLowerCase();
      const existing = await db.collection("users").where("usernameLowercase", "==", normalized).get();
      const conflict = existing.docs.find((doc) => doc.id !== payload.userId);
      if (conflict) {
        throw new HttpsError("already-exists", "Username already taken.");
      }
      updates.username = payload.username;
      updates.usernameLowercase = normalized;
    }
    if (payload.bio !== undefined) {
      updates.bio = payload.bio ?? null;
    }
    if (payload.primaryLocation !== undefined) {
      updates.primaryLocation = payload.primaryLocation ?? null;
    }
    if (payload.photoURL !== undefined) {
      updates.photoURL = payload.photoURL ?? null;
    }

    if (!userSnap.exists) {
      updates.createdAt = Timestamp.now();
    }

    await userRef.set(updates, { merge: true });

    const response = await buildProfilePayload(payload.userId);
    console.log("[Function] updateProfile response summary", {
      userId: response.profile.userId,
      friends: response.friends.length,
      pendingInvites: response.pendingInvites.length,
      attendedEvents: response.attendedEvents.length
    });
    return response;
  } catch (error) {
    console.error("[Function] updateProfile error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to update profile.");
  }
});

export const listAttendedEvents = onCall(async (request) => {
  const rawPayload = parseRequest(profileAttendedSchema, request.data);
  const payload: ProfileAttendedPayload = {
    userId: rawPayload.userId,
    limit: rawPayload.limit ?? 25
  };
  console.log("[Function] listAttendedEvents payload", payload);

  try {
    const events = await fetchAttendedEvents(payload.userId, payload.limit);
    console.log("[Function] listAttendedEvents returning", { count: events.length });
    return { events };
  } catch (error) {
    console.error("[Function] listAttendedEvents error", error);
    throw new HttpsError("internal", (error as Error).message ?? "Failed to fetch events.");
  }
});

// ===========================
// Social APIs
// ===========================

export const shareEvent = onCall(async (request) => {
  const payload = parseRequest(shareEventSchema, request.data);
  console.log("[Function] shareEvent payload", payload);

  try {
    // Verify event exists
    const eventRef = db.collection("events").doc(payload.eventId);
    const eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found");
    }

    // Get current sharedInviteFriendIds
    const eventData = eventSnap.data();
    const currentShared = (eventData?.sharedInviteFriendIds as string[]) || [];

    // Merge with new recipients (deduplicate)
    const updatedShared = Array.from(new Set([...currentShared, ...payload.recipientIds]));

    // Update event with new shared list
    await eventRef.update({
      sharedInviteFriendIds: updatedShared,
      updatedAt: Timestamp.now()
    });

    console.log("[Function] shareEvent success", {
      eventId: payload.eventId,
      newRecipients: payload.recipientIds.length,
      totalShared: updatedShared.length
    });

    return {
      eventId: payload.eventId,
      sharedWith: updatedShared.length
    };
  } catch (error) {
    console.error("[Function] shareEvent error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", (error as Error).message ?? "Failed to share event.");
  }
});

export const sendFriendInvite = onCall(async (request) => {
  const payload = parseRequest(friendInviteSchema, request.data);
  console.log("[Function] sendFriendInvite payload", payload);

  try {
    // Verify sender exists
    const senderRef = db.collection("users").doc(payload.senderId);
    const senderSnap = await senderRef.get();
    if (!senderSnap.exists) {
      throw new HttpsError("not-found", "Sender not found");
    }

    // Check if recipient already has an account
    let recipientUserId: string | null = null;
    if (payload.recipientPhone) {
      const userQuery = await db.collection("users")
        .where("phoneNumber", "==", payload.recipientPhone)
        .limit(1)
        .get();
      if (!userQuery.empty) {
        recipientUserId = userQuery.docs[0].id;
      }
    } else if (payload.recipientEmail) {
      const userQuery = await db.collection("users")
        .where("email", "==", payload.recipientEmail)
        .limit(1)
        .get();
      if (!userQuery.empty) {
        recipientUserId = userQuery.docs[0].id;
      }
    }

    // Create invite document
    const inviteRef = db.collection("friendInvites").doc();
    const inviteData: FriendInviteDoc = {
      senderId: payload.senderId,
      recipientPhone: payload.recipientPhone || null,
      recipientEmail: payload.recipientEmail || null,
      recipientUserId: recipientUserId,
      status: "pending",
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now()
    };

    await inviteRef.set(inviteData);

    console.log("[Function] sendFriendInvite success", {
      inviteId: inviteRef.id,
      foundExistingUser: !!recipientUserId
    });

    return {
      inviteId: inviteRef.id,
      recipientUserId: recipientUserId
    };
  } catch (error) {
    console.error("[Function] sendFriendInvite error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", (error as Error).message ?? "Failed to send friend invite.");
  }
});

export const listFriends = onCall(async (request) => {
  const payload = parseRequest(listFriendsSchema, request.data);
  console.log("[Function] listFriends payload", payload);

  try {
    // Fetch active friends
    const friendsQuery = await db.collection("friends")
      .where("userId", "==", payload.userId)
      .where("status", "==", "active")
      .get();

    const friendIds = friendsQuery.docs.map(doc => (doc.data() as FriendDoc).friendId);

    // Fetch friend user details
    const friends = await Promise.all(
      friendIds.map(async (friendId) => {
        const userSnap = await db.collection("users").doc(friendId).get();
        if (!userSnap.exists) return null;
        const userData = userSnap.data() as UserDoc;
        return {
          id: friendId,
          displayName: userData.displayName,
          photoURL: userData.photoURL || null
        };
      })
    );

    const validFriends = friends.filter(f => f !== null);

    // Optionally fetch pending invites
    let pendingInvites: Array<{
      id: string;
      displayName: string;
      direction: "sent" | "received";
      contact: string | null;
    }> = [];

    if (payload.includeInvites) {
      // Sent invites
      const sentQuery = await db.collection("friendInvites")
        .where("senderId", "==", payload.userId)
        .where("status", "==", "pending")
        .get();

      // Received invites
      const receivedQuery = await db.collection("friendInvites")
        .where("recipientUserId", "==", payload.userId)
        .where("status", "==", "pending")
        .get();

      const sentInvites = await Promise.all(
        sentQuery.docs.map(async (doc) => {
          const data = doc.data() as FriendInviteDoc;
          return {
            id: doc.id,
            displayName: data.recipientPhone || data.recipientEmail || "Unknown",
            direction: "sent" as const,
            contact: data.recipientPhone || data.recipientEmail || null
          };
        })
      );

      const receivedInvites = await Promise.all(
        receivedQuery.docs.map(async (doc) => {
          const data = doc.data() as FriendInviteDoc;
          const senderSnap = await db.collection("users").doc(data.senderId).get();
          const senderData = senderSnap.exists ? (senderSnap.data() as UserDoc) : null;
          return {
            id: doc.id,
            displayName: senderData?.displayName || "Unknown",
            direction: "received" as const,
            contact: data.recipientPhone || data.recipientEmail || null
          };
        })
      );

      pendingInvites = [...sentInvites, ...receivedInvites];
    }

    console.log("[Function] listFriends success", {
      friendCount: validFriends.length,
      inviteCount: pendingInvites.length
    });

    return {
      friends: validFriends,
      pendingInvites: pendingInvites
    };
  } catch (error) {
    console.error("[Function] listFriends error", error);
    throw new HttpsError("internal", (error as Error).message ?? "Failed to fetch friends.");
  }
});
