const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp({
  projectId: 'stepout-3db1a',
});

const db = admin.firestore();

async function checkUser() {
  const authUid = '9WZV2R982Qhwz07r1pxXTVbURMu2';

  console.log('Checking user document for authUid:', authUid);

  const userDoc = await db.collection('users').doc(authUid).get();

  if (!userDoc.exists) {
    console.log('❌ User document does not exist!');
    return;
  }

  const userData = userDoc.data();
  console.log('\n✅ User document found:');
  console.log(JSON.stringify(userData, null, 2));
  console.log('\nUser ID field:', userData.id);
  console.log('Expected UUID from iOS query: 00000000-0000-0000-3226-0000646A1CC3');

  process.exit(0);
}

checkUser().catch(console.error);
