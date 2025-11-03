const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp({
  projectId: 'stepout-3db1a',
});

const db = admin.firestore();

async function fixUser() {
  const authUid = '9WZV2R982Qhwz07r1pxXTVbURMu2';
  const correctUuid = '00000000-0000-0000-3226-0000646A1CC3';

  console.log('Fixing user document for authUid:', authUid);
  console.log('Setting correct UUID:', correctUuid);

  await db.collection('users').doc(authUid).update({
    id: correctUuid
  });

  console.log('✅ User document updated successfully!');

  // Verify the update
  const userDoc = await db.collection('users').doc(authUid).get();
  const userData = userDoc.data();
  console.log('\n✅ Verified - User ID is now:', userData.id);

  process.exit(0);
}

fixUser().catch(console.error);
