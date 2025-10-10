#!/usr/bin/env node
/**
 * Seed script for StepOut sample data.
 * Usage (emulator):
 *   FIREBASE_PROJECT_ID=stepout-local \
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
 *   node seed.js
 *
 * Usage (production project):
 *   FIREBASE_PROJECT_ID=stepout-3db1a node seed.js
 *
 * Requires firebase-admin (installed via package.json in this folder).
 */
import admin from "firebase-admin";
import serviceAccount from "./serviceaccount.json" assert { type: "json" };

const projectId = process.env.FIREBASE_PROJECT_ID;
if (!projectId) {
  console.error("FIREBASE_PROJECT_ID environment variable is required.");
  process.exit(1);
}

const app = admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId
});
const db = admin.firestore();

const now = admin.firestore.Timestamp.now();

const users = [
  {
    id: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942",
    data: {
      displayName: "You",
      email: "you@example.com",
      onboarded: true,
      theme: "system",
      interests: ["tech", "coffee", "music"],
      pushTokens: [],
      createdAt: now,
      updatedAt: now
    },
    credentials: {
      email: "you@example.com",
      password: "StepOut123!"
    }
  },
  {
    id: "F7B10C18-5A0F-4C16-ABF3-8DFD52E3E570",
    data: {
      displayName: "Disha Kapoor",
      email: "disha@example.com",
      onboarded: true,
      theme: "dark",
      interests: ["startups", "mentoring"],
      pushTokens: [],
      createdAt: now,
      updatedAt: now
    },
    credentials: {
      email: "disha@example.com",
      password: "StepOut123!"
    }
  },
  {
    id: "02D4F551-8C88-4A58-9783-BA5B4B4AD9B6",
    data: {
      displayName: "Divyam Mehta",
      email: "divyam@example.com",
      onboarded: true,
      theme: "light",
      interests: ["photography", "travel"],
      pushTokens: [],
      createdAt: now,
      updatedAt: now
    },
    credentials: {
      email: "divyam@example.com",
      password: "StepOut123!"
    }
  },
  {
    id: "6B7C5D7E-1D90-4FD0-8B7E-75E0A9A9B415",
    data: {
      displayName: "Maya Chen",
      email: "maya@example.com",
      onboarded: true,
      theme: "system",
      interests: ["design", "wellness"],
      pushTokens: [],
      createdAt: now,
      updatedAt: now
    },
    credentials: {
      email: "maya@example.com",
      password: "StepOut123!"
    }
  },
  {
    id: "1E3FC403-346F-4ADC-8B3E-359BAAF343B5",
    data: {
      displayName: "Jordan Lee",
      email: "jordan@example.com",
      onboarded: true,
      theme: "dark",
      interests: ["hackathons", "ai"],
      pushTokens: [],
      createdAt: now,
      updatedAt: now
    },
    credentials: {
      email: "jordan@example.com",
      password: "StepOut123!"
    }
  }
];

const futureDate = (daysFromNow, hour = 18) => {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  date.setDate(date.getDate() + daysFromNow);
  date.setHours(hour);
  return admin.firestore.Timestamp.fromDate(date);
};

const events = [
  {
    id: "A2D2B22B-5C36-4E67-8F41-1F68A39F8E03",
    title: "Swift Meetup",
    description: "Feels-like WWDC mini session with SF devs.",
    startAt: futureDate(2, 18),
    endAt: futureDate(2, 20),
    location: "San Francisco, CA",
    visibility: "public",
    ownerId: "F7B10C18-5A0F-4C16-ABF3-8DFD52E3E570",
    geo: { lat: 37.776321, lng: -122.417864 },
    members: [
      { userId: "F7B10C18-5A0F-4C16-ABF3-8DFD52E3E570", status: "going", role: "host" },
      { userId: "02D4F551-8C88-4A58-9783-BA5B4B4AD9B6", status: "going", role: "attendee" },
      { userId: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942", status: "going", role: "attendee" }
    ]
  },
  {
    id: "D354D6E7-885C-4949-A2D7-0C79431635F7",
    title: "UI Design Workshop",
    description: "Hands-on Figma session for mobile UI lovers.",
    startAt: futureDate(7, 17),
    endAt: futureDate(7, 19),
    location: "Remote",
    visibility: "invite-only",
    ownerId: "6B7C5D7E-1D90-4FD0-8B7E-75E0A9A9B415",
    members: [
      { userId: "6B7C5D7E-1D90-4FD0-8B7E-75E0A9A9B415", status: "going", role: "host" },
      { userId: "F7B10C18-5A0F-4C16-ABF3-8DFD52E3E570", status: "going", role: "attendee" },
      { userId: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942", status: "interested", role: "attendee" }
    ]
  },
  {
    id: "8C7B1B8F-6F02-49DA-AB43-6C45CE3631DC",
    title: "NYC Hackathon",
    description: "48-hour build sprint with prizes and mentors.",
    startAt: futureDate(14, 9),
    endAt: futureDate(14, 21),
    location: "New York, NY",
    visibility: "public",
    ownerId: "1E3FC403-346F-4ADC-8B3E-359BAAF343B5",
    geo: { lat: 40.7128, lng: -74.006 },
    members: [
      { userId: "1E3FC403-346F-4ADC-8B3E-359BAAF343B5", status: "going", role: "host" },
      { userId: "F7B10C18-5A0F-4C16-ABF3-8DFD52E3E570", status: "going", role: "attendee" },
      { userId: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942", status: "going", role: "attendee" }
    ]
  },
  {
    id: "E75A3E68-1F15-43D2-8E8A-C6E1FB2D5F20",
    title: "Mission Coffee Crawl",
    description: "Saturday stroll through SF coffee shops.",
    startAt: futureDate(4, 10),
    endAt: futureDate(4, 13),
    location: "San Francisco, CA",
    visibility: "public",
    ownerId: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942",
    geo: { lat: 37.7599, lng: -122.4148 },
    members: [
      { userId: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942", status: "going", role: "host" },
      { userId: "02D4F551-8C88-4A58-9783-BA5B4B4AD9B6", status: "going", role: "attendee" },
      { userId: "6B7C5D7E-1D90-4FD0-8B7E-75E0A9A9B415", status: "interested", role: "attendee" }
    ]
  }
];

async function seedUsers() {
  for (const user of users) {
    await db.collection("users").doc(user.id).set(user.data, { merge: true });
    console.log(`✓ Seeded user ${user.data.displayName}`);

    if (user.credentials) {
      try {
        await admin.auth().createUser({
          uid: user.id,
          email: user.credentials.email,
          password: user.credentials.password,
          displayName: user.data.displayName
        });
        console.log(`  ↳ Created auth user ${user.credentials.email}`);
      } catch (error) {
        if (error.code === "auth/uid-already-exists" || error.code === "auth/email-already-exists") {
          console.log(`  ↳ Auth user ${user.credentials.email} already exists`);
        } else {
          throw error;
        }
      }
    }
  }
}

async function seedEvents() {
  for (const event of events) {
    const eventRef = db.collection("events").doc(event.id);
    const eventDoc = {
      ownerId: event.ownerId,
      title: event.title,
      description: event.description,
      startAt: event.startAt,
      endAt: event.endAt,
      location: event.location,
      visibility: event.visibility,
      maxGuests: null,
      geo: event.geo ?? null,
      coverImagePath: null,
      createdAt: now,
      updatedAt: now,
      canceled: false
    };

    await eventRef.set(eventDoc, { merge: true });

    for (const member of event.members) {
      await eventRef.collection("members").doc(member.userId).set(
        {
          userId: member.userId,
          status: member.status,
          arrivalAt: null,
          role: member.role,
          updatedAt: now
        },
        { merge: true }
      );
    }

    console.log(`✓ Seeded event ${event.title}`);
  }
}

async function main() {
  try {
    await seedUsers();
    await seedEvents();
    console.log("Seed complete!");
    process.exit(0);
  } catch (error) {
    console.error("Seed failed:", error);
    process.exit(1);
  }
}

await main();
