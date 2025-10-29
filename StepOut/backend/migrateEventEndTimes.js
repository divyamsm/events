const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp({
  projectId: 'stepout-3db1a'
});

const db = admin.firestore();

async function migrateEvents() {
  console.log('[Migration] Starting event endAt migration...');

  try {
    // Get all events that don't have endAt
    const eventsSnap = await db.collection('events').get();

    console.log(`[Migration] Found ${eventsSnap.size} total events`);

    let updatedCount = 0;
    let skippedCount = 0;
    const batch = db.batch();
    let batchCount = 0;

    for (const eventDoc of eventsSnap.docs) {
      const data = eventDoc.data();

      // Skip if already has endAt
      if (data.endAt) {
        skippedCount++;
        continue;
      }

      // Set endAt to 11 PM on the same day as startAt
      if (data.startAt) {
        const startDate = data.startAt.toDate();
        const endDate = new Date(startDate);
        endDate.setHours(23, 0, 0, 0); // 11 PM

        // If start time is after 11 PM, set end time to next day 2 AM
        if (startDate.getHours() >= 23) {
          endDate.setDate(endDate.getDate() + 1);
          endDate.setHours(2, 0, 0, 0);
        }

        batch.update(eventDoc.ref, {
          endAt: admin.firestore.Timestamp.fromDate(endDate),
          updatedAt: admin.firestore.Timestamp.now()
        });

        updatedCount++;
        batchCount++;

        console.log(`[Migration] Event "${data.title}" - start: ${startDate.toISOString()}, end: ${endDate.toISOString()}`);

        // Commit batch every 500 updates
        if (batchCount >= 500) {
          await batch.commit();
          console.log(`[Migration] Committed batch of ${batchCount} updates`);
          batchCount = 0;
        }
      }
    }

    // Commit remaining updates
    if (batchCount > 0) {
      await batch.commit();
      console.log(`[Migration] Committed final batch of ${batchCount} updates`);
    }

    console.log('[Migration] ✅ Migration complete!');
    console.log(`[Migration] Updated: ${updatedCount} events`);
    console.log(`[Migration] Skipped (already had endAt): ${skippedCount} events`);

  } catch (error) {
    console.error('[Migration] ❌ Error:', error);
    process.exit(1);
  }

  process.exit(0);
}

// Run migration
migrateEvents();
