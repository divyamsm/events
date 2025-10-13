const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function seedProfile(userId) {
  const userRef = db.collection('users').doc(userId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  await userRef.set(
    {
      displayName: 'StepOut Friend',
      username: 'friend',
      usernameLowercase: 'friend',
      bio: 'Seeded profile for development',
      createdAt: now,
      updatedAt: now
    },
    { merge: true }
  );

  console.log(`Seeded profile for ${userId}`);
}

const userId = process.env.SEED_PROFILE_USER_ID;
if (!userId) {
  console.error('Must set SEED_PROFILE_USER_ID env var');
  process.exit(1);
}

seedProfile(userId)
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
