// Source for vendor/firebase-bundle-2.js — the pinned Firebase Auth+Firestore
// bundle plus this app's sync API. Rebuild with: npm run build (see tools/README.md).
// The users/{uid} layout must stay wire-compatible with existing accounts:
// users/{uid} → {v, chunks, count, settings, updated}, users/{uid}/w/{n} → {words}.
import { initializeApp } from "firebase/app";
import {
  getAuth, connectAuthEmulator, onAuthStateChanged,
  signInWithEmailAndPassword, createUserWithEmailAndPassword,
  signInWithPopup, GoogleAuthProvider, sendPasswordResetEmail, signOut,
} from "firebase/auth";
import {
  getFirestore, connectFirestoreEmulator, doc, collection,
  getDoc, getDocs, setDoc, writeBatch, serverTimestamp, arrayUnion,
  query, where, getCountFromServer,
} from "firebase/firestore";

let auth, db;

export function init(config, emulators){
  const app = initializeApp(config);
  auth = getAuth(app);
  db = getFirestore(app);
  if (emulators){
    connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
    connectFirestoreEmulator(db, "127.0.0.1", 8080);
  }
}

export function onUser(cb){ return onAuthStateChanged(auth, cb); }
export function signInEmail(email, pass){ return signInWithEmailAndPassword(auth, email, pass); }
export function signUpEmail(email, pass){ return createUserWithEmailAndPassword(auth, email, pass); }
export function signInGoogle(){ return signInWithPopup(auth, new GoogleAuthProvider()); }
export function resetPassword(email){ return sendPasswordResetEmail(auth, email); }
export function doSignOut(){ return signOut(auth); }

const CHUNK = 1000;

export async function loadCloud(uid){
  const head = await getDoc(doc(db, "users", uid));
  if (!head.exists()) return null;
  const data = head.data();
  const snaps = await getDocs(collection(db, "users", uid, "w"));
  const parts = [];
  snaps.forEach(s => parts.push([parseInt(s.id, 10) || 0, s.data().words || []]));
  parts.sort((a, b) => a[0] - b[0]);
  return {
    words: [].concat(...parts.map(p => p[1])),
    settings: data.settings || {},
    chunks: data.chunks || parts.length,
  };
}

export async function saveCloud(uid, words, settings, prevChunks){
  const batch = writeBatch(db);
  const n = Math.max(1, Math.ceil(words.length / CHUNK));
  batch.set(doc(db, "users", uid), {
    v: 1, chunks: n, count: words.length,
    settings: settings || {}, updated: serverTimestamp(),
  });
  for (let i = 0; i < n; i++)
    batch.set(doc(db, "users", uid, "w", String(i)),
      { words: words.slice(i * CHUNK, (i + 1) * CHUNK) });
  for (let i = n; i < (prevChunks || 0); i++)
    batch.delete(doc(db, "users", uid, "w", String(i)));
  await batch.commit();
  return n;
}

// Append-only review log, one doc per day: users/{uid}/log/{YYYYMMDD} → {e:[...]}.
export async function appendReviewLog(uid, day, entries){
  await setDoc(doc(db, "users", uid, "log", day),
    { e: arrayUnion(...entries), updated: serverTimestamp() }, { merge: true });
}

// Shareable sets: sets/{code} → snapshot of words at creation time.
// Redemptions live under sets/{code}/redemptions/{uid} — one doc per redeemer,
// so a per-student dashboard can be layered on later without migration.
export async function createSet(uid, code, name, desc, words){
  await setDoc(doc(db, "sets", code), {
    owner: uid, name: name, desc: desc || "",
    words: words, count: words.length, created: serverTimestamp(),
  });
}

export async function getSet(code){
  const snap = await getDoc(doc(db, "sets", code));
  return snap.exists() ? snap.data() : null;
}

export async function listMySets(uid){
  const snaps = await getDocs(query(collection(db, "sets"), where("owner", "==", uid)));
  const out = [];
  snaps.forEach(s => {
    const d = s.data();
    out.push({ code: s.id, name: d.name, count: d.count,
      created: d.created && d.created.toMillis ? d.created.toMillis() : 0 });
  });
  out.sort((a, b) => b.created - a.created);
  return out;
}

export async function redeemSet(code, uid){
  await setDoc(doc(db, "sets", code, "redemptions", uid),
    { user: uid, at: serverTimestamp() });
}

export async function countRedemptions(code){
  const c = await getCountFromServer(collection(db, "sets", code, "redemptions"));
  return c.data().count;
}

export function friendlyError(e){
  return {
    "auth/invalid-email": "That email address doesn't look right.",
    "auth/email-already-in-use": "An account with that email already exists — try signing in.",
    "auth/weak-password": "Password needs at least 6 characters.",
    "auth/missing-password": "Enter a password.",
    "auth/invalid-credential": "Wrong email or password.",
    "auth/wrong-password": "Wrong email or password.",
    "auth/user-not-found": "No account with that email — create one?",
    "auth/too-many-requests": "Too many attempts — wait a minute and try again.",
    "auth/network-request-failed": "Network problem — check your connection.",
    "auth/popup-closed-by-user": "Sign-in window was closed before finishing.",
  }[e && e.code || ""] || (e && e.message) || "Something went wrong.";
}
