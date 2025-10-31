const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function createTestFriendRequest() {
  try {
    // Create a fake sender user first
    const testSenderId = 'test-friend-abc123';
    await db.collection('users').doc(testSenderId).set({
      displayName: 'Test Friend',
      email: 'testfriend@example.com',
      photoURL: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    console.log('✅ Created test user');

    // Create incoming friend request
    const inviteRef = await db.collection('invites').add({
      senderId: testSenderId,
      recipientUserId: '9WZV2R982Qhwz07r1pxXTVbURMu2',
      recipientPhone: null,
      recipientEmail: null,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log('✅ Created friend request with ID:', inviteRef.id);
    console.log('🎉 Test friend request created successfully!');
    console.log('Now open your app and go to Profile → Friend Requests');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

createTestFriendRequest();
