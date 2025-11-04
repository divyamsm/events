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

// Calculate distance between two coordinates using Haversine formula (returns distance in km)
function calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371; // Earth's radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
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
  console.log("[Function] createEvent RAW request.data.categories", request.data?.categories);
  const payload: EventCreatePayload = parseRequest(eventSchema, request.data);
  console.log("[Function] createEvent PARSED payload.categories", payload.categories);
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
    categories: payload.categories ?? ["other"],
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

  // Query 4: Events shared with user by friends
  let sharedQuery = db
    .collection("events")
    .where("sharedInviteFriendIds", "array-contains", authUid)
    .where("canceled", "==", false)
    .orderBy("startAt", "desc");

  // Execute all queries in parallel
  const [ownedSnap, publicSnap, invitedSnap, sharedSnap] = await Promise.all([
    ownedQuery.limit(queryParams.limit).get(),
    publicQuery.limit(queryParams.limit).get(),
    invitedQuery.limit(queryParams.limit).get(),
    sharedQuery.limit(queryParams.limit).get()
  ]);

  // Combine and deduplicate events
  const eventMap = new Map();
  const allSnaps = [...ownedSnap.docs, ...publicSnap.docs, ...invitedSnap.docs, ...sharedSnap.docs];

  allSnaps.forEach(doc => {
    if (!eventMap.has(doc.id)) {
      eventMap.set(doc.id, doc);
    }
  });

  // Apply filters
  let filteredDocs = Array.from(eventMap.values());

  // Filter by categories
  if (queryParams.categories && queryParams.categories.length > 0) {
    filteredDocs = filteredDocs.filter(doc => {
      const data = doc.data();
      const eventCategories = data.categories || ["other"];
      return eventCategories.some((cat: string) => queryParams.categories!.includes(cat as any));
    });
  }

  // Filter by text search (case-insensitive search in title, description, location)
  if (queryParams.searchText && queryParams.searchText.trim()) {
    const searchLower = queryParams.searchText.trim().toLowerCase();
    filteredDocs = filteredDocs.filter(doc => {
      const data = doc.data();
      const titleMatch = (data.title || "").toLowerCase().includes(searchLower);
      const descMatch = (data.description || "").toLowerCase().includes(searchLower);
      const locMatch = (data.location || "").toLowerCase().includes(searchLower);
      return titleMatch || descMatch || locMatch;
    });
  }

  // Filter by distance (if user location and maxDistance provided)
  if (queryParams.maxDistance && queryParams.userLat && queryParams.userLng) {
    filteredDocs = filteredDocs.filter(doc => {
      const data = doc.data();
      if (!data.geo || !data.geo.lat || !data.geo.lng) {
        return false; // Exclude events without location
      }
      const distance = calculateDistance(
        queryParams.userLat!,
        queryParams.userLng!,
        data.geo.lat,
        data.geo.lng
      );
      return distance <= queryParams.maxDistance!;
    });
  }

  const snap = { docs: filteredDocs };
  const attendeeIds = new Set<string>();

  // Build reverse mapping: Firebase Auth UID -> UUID
  const authUidToUuid = new Map<string, string>();
  const allUsersSnap = await db.collection("users").get();
  allUsersSnap.docs.forEach((userDoc) => {
    const userData = userDoc.data();
    if (userData.id) {
      authUidToUuid.set(userDoc.id, userData.id);  // Map Firebase Auth UID -> UUID
    }
  });

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

      // Convert sharedInviteFriendIds from Firebase Auth UIDs back to UUIDs for iOS
      const sharedAuthUids = (data.sharedInviteFriendIds as string[]) ?? [];
      const sharedUuids = sharedAuthUids
        .map(authUid => authUidToUuid.get(authUid))
        .filter((uuid): uuid is string => uuid !== undefined);

      // Convert attendingFriendIds from Firebase Auth UIDs back to UUIDs for iOS
      const attendingUuids = attendingFriendIds
        .map(authUid => authUidToUuid.get(authUid))
        .filter((uuid): uuid is string => uuid !== undefined);

      // Convert arrivalTimes keys from Firebase Auth UIDs to UUIDs
      const arrivalTimesUuids: Record<string, number> = {};
      for (const [authUid, time] of Object.entries(arrivalTimes)) {
        const uuid = authUidToUuid.get(authUid);
        if (uuid) {
          arrivalTimesUuids[uuid] = time;
        }
      }

      const eventResponse = {
        id: doc.id,
        title: data.title,
        location: data.location,
        startAt: data.startAt instanceof Timestamp ? data.startAt.toMillis() : null,
        endAt: data.endAt instanceof Timestamp ? data.endAt.toMillis() : null,
        coverImagePath: data.coverImagePath ?? null,
        visibility: data.visibility,
        ownerId: data.ownerId,
        attending,
        attendingFriendIds: attendingUuids,  // Send UUIDs, not Firebase Auth UIDs
        invitedFriendIds: data.invitedFriendIds ?? [],
        sharedInviteFriendIds: sharedUuids,  // Send UUIDs, not Firebase Auth UIDs
        arrivalTimes: arrivalTimesUuids,  // Send UUIDs as keys, not Firebase Auth UIDs
        geo: data.geo ?? null,
        categories: data.categories ?? ["other"]
      };

      if (data.title === "Bharath" || data.title === "Bharath 2") {
        console.log("[Function] listFeed 🔍 Event:", JSON.stringify(eventResponse, null, 2));
        console.log("[Function] listFeed 🔍 Raw attendingFriendIds (Auth UIDs):", attendingFriendIds);
        console.log("[Function] listFeed 🔍 Converted attendingUuids:", attendingUuids);
      }

      if (data.title === "Text") {
        console.log("[Function] listFeed 🔍 Event 'Text' - data.categories from Firestore:", data.categories);
        console.log("[Function] listFeed 🔍 Event 'Text' - eventResponse.categories:", eventResponse.categories);
      }

      return eventResponse;
    })
  );

  if (authUid) {
    attendeeIds.delete(authUid);
  }
  // Fetch the user's actual friends from the friends collection
  let friendsList: Array<{ id: string; displayName: string; photoURL: string | null }> = [];

  if (authUid) {
    console.log(`[Function] listFeed querying friends for authUid: ${authUid}`);

    const friendsQuery = await db.collection("friends")
      .where("userId", "==", authUid)
      .where("status", "==", "active")
      .get();

    console.log(`[Function] listFeed found ${friendsQuery.docs.length} friend docs`);
    const friendIds = friendsQuery.docs.map(doc => {
      const data = doc.data();
      console.log(`[Function] listFeed friend doc:`, data);
      return (data as any).friendId;
    });

    const friendPromises = friendIds.map(async (friendId) => {
      const userSnap = await db.collection("users").doc(friendId).get();
      if (!userSnap.exists) return null;
      const userData = userSnap.data() ?? {};
      return {
        id: userData.id ?? friendId,  // Use UUID from user document
        displayName: userData.displayName ?? "Friend",
        photoURL: userData.photoURL ?? null
      };
    });

    const friendDocs = await Promise.all(friendPromises);
    friendsList = friendDocs.filter((doc): doc is { id: string; displayName: string; photoURL: string | null } => doc !== null);
    console.log(`[Function] listFeed found ${friendsList.length} friends after fetching user data`);
  }

  console.log(`[Function] listFeed returning ${events.length} events and ${friendsList.length} friends`);
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

  // Manage chat access based on RSVP status
  const chatRef = db.collection("chats").doc(eventSnap.id);
  const chatSnap = await chatRef.get();

  if (chatSnap.exists) {
    const chatData = chatSnap.data() as schema.ChatDoc;

    if (payload.status === "going") {
      // Add user to chat participants if not already there
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
    } else {
      // Remove user from chat participants if changing to "not going" or "maybe"
      if (chatData.participantIds.includes(uid)) {
        await chatRef.update({
          participantIds: admin.firestore.FieldValue.arrayRemove(uid)
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
          text: `${userName} left the event`,
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

        // Remove unread count for this user
        const newUnreadCounts = { ...chatData.unreadCounts };
        delete newUnreadCounts[uid];
        await chatRef.update({ unreadCounts: newUnreadCounts });
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
  if (payload.categories !== undefined) {
    updates.categories = payload.categories;
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
  // Require authentication
  const authUid = requireAuth(request);
  const payload = parseRequest(shareEventSchema, request.data);

  console.log("[Function] shareEvent payload", payload, "authUid:", authUid);

  try {
    // Convert recipient UUIDs to Firebase Auth UIDs
    // Query all users and build UUID -> authUid mapping from user documents
    const usersSnap = await db.collection("users").get();
    const uuidToAuthUid = new Map<string, string>();

    usersSnap.docs.forEach((doc) => {
      const userData = doc.data();
      if (userData.id) {
        uuidToAuthUid.set(userData.id, doc.id);  // Map UUID -> Firebase Auth UID
      }
    });

    // Convert recipient UUIDs to Firebase Auth UIDs
    const recipientAuthUids = payload.recipientIds
      .map(uuid => uuidToAuthUid.get(uuid))
      .filter((uid): uid is string => uid !== undefined);

    console.log("[Function] shareEvent converted", { uuidCount: payload.recipientIds.length, authUidCount: recipientAuthUids.length });

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
    const updatedShared = Array.from(new Set([...currentShared, ...recipientAuthUids]));

    // Update event with new shared list
    await eventRef.update({
      sharedInviteFriendIds: updatedShared,
      updatedAt: Timestamp.now()
    });

    // Get sender information for notification
    const senderSnap = await db.collection("users").doc(authUid).get();
    const senderData = senderSnap.data();
    const senderName = senderData?.displayName ?? "Someone";

    // Send push notifications to new recipients
    const newRecipientAuthUids = recipientAuthUids.filter(id => !currentShared.includes(id));

    if (newRecipientAuthUids.length > 0) {
      const recipientPromises = newRecipientAuthUids.map(async (recipientId) => {
        try {
          const recipientSnap = await db.collection("users").doc(recipientId).get();
          if (!recipientSnap.exists) return;

          const recipientData = recipientSnap.data();
          const pushTokens = recipientData?.pushTokens ?? [];

          if (pushTokens.length === 0) {
            console.log(`[Function] shareEvent: No push tokens for recipient ${recipientId}`);
            return;
          }

          const eventTitle = eventData?.title ?? "an event";
          const eventDate = eventData?.startAt instanceof Timestamp
            ? eventData.startAt.toDate().toLocaleDateString()
            : "soon";

          const message = {
            notification: {
              title: `${senderName} invited you to an event`,
              body: `${eventTitle} on ${eventDate}`
            },
            data: {
              type: "event_invite",
              eventId: payload.eventId,
              senderId: authUid,
              senderName: senderName
            },
            tokens: pushTokens
          };

          const response = await admin.messaging().sendEachForMulticast(message);
          console.log(`[Function] shareEvent: Sent ${response.successCount} notifications to ${recipientId}`);

          if (response.failureCount > 0) {
            const failedTokens: string[] = [];
            response.responses.forEach((resp, idx) => {
              if (!resp.success) {
                failedTokens.push(pushTokens[idx]);
              }
            });

            // Remove invalid tokens
            if (failedTokens.length > 0) {
              await db.collection("users").doc(recipientId).update({
                pushTokens: pushTokens.filter((token: string) => !failedTokens.includes(token))
              });
            }
          }
        } catch (error) {
          console.error(`[Function] shareEvent: Failed to send notification to ${recipientId}`, error);
        }
      });

      await Promise.all(recipientPromises);
    }

    console.log("[Function] shareEvent success", {
      eventId: payload.eventId,
      newRecipients: payload.recipientIds.length,
      totalShared: updatedShared.length,
      notificationsSent: newRecipientAuthUids.length
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

    console.log("[Function] sendFriendRequest created", { inviteId: inviteRef.id, from: authUid, to: payload.recipientUserId });

    // TODO: Send push notification to recipient user
    // This would require FCM token stored in user document
    // await sendPushNotification(payload.recipientUserId, "New Friend Request", `${senderName} wants to be friends`);

    return {
      inviteId: inviteRef.id,
      status: "pending",
      message: "Friend request sent successfully"
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

    // Double-check: Verify user has RSVP'd as "going" to the event
    const eventRef = db.collection("events").doc(chatData.eventId);
    const memberDoc = await eventRef.collection("members").doc(authUid).get();
    if (!memberDoc.exists || memberDoc.data()?.status !== "going") {
      throw new HttpsError("permission-denied", "You must RSVP as 'going' to access this chat");
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

    // Double-check: Verify user has RSVP'd as "going" to the event
    const eventRef = db.collection("events").doc(chatData.eventId);
    const memberDoc = await eventRef.collection("members").doc(authUid).get();
    if (!memberDoc.exists || memberDoc.data()?.status !== "going") {
      throw new HttpsError("permission-denied", "You must RSVP as 'going' to access this chat");
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

// ===========================
// Event Photos APIs
// ===========================

export const uploadEventPhoto = onCall(async (request) => {
  const authUid = requireAuth(request);
  const payload: schema.UploadPhotoPayload = parseRequest(schema.uploadPhotoSchema, request.data);
  console.log("[Function] uploadEventPhoto payload", payload, "authUid:", authUid);

  try {
    // Verify event exists
    const eventRef = db.collection("events").doc(payload.eventId);
    const eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found");
    }

    // Get user info
    const userRef = db.collection("users").doc(authUid);
    const userSnap = await userRef.get();
    const userData = userSnap.data() as schema.UserDoc | undefined;
    const userName = userData?.displayName ?? "User";
    const userPhotoURL = userData?.photoURL ?? null;

    const now = Timestamp.now();
    const photoId = randomUUID();
    const photoDoc: schema.EventPhotoDoc = {
      photoId,
      eventId: payload.eventId,
      userId: authUid,
      userName,
      userPhotoURL,
      photoURL: payload.photoURL,
      caption: payload.caption ?? null,
      createdAt: now
    };

    await db.collection("eventPhotos").doc(photoId).set(photoDoc);

    console.log("[Function] uploadEventPhoto created photo", photoId);
    return { photoId };
  } catch (error) {
    console.error("[Function] uploadEventPhoto error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to upload photo.");
  }
});

export const listEventPhotos = onCall(async (request) => {
  const authUid = requireAuth(request);
  const rawPayload = parseRequest(schema.listPhotosSchema, request.data);
  const payload: schema.ListPhotosPayload = {
    eventId: rawPayload.eventId,
    limit: rawPayload.limit ?? 30,
    before: rawPayload.before
  };
  console.log("[Function] listEventPhotos payload", payload, "authUid:", authUid);

  try {
    // Verify event exists and user has access
    const eventRef = db.collection("events").doc(payload.eventId);
    const eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found");
    }

    const eventData = eventSnap.data();
    const visibility = eventData?.visibility;

    // Check access: public event, invited, or attending
    if (visibility !== "public") {
      const memberSnap = await eventRef.collection("members").doc(authUid).get();
      const sharedInviteIds = (eventData?.sharedInviteFriendIds as string[]) ?? [];

      if (!memberSnap.exists && !sharedInviteIds.includes(authUid) && eventData?.ownerId !== authUid) {
        throw new HttpsError("permission-denied", "You don't have access to this event");
      }
    }

    // Get photos with cursor pagination
    let photosQuery = db.collection("eventPhotos")
      .where("eventId", "==", payload.eventId)
      .orderBy("createdAt", "desc");

    if (payload.before) {
      photosQuery = photosQuery.where("createdAt", "<", Timestamp.fromDate(payload.before));
    }

    photosQuery = photosQuery.limit(payload.limit);

    const photosSnap = await photosQuery.get();

    const photos = photosSnap.docs.map(doc => {
      const data = doc.data() as schema.EventPhotoDoc;
      return {
        photoId: data.photoId,
        userId: data.userId,
        userName: data.userName,
        userPhotoURL: data.userPhotoURL,
        photoURL: data.photoURL,
        caption: data.caption,
        createdAt: data.createdAt.toMillis()
      };
    });

    console.log("[Function] listEventPhotos returning", photos.length, "photos");
    return { photos };
  } catch (error) {
    console.error("[Function] listEventPhotos error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to list photos.");
  }
});

export const deleteEventPhoto = onCall(async (request) => {
  const authUid = requireAuth(request);
  const payload: schema.DeletePhotoPayload = parseRequest(schema.deletePhotoSchema, request.data);
  console.log("[Function] deleteEventPhoto payload", payload, "authUid:", authUid);

  try {
    const photoRef = db.collection("eventPhotos").doc(payload.photoId);
    const photoSnap = await photoRef.get();

    if (!photoSnap.exists) {
      throw new HttpsError("not-found", "Photo not found");
    }

    const photoData = photoSnap.data() as schema.EventPhotoDoc;

    // Verify user is photo owner or event owner
    const eventRef = db.collection("events").doc(payload.eventId);
    const eventSnap = await eventRef.get();
    const eventData = eventSnap.data();

    if (photoData.userId !== authUid && eventData?.ownerId !== authUid) {
      throw new HttpsError("permission-denied", "You can only delete your own photos or photos from your events");
    }

    await photoRef.delete();

    console.log("[Function] deleteEventPhoto deleted", payload.photoId);
    return { success: true };
  } catch (error) {
    console.error("[Function] deleteEventPhoto error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to delete photo.");
  }
});

// ===========================
// Event Comments APIs
// ===========================

export const postEventComment = onCall(async (request) => {
  const authUid = requireAuth(request);
  const payload: schema.PostCommentPayload = parseRequest(schema.postCommentSchema, request.data);
  console.log("[Function] postEventComment payload", payload, "authUid:", authUid);

  try {
    // Verify event exists
    const eventRef = db.collection("events").doc(payload.eventId);
    const eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found");
    }

    const eventData = eventSnap.data();
    const visibility = eventData?.visibility;

    // Check access: public event, invited, or attending
    if (visibility !== "public") {
      const memberSnap = await eventRef.collection("members").doc(authUid).get();
      const sharedInviteIds = (eventData?.sharedInviteFriendIds as string[]) ?? [];

      if (!memberSnap.exists && !sharedInviteIds.includes(authUid) && eventData?.ownerId !== authUid) {
        throw new HttpsError("permission-denied", "You don't have access to this event");
      }
    }

    // Get user info
    const userRef = db.collection("users").doc(authUid);
    const userSnap = await userRef.get();
    const userData = userSnap.data() as schema.UserDoc | undefined;
    const userName = userData?.displayName ?? "User";
    const userPhotoURL = userData?.photoURL ?? null;

    const now = Timestamp.now();
    const commentId = randomUUID();
    const commentDoc: schema.EventCommentDoc = {
      commentId,
      eventId: payload.eventId,
      userId: authUid,
      userName,
      userPhotoURL,
      text: payload.text,
      createdAt: now
    };

    await db.collection("eventComments").doc(commentId).set(commentDoc);

    console.log("[Function] postEventComment created comment", commentId);
    return { commentId };
  } catch (error) {
    console.error("[Function] postEventComment error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to post comment.");
  }
});

export const listEventComments = onCall(async (request) => {
  const authUid = requireAuth(request);
  const rawPayload = parseRequest(schema.listCommentsSchema, request.data);
  const payload: schema.ListCommentsPayload = {
    eventId: rawPayload.eventId,
    limit: rawPayload.limit ?? 50,
    before: rawPayload.before
  };
  console.log("[Function] listEventComments payload", payload, "authUid:", authUid);

  try {
    // Verify event exists and user has access
    const eventRef = db.collection("events").doc(payload.eventId);
    const eventSnap = await eventRef.get();
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Event not found");
    }

    const eventData = eventSnap.data();
    const visibility = eventData?.visibility;

    // Check access: public event, invited, or attending
    if (visibility !== "public") {
      const memberSnap = await eventRef.collection("members").doc(authUid).get();
      const sharedInviteIds = (eventData?.sharedInviteFriendIds as string[]) ?? [];

      if (!memberSnap.exists && !sharedInviteIds.includes(authUid) && eventData?.ownerId !== authUid) {
        throw new HttpsError("permission-denied", "You don't have access to this event");
      }
    }

    // Get comments
    let commentsQuery = db.collection("eventComments")
      .where("eventId", "==", payload.eventId)
      .orderBy("createdAt", "desc")
      .limit(payload.limit);

    if (payload.before) {
      commentsQuery = commentsQuery.where("createdAt", "<", Timestamp.fromDate(payload.before));
    }

    const commentsSnap = await commentsQuery.get();

    const comments = commentsSnap.docs.map(doc => {
      const data = doc.data() as schema.EventCommentDoc;
      return {
        commentId: data.commentId,
        userId: data.userId,
        userName: data.userName,
        userPhotoURL: data.userPhotoURL,
        text: data.text,
        createdAt: data.createdAt.toMillis()
      };
    });

    console.log("[Function] listEventComments returning", comments.length, "comments");
    return { comments };
  } catch (error) {
    console.error("[Function] listEventComments error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to list comments.");
  }
});

export const deleteEventComment = onCall(async (request) => {
  const authUid = requireAuth(request);
  const payload: schema.DeleteCommentPayload = parseRequest(schema.deleteCommentSchema, request.data);
  console.log("[Function] deleteEventComment payload", payload, "authUid:", authUid);

  try {
    const commentRef = db.collection("eventComments").doc(payload.commentId);
    const commentSnap = await commentRef.get();

    if (!commentSnap.exists) {
      throw new HttpsError("not-found", "Comment not found");
    }

    const commentData = commentSnap.data() as schema.EventCommentDoc;

    // Verify user is comment owner or event owner
    const eventRef = db.collection("events").doc(payload.eventId);
    const eventSnap = await eventRef.get();
    const eventData = eventSnap.data();

    if (commentData.userId !== authUid && eventData?.ownerId !== authUid) {
      throw new HttpsError("permission-denied", "You can only delete your own comments or comments from your events");
    }

    await commentRef.delete();

    console.log("[Function] deleteEventComment deleted", payload.commentId);
    return { success: true };
  } catch (error) {
    console.error("[Function] deleteEventComment error", error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", (error as Error).message ?? "Failed to delete comment.");
  }
});
