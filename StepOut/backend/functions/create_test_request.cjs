const admin = require('firebase-admin');

// Initialize Firebase Admin (will use Application Default Credentials)
admin.initializeApp({
  projectId: 'stepout-3db1a'
});

const db = admin.firestore();

async function createTestFriendRequest() {
  try {
    // Create a fake sender user first
    const testSenderId = 'test-friend-abc123';
    await db.collection('users').doc(testSenderId).set({
      displayName: 'Test Friend',
      username: 'testfriend',
      email: 'testfriend@example.com',
      photoURL: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    console.log('✅ Created test user: Test Friend');

    // Create incoming friend request to you
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
    console.log('');
    console.log('🎉 Test data created successfully!');
    console.log('📱 Now open your app and:');
    console.log('   1. Go to Profile tab');
    console.log('   2. Tap Friend Requests button (top-left)');
    console.log('   3. You should see "Test Friend wants to be friends"');
    console.log('   4. Try accepting it!');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

createTestFriendRequest();
