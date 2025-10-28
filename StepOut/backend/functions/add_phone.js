const admin = require('firebase-admin');
const serviceAccount = require('../stepout-3db1a-firebase-adminsdk-t7uxm-0b4e29b9d6.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function addPhone() {
  try {
    const userRef = db.collection('users').doc('9WZV2R982Qhwz07r1pxXTVbURMu2');
    
    // First check if document exists
    const doc = await userRef.get();
    if (!doc.exists) {
      console.log('❌ User document does not exist');
      process.exit(1);
    }
    
    console.log('Current data:', doc.data());
    
    // Update
    await userRef.update({
      phoneNumber: '+12137065381'
    });
    console.log('✅ Phone number added successfully');
    
    // Verify
    const updated = await userRef.get();
    console.log('📱 Updated phoneNumber:', updated.data().phoneNumber);
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
  process.exit(0);
}

addPhone();
