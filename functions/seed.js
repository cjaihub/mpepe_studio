const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
admin.initializeApp({ projectId: "mpepe-2b4bd" });

const db = getFirestore();

async function seed() {
  await db.collection('users').doc('crown_uid').set({
    username: 'Crown',
    displayName: 'Crown',
    profilePhotoUrl: 'https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?q=80&w=1000&auto=format&fit=crop',
    role: 'user', status: 'active',
  });
  console.log('Seeded Crown user');

  await db.collection('users').doc('angel_uid').set({
    username: 'Angel',
    displayName: 'Angel',
    profilePhotoUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?q=80&w=1000&auto=format&fit=crop',
    role: 'user', status: 'active',
  });
  console.log('Seeded Angel user');

  await db.collection('content').doc('video_crown').set({
    authorId: 'crown_uid',
    description: 'Crown exploring the new studio! #onerova #crown',
    mediaUrl: 'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    type: 'short_video', 
    createdAt: FieldValue.serverTimestamp(),
    viewCount: 0, likeCount: 0, commentCount: 0, saveCount: 0, shareCount: 0,
    hashtags: ['onerova', 'crown'],
    permissions: {allowComments: true, allowDuet: true},
  });
  console.log('Seeded Crown video');

  await db.collection('content').doc('video_angel').set({
    authorId: 'angel_uid',
    description: 'Angel sharing some vibes! #onerova #angel',
    mediaUrl: 'https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    type: 'short_video', 
    createdAt: FieldValue.serverTimestamp(),
    viewCount: 0, likeCount: 0, commentCount: 0, saveCount: 0, shareCount: 0,
    hashtags: ['onerova', 'angel'],
    permissions: {allowComments: true, allowDuet: true},
  });
  console.log('Seeded Angel video');
}

seed().catch(console.error);
