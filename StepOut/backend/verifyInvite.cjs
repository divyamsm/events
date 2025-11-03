const admin = require('./functions/node_modules/firebase-admin');

admin.initializeApp();
const db = admin.firestore();

async function verifyInvite() {
  const eventId = '41919272-1872-450F-8C2A-362526B04D57';
  const divyamAuthUid = 'hRDQYaLO7fZSkzBkQVil4yJ1MRz2';

  console.log(`Checking event ${eventId} for invite to Divyam (${divyamAuthUid})...\n`);

  const eventDoc = await db.collection('events').doc(eventId).get();

  if (!eventDoc.exists) {
    console.log('❌ Event not found!');
    process.exit(1);
  }

  const eventData = eventDoc.data();
  console.log('Event Details:');
  console.log(`  Title: ${eventData.title}`);
  console.log(`  Owner: ${eventData.ownerId}`);
  console.log(`  Created At: ${eventData.createdAt?.toDate()}`);
  console.log(`  Visibility: ${eventData.visibility}`);
  console.log();

  const sharedInviteFriendIds = eventData.sharedInviteFriendIds || [];
  console.log(`Shared Invite Friend IDs (${sharedInviteFriendIds.length}):`);
  sharedInviteFriendIds.forEach(id => {
    console.log(`  - ${id}${id === divyamAuthUid ? ' ← Divyam!' : ''}`);
  });
  console.log();

  if (sharedInviteFriendIds.includes(divyamAuthUid)) {
    console.log('✅ SUCCESS! Divyam received the invite!');
  } else {
    console.log('❌ Divyam NOT found in shared invites');
  }

  process.exit(0);
}

verifyInvite().catch(error => {
  console.error('Error:', error);
  process.exit(1);
});
