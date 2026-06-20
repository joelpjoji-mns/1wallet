const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');

// Initialize Firebase Admin with the default credentials
admin.initializeApp({
  projectId: 'joel-wallet-v1',
});

const db = getFirestore();

async function checkUserData() {
  const userId = '1j5KLHMzWnPzaHzwEeLeU1uZ0F82';
  
  console.log(`Checking data for user: ${userId}`);
  
  // Check users doc
  const userDoc = await db.collection('users').doc(userId).get();
  console.log(`User doc exists: ${userDoc.exists}`);
  if (userDoc.exists) console.log(userDoc.data());

  // Check legacy collections
  const accounts = await db.collection(`users/${userId}/accounts`).get();
  console.log(`Legacy accounts count: ${accounts.size}`);
  accounts.forEach(doc => {
    console.log(doc.id, doc.data().name, "isArchived:", doc.data().isArchived, "includeInTotals:", doc.data().includeInTotals);
  });

  const transactions = await db.collection(`users/${userId}/transactions`).get();
  console.log(`Legacy transactions count: ${transactions.size}`);

  // Check new wallet_backups
  const backups = await db.collection(`users/${userId}/wallet_backups`).get();
  console.log(`wallet_backups count: ${backups.size}`);
}

checkUserData().catch(console.error);
