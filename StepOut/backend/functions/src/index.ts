import * as admin from "firebase-admin";
import { DocumentData, DocumentReference, DocumentSnapshot, Timestamp } from "firebase-admin/firestore";
import { randomUUID } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { CallableRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as schema from "./schema";
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
        phoneNumber: null,
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
  const phoneNumber = data.phoneNumber ?? null;
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
      phoneNumber,
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
  // Require authentication - use authenticated user's UID as ownerId
  const uid = requireAuth(request);
  const payload: EventCreatePayload = parseRequest(eventSchema, request.data);
  console.log("[Function] createEvent payload", payload, "authUid:", uid);
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

  // Create chat for the event
  const chatRef = db.collection("chats").doc(eventId);
  const chatDoc: schema.ChatDoc = {
    chatId: eventId,
    eventId: eventId,
    eventTitle: payload.title,
    participantIds: [uid],
    createdAt: now,
    lastMessageAt: null,
    lastMessageText: null,
    lastMessageSenderId: null,
    lastMessageSenderName: null,
    unreadCounts: {}
  };
  batch.set(chatRef, chatDoc);

  await batch.commit();
  console.log("[Function] createEvent returning", eventId);
  return { eventId };
});

export const listFeed = onCall(async (request) => {
  // Require authentication
  const authUid = requireAuth(request);
  console.log("[Function] listFeed query", request.data, "authUid:", authUid);
  const queryParams = parseRequest(feedQuerySchema, request.data ?? {}) as FeedQuery;

  // Fetch user-specific events:
  // 1. Events owned by the user
  // 2. Events user is invited to
  // 3. Public events

  const now = queryParams.from ? Timestamp.fromDate(new Date(queryParams.from)) : Timestamp.now();
  const to = queryParams.to ? Timestamp.fromDate(new Date(queryParams.to)) : null;

  // Query 1: Events owned by user (all events, past and upcoming)
  let ownedQuery = db
    .collection("events")
    .where("canceled", "==", false)
    .where("ownerId", "==", authUid)
    .orderBy("startAt", "desc");

  // Query 2: Public events (all events, past and upcoming)
  let publicQuery = db
    .collection("events")
    .where("canceled", "==", false)
    .where("visibility", "==", "public")
    .orderBy("startAt", "desc");

  // Query 3: Events where user is invited (private events, all past and upcoming)
  // NOTE: array-contains MUST be first in Firestore queries
  let invitedQuery = db
    .collection("events")
    .where("invitedUserIds", "array-contains", authUid)
    .where("canceled", "==", false)
    .orderBy("startAt", "desc");

  // Execute all queries in parallel
  const [ownedSnap, publicSnap, invitedSnap] = await Promise.all([
    ownedQuery.limit(queryParams.limit).get(),
    publicQuery.limit(queryParams.limit).get(),
    invitedQuery.limit(queryParams.limit).get()
  ]);

  // Combine and deduplicate events
  const eventMap = new Map();
  const allSnaps = [...ownedSnap.docs, ...publicSnap.docs, ...invitedSnap.docs];

  allSnaps.forEach(doc => {
    if (!eventMap.has(doc.id)) {
      eventMap.set(doc.id, doc);
    }
  });

  const snap = { docs: Array.from(eventMap.values()) };
  const attendeeIds = new Set<string>();
  const events = await Promise.all(
    snap.docs.map(async (doc) => {
      const data = doc.data();
      const membersSnap = await doc.ref.collection("members").get();

      const attendingFriendIds: string[] = [];
      const arrivalTimes: Record<string, number> = {};
      let attending = false;

      membersSnap.forEach((memberDoc: admin.firestore.QueryDocumentSnapshot<admin.firestore.DocumentData>) => {
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
  // Require authentication - userId must match authenticated user
  const uid = requireAuth(request);
  const payload = parseRequest(rsvpRequestSchema, request.data) as RSVPCallPayload;

  // Verify userId matches authenticated user (if provided)
  if (payload.userId && payload.userId !== uid) {
    throw new HttpsError("permission-denied", "UserId must match authenticated user");
  }

  console.log("[Function] rsvpEvent payload", payload, "authUid:", uid);

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

  // Add user to chat if status is "going"
  if (payload.status === "going") {
    const chatRef = db.collection("chats").doc(eventSnap.id);
    const chatSnap = await chatRef.get();

    if (chatSnap.exists) {
      const chatData = chatSnap.data() as schema.ChatDoc;

      // Add user to participants if not already there
      if (!chatData.participantIds.includes(uid)) {
        await chatRef.update({
          participantIds: admin.firestore.FieldValue.arrayUnion(uid)
        });

        // Get user info for system message
        const userSnap = await db.collection("users").doc(uid).get();
        const userData = userSnap.data() as schema.UserDoc | undefined;
        const userName = userData?.displayName ?? "A user";

        // Send system message
        const messageRef = chatRef.collection("messages").doc();
        const systemMessage: schema.MessageDoc = {
          messageId: messageRef.id,
          senderId: "system",
          senderName: "System",
          senderPhotoURL: null,
          text: `${userName} joined the event`,
          createdAt: now,
          type: "system"
        };
        await messageRef.set(systemMessage);

        // Update chat metadata
        await chatRef.update({
          lastMessageAt: now,
          lastMessageText: systemMessage.text,
          lastMessageSenderId: "system",
          lastMessageSenderName: "System"
        });
      }
    }
  }

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

  // Archive the associated chat
  const chatRef = db.collection("chats").doc(canonicalId);
  const chatSnap = await chatRef.get();
  if (chatSnap.exists) {
    await chatRef.update({
      archived: true
    });
    console.log("[Function] deleteEvent archived chat", { chatId: canonicalId });
  }

  console.log("[Function] deleteEvent canceled", { eventId: canonicalId });
  return { eventId: canonicalId, hardDelete: false };
});

export const getProfile = onCall(async (request) => {
  const authUid = requireAuth(request);
  const payload: ProfileRequestPayload = parseRequest(profileRequestSchema, request.data);
  console.log("[Function] getProfile payload", payload, "authUid:", authUid);

  try {
    // Use the authenticated user's UID instead of the payload userId
    const response = await buildProfilePayload(authUid);
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
  const authUid = requireAuth(request);
  const payload: ProfileUpdatePayload = parseRequest(profileUpdateSchema, request.data);
  console.log("[Function] updateProfile payload", payload, "authUid:", authUid);

  try {
    // Use the authenticated user's UID instead of the payload userId
    const userRef = db.collection("users").doc(authUid);
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
      const conflict = existing.docs.find((doc) => doc.id !== authUid);
      if (conflict) {
        throw new HttpsError("already-exists", "Username already taken.");
      }
      updates.username = payload.username;
      updates.usernameLowercase = normalized;
    }
    if (payload.bio !== undefined) {
      updates.bio = payload.bio ?? null;
    }
    if (payload.phoneNumber !== undefined) {
      updates.phoneNumber = payload.phoneNumber ?? null;
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

    const response = await buildProfilePayload(authUid);
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
  // Require authentication - senderId must match authenticated user
  const authUid = requireAuth(request);
  const payload = parseRequest(shareEventSchema, request.data);

  // Verify senderId matches authenticated user
  if (payload.senderId !== authUid) {
    throw new HttpsError("permission-denied", "SenderId must match authenticated user");
  }

  console.log("[Function] shareEvent payload", payload, "authUid:", authUid);

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

/**
 * Send a friend request to another user already on the app
 */
export const sendFriendRequest = onCall(async (request) => {
  const authUid = requireAuth(request);
  const payload: schema.SendFriendRequestPayload = parseRequest(schema.sendFriendRequestSchema, request.data);
  console.log("[Function] sendFriendRequest", { from: authUid, to: payload.recipientUserId });

  const now = Timestamp.now();
  const inviteRef = db.collection("invites").doc();

  try {
    // Check if recipient exists
    const recipientDoc = await db.collection("users").doc(payload.recipientUserId).get();
    if (!recipientDoc.exists) {
      throw new HttpsError("not-found", "Recipient user not found");
    }

    // Check if already friends
    const existingFriendship = await db.collection("friends")
      .where("userId", "==", authUid)
      .where("friendId", "==", payload.recipientUserId)
      .get();

    if (!existingFriendship.empty) {
      throw new HttpsError("already-exists", "Already friends with this user");
    }

    // Check if friend request already exists
    const existingRequest = await db.collection("invites")
      .where("senderId", "==", authUid)
      .where("recipientUserId", "==", payload.recipientUserId)
      .where("status", "==", "pending")
      .get();

    if (!existingRequest.empty) {
      throw new HttpsError("already-exists", "Friend request already sent");
    }

    // Create friend request
    const inviteDoc: schema.FriendInviteDoc = {
      senderId: authUid,
      recipientUserId: payload.recipientUserId,
      recipientPhone: null,
      recipientEmail: null,
      status: "pending",
      createdAt: now,
      updatedAt: now
    };

    await inviteRef.set(inviteDoc);

    console.log("[Function] sendFriendRequest created", { inviteId: inviteRef.id });

    return {
      inviteId: inviteRef.id,
      status: "pending"
    };
  } catch (error) {
    console.error("[Function] sendFriendRequest error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", (error as Error).message ?? "Failed to send friend request");
  }
});

/**
 * Accept or decline a friend request
 */
export const respondToFriendRequest = onCall(async (request) => {
  const authUid = requireAuth(request);
  const payload: schema.RespondToFriendRequestPayload = parseRequest(schema.respondToFriendRequestSchema, request.data);
  console.log("[Function] respondToFriendRequest", { user: authUid, inviteId: payload.inviteId, accept: payload.accept });

  const now = Timestamp.now();

  try {
    const inviteRef = db.collection("invites").doc(payload.inviteId);
    const inviteSnap = await inviteRef.get();

    if (!inviteSnap.exists) {
      throw new HttpsError("not-found", "Friend request not found");
    }

    const invite = inviteSnap.data() as schema.FriendInviteDoc;

    // Verify the authenticated user is the recipient
    if (invite.recipientUserId !== authUid) {
      throw new HttpsError("permission-denied", "You can only respond to your own friend requests");
    }

    if (invite.status !== "pending") {
      throw new HttpsError("failed-precondition", "Friend request already responded to");
    }

    if (payload.accept) {
      // Create bidirectional friendship
      const friend1: schema.FriendDoc = {
        userId: authUid,
        friendId: invite.senderId,
        status: "active",
        createdAt: now,
        updatedAt: now
      };

      const friend2: schema.FriendDoc = {
        userId: invite.senderId,
        friendId: authUid,
        status: "active",
        createdAt: now,
        updatedAt: now
      };

      await db.collection("friends").add(friend1);
      await db.collection("friends").add(friend2);

      // Update invite status
      await inviteRef.update({
        status: "accepted",
        updatedAt: now
      });

      console.log("[Function] respondToFriendRequest accepted", { inviteId: payload.inviteId });

      return {
        status: "accepted",
        friendId: invite.senderId
      };
    } else {
      // Decline request
      await inviteRef.update({
        status: "declined",
        updatedAt: now
      });

      console.log("[Function] respondToFriendRequest declined", { inviteId: payload.inviteId });

      return {
        status: "declined"
      };
    }
  } catch (error) {
    console.error("[Function] respondToFriendRequest error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", (error as Error).message ?? "Failed to respond to friend request");
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

// ====================================================================
// CHAT FUNCTIONS
// ====================================================================

/**
 * Send a message to an event chat
 */
export const sendMessage = onCall(async (request) => {
  const authUid = requireAuth(request);
  console.log("[Function] sendMessage", request.data, "authUid:", authUid);

  const payload = parseRequest(schema.sendMessageSchema, request.data ?? {}) as schema.SendMessagePayload;

  try {
    const chatRef = db.collection("chats").doc(payload.chatId);
    const chatSnap = await chatRef.get();

    if (!chatSnap.exists) {
      throw new HttpsError("not-found", "Chat not found");
    }

    const chatData = chatSnap.data() as schema.ChatDoc;

    // Verify user is a participant
    if (!chatData.participantIds.includes(authUid)) {
      throw new HttpsError("permission-denied", "You are not a participant in this chat");
    }

    // Get sender info
    const userRef = db.collection("users").doc(authUid);
    const userSnap = await userRef.get();
    const userData = userSnap.data() as schema.UserDoc | undefined;
    const senderName = userData?.displayName ?? "User";
    const senderPhotoURL = userData?.photoURL ?? null;

    // Create message
    const messageRef = chatRef.collection("messages").doc();
    const now = Timestamp.now();

    const messageDoc: schema.MessageDoc = {
      messageId: messageRef.id,
      senderId: authUid,
      senderName,
      senderPhotoURL,
      text: payload.text,
      createdAt: now,
      type: "text"
    };

    await messageRef.set(messageDoc);

    // Update chat metadata
    const newUnreadCounts = { ...chatData.unreadCounts };
    chatData.participantIds.forEach(participantId => {
      if (participantId !== authUid) {
        newUnreadCounts[participantId] = (newUnreadCounts[participantId] || 0) + 1;
      }
    });

    await chatRef.update({
      lastMessageAt: now,
      lastMessageText: payload.text.substring(0, 100),
      lastMessageSenderId: authUid,
      lastMessageSenderName: senderName,
      unreadCounts: newUnreadCounts
    });

    console.log("[Function] sendMessage success", messageRef.id);

    return {
      success: true,
      messageId: messageRef.id
    };
  } catch (error) {
    console.error("[Function] sendMessage error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to send message");
  }
});

/**
 * Get messages for a chat
 */
export const getMessages = onCall(async (request) => {
  const authUid = requireAuth(request);
  console.log("[Function] getMessages", request.data, "authUid:", authUid);

  const payload = parseRequest(schema.getMessagesSchema, request.data ?? {}) as schema.GetMessagesPayload;

  try {
    const chatRef = db.collection("chats").doc(payload.chatId);
    const chatSnap = await chatRef.get();

    if (!chatSnap.exists) {
      throw new HttpsError("not-found", "Chat not found");
    }

    const chatData = chatSnap.data() as schema.ChatDoc;

    // Verify user is a participant
    if (!chatData.participantIds.includes(authUid)) {
      throw new HttpsError("permission-denied", "You are not a participant in this chat");
    }

    // Query messages
    let query = chatRef.collection("messages")
      .orderBy("createdAt", "asc")
      .limit(payload.limit);

    if (payload.before) {
      query = query.where("createdAt", "<", Timestamp.fromDate(payload.before));
    }

    const messagesSnap = await query.get();

    const messages = messagesSnap.docs.map(doc => {
      const data = doc.data() as schema.MessageDoc;
      return {
        messageId: data.messageId,
        senderId: data.senderId,
        senderName: data.senderName,
        senderPhotoURL: data.senderPhotoURL,
        text: data.text,
        createdAt: data.createdAt.toDate().toISOString(),
        type: data.type
      };
    });

    // Reset unread count for this user
    const newUnreadCounts = { ...chatData.unreadCounts };
    newUnreadCounts[authUid] = 0;
    await chatRef.update({ unreadCounts: newUnreadCounts });

    console.log("[Function] getMessages success", messages.length, "messages");

    return { messages };
  } catch (error) {
    console.error("[Function] getMessages error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to get messages");
  }
});

/**
 * List all chats for the current user
 */
export const listChats = onCall(async (request) => {
  const authUid = requireAuth(request);
  console.log("[Function] listChats authUid:", authUid);

  try {
    const chatsSnap = await db.collection("chats")
      .where("participantIds", "array-contains", authUid)
      .limit(50)
      .get();

    const chats = await Promise.all(chatsSnap.docs
      .filter(doc => {
        const data = doc.data() as schema.ChatDoc;
        // Filter out archived chats
        return !data.archived;
      })
      .map(async (doc) => {
        const data = doc.data() as schema.ChatDoc;

        // Fetch event to get endAt timestamp
        let eventEndAt: string | null = null;
        try {
          const eventDoc = await db.collection("events").doc(data.eventId).get();
          if (eventDoc.exists) {
            const eventData = eventDoc.data();
            if (eventData?.endAt) {
              eventEndAt = eventData.endAt.toDate().toISOString();
            }
          }
        } catch (eventError) {
          console.warn("[Function] listChats - failed to fetch event", data.eventId, eventError);
        }

        return {
          chatId: data.chatId,
          eventId: data.eventId,
          eventTitle: data.eventTitle,
          eventEndAt: eventEndAt,
          lastMessageAt: data.lastMessageAt?.toDate().toISOString() ?? null,
          lastMessageText: data.lastMessageText,
          lastMessageSenderName: data.lastMessageSenderName,
          unreadCount: data.unreadCounts[authUid] || 0,
          participantCount: data.participantIds.length,
          lastMessageTimestamp: data.lastMessageAt?.toMillis() ?? 0
        };
      }));

    // Sort in memory by lastMessageAt (most recent first)
    chats.sort((a, b) => b.lastMessageTimestamp - a.lastMessageTimestamp);

    console.log("[Function] listChats success", chats.length, "chats");

    return { chats };
  } catch (error) {
    console.error("[Function] listChats error", error);
    throw new HttpsError("internal", (error as Error).message ?? "Failed to list chats");
  }
});

// Scheduled function to archive old chats
// Runs daily at 2 AM UTC to archive chats from events that ended 7+ days ago
export const archiveOldChats = onSchedule("every day 02:00", async (event) => {
  console.log("[Function] archiveOldChats starting");

  try {
    const now = Timestamp.now();
    const sevenDaysAgo = Timestamp.fromDate(
      new Date(now.toMillis() - 7 * 24 * 60 * 60 * 1000)
    );

    // Find all events that ended 7+ days ago
    const eventsSnap = await db.collection("events")
      .where("endAt", "<=", sevenDaysAgo)
      .get();

    console.log("[Function] archiveOldChats found", eventsSnap.size, "old events");

    let archivedCount = 0;
    const batch = db.batch();

    for (const eventDoc of eventsSnap.docs) {
      const eventId = eventDoc.id;

      // Find all chats for this event
      const chatsSnap = await db.collection("chats")
        .where("eventId", "==", eventId)
        .where("archived", "==", false)
        .get();

      for (const chatDoc of chatsSnap.docs) {
        batch.update(chatDoc.ref, {
          archived: true,
          archivedAt: now
        });
        archivedCount++;
      }
    }

    if (archivedCount > 0) {
      await batch.commit();
      console.log("[Function] archiveOldChats archived", archivedCount, "chats");
    } else {
      console.log("[Function] archiveOldChats no chats to archive");
    }
  } catch (error) {
    console.error("[Function] archiveOldChats error", error);
    throw error;
  }
});
