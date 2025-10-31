const admin = require('./functions/node_modules/firebase-admin');

// Initialize Firebase Admin
admin.initializeApp();

const db = admin.firestore();

async function cleanupFriends() {
  console.log('Starting cleanup of friends collection...');

  // Get all documents in friends collection
  const friendsSnapshot = await db.collection('friends').get();

  console.log(`Found ${friendsSnapshot.docs.length} friend documents`);

  // Delete documents where userId is NOT the correct Firebase Auth UID
  const correctUserId = '9WZV2R982Qhwz07r1pxXTVbURMu2';

  const batch = db.batch();
  let deleteCount = 0;

  friendsSnapshot.docs.forEach(doc => {
    const data = doc.data();
    // Delete if userId doesn't match the correct Firebase Auth UID
    if (data.userId !== correctUserId) {
      console.log(`Deleting friend doc ${doc.id} with userId: ${data.userId}`);
      batch.delete(doc.ref);
      deleteCount++;
    } else {
      console.log(`Keeping friend doc ${doc.id} - correct userId`);
    }
  });

  if (deleteCount > 0) {
    await batch.commit();
    console.log(`Deleted ${deleteCount} fake friend documents`);
  } else {
    console.log('No documents to delete');
  }

  console.log('Cleanup complete!');
  process.exit(0);
}

cleanupFriends().catch(error => {
  console.error('Error during cleanup:', error);
  process.exit(1);
});
