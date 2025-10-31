const admin = require('./functions/node_modules/firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Function to generate deterministic UUID from Firebase Auth UID
function authUidToUuid(authUid) {
  const uidHex = Buffer.from(authUid, 'utf8').toString('hex').padEnd(32, '0').substring(0, 32);
  return `${uidHex.substring(0, 8)}-${uidHex.substring(8, 12)}-${uidHex.substring(12, 16)}-${uidHex.substring(16, 20)}-${uidHex.substring(20, 32)}`.toUpperCase();
}

async function addUuidToUsers() {
  console.log('Adding UUID field to all user documents...');

  const usersSnapshot = await db.collection('users').get();
  console.log(`Found ${usersSnapshot.docs.length} user documents`);

  const batch = db.batch();
  let updateCount = 0;

  for (const doc of usersSnapshot.docs) {
    const authUid = doc.id;
    const userData = doc.data();

    // Skip if already has UUID
    if (userData.id) {
      console.log(`User ${authUid} already has UUID: ${userData.id}`);
      continue;
    }

    // Generate deterministic UUID from authUid
    const uuid = authUidToUuid(authUid);

    console.log(`Adding UUID ${uuid} to user ${authUid} (${userData.displayName || 'no name'})`);
    batch.update(doc.ref, { id: uuid });
    updateCount++;
  }

  if (updateCount > 0) {
    await batch.commit();
    console.log(`✅ Updated ${updateCount} user documents with UUID field`);
  } else {
    console.log('✅ All users already have UUID field');
  }

  // Verify
  console.log('\nVerifying updates...');
  const verifySnapshot = await db.collection('users').get();
  verifySnapshot.docs.forEach(doc => {
    const data = doc.data();
    console.log(`User ${doc.id}: displayName="${data.displayName}", id="${data.id}"`);
  });

  process.exit(0);
}

addUuidToUsers().catch(error => {
  console.error('Error:', error);
  process.exit(1);
});
