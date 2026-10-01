// Source for vendor/firebase-bundle-4.js — the pinned Firebase Auth+Firestore
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
  getDoc, getDocs, setDoc, addDoc, deleteDoc, writeBatch, serverTimestamp, arrayUnion,
  query, where, getCountFromServer, onSnapshot,
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
    stats: data.stats || {},
    chunks: data.chunks || parts.length,
  };
}

// stats = { days: { YYYYMMDD: { n: reviews, a: agains } } } — the daily
// aggregate behind the progress calendar; the per-day log holds the detail.
export async function saveCloud(uid, words, settings, prevChunks, stats){
  const batch = writeBatch(db);
  const n = Math.max(1, Math.ceil(words.length / CHUNK));
  batch.set(doc(db, "users", uid), {
    v: 1, chunks: n, count: words.length,
    settings: settings || {}, stats: stats || {}, updated: serverTimestamp(),
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

// ---- Teachers and students
// teachers/{CODE} → {uid, email}: a teacher's code, handed to students.
// users/{teacher}/students/{student} → {email, code, at}: the consent record,
//   written by the student, which is what the rules check for teacher access.
// users/{student}/teachers/{teacher} → {email, code, at}: the student's own list.
// users/{student}/inbox/{id} → {from, email, list, add[], remove[], at}: a
//   change a teacher sent; the student's app applies it and deletes it.
function toMs(ts){ return ts && ts.toMillis ? ts.toMillis() : 0; }

export async function createTeacherCode(uid, email, code){
  await setDoc(doc(db, "teachers", code), { uid: uid, email: email || "", created: serverTimestamp() });
}

export async function myTeacherCode(uid){
  const snaps = await getDocs(query(collection(db, "teachers"), where("uid", "==", uid)));
  let code = null;
  snaps.forEach(s => { if (!code) code = s.id; });
  return code;
}

export async function getTeacher(code){
  const s = await getDoc(doc(db, "teachers", code));
  return s.exists() ? { uid: s.data().uid, email: s.data().email || "" } : null;
}

// The student links themself to a teacher: both records in one batch.
export async function linkTeacher(uid, email, code){
  const t = await getTeacher(code);
  if (!t) throw new Error("No teacher has the code " + code + ".");
  if (t.uid === uid) throw new Error("That is your own teacher code.");
  const batch = writeBatch(db);
  batch.set(doc(db, "users", uid, "teachers", t.uid), { email: t.email, code: code, at: serverTimestamp() });
  batch.set(doc(db, "users", t.uid, "students", uid), { email: email || "", code: code, at: serverTimestamp() });
  await batch.commit();
  return t;
}

// Ending the link removes both records; the rules let either side do it.
export async function unlinkTeacher(uid, tuid){
  const batch = writeBatch(db);
  batch.delete(doc(db, "users", uid, "teachers", tuid));
  batch.delete(doc(db, "users", tuid, "students", uid));
  await batch.commit();
}

export async function removeStudent(uid, suid){
  const batch = writeBatch(db);
  batch.delete(doc(db, "users", uid, "students", suid));
  batch.delete(doc(db, "users", suid, "teachers", uid));
  await batch.commit();
}

export async function listTeachers(uid){
  const snaps = await getDocs(collection(db, "users", uid, "teachers"));
  const out = [];
  snaps.forEach(s => out.push({ uid: s.id, email: s.data().email || "", code: s.data().code || "" }));
  return out;
}

// Each student's head doc gives the word count and last save without
// pulling the whole file; the file itself comes through loadCloud(suid).
export async function listStudents(uid){
  const snaps = await getDocs(collection(db, "users", uid, "students"));
  const out = [];
  snaps.forEach(s => out.push({ uid: s.id, email: s.data().email || "", at: toMs(s.data().at),
    count: 0, updated: 0, stats: {} }));
  for (const st of out){
    try {
      const h = await getDoc(doc(db, "users", st.uid));
      if (h.exists()){
        const d = h.data();
        st.count = d.count || 0; st.updated = toMs(d.updated); st.stats = d.stats || {};
      }
    } catch (e){}
  }
  return out;
}

export async function sendToStudent(suid, item){
  const ref = await addDoc(collection(db, "users", suid, "inbox"),
    Object.assign({}, item, { at: serverTimestamp() }));
  return ref.id;
}

export async function listPending(suid, tuid){
  const snaps = await getDocs(query(collection(db, "users", suid, "inbox"), where("from", "==", tuid)));
  const out = [];
  snaps.forEach(s => out.push(Object.assign({ id: s.id }, s.data(), { at: toMs(s.data().at) })));
  return out;
}

// Live: fires with everything waiting whenever the inbox changes.
export function watchInbox(uid, cb){
  return onSnapshot(collection(db, "users", uid, "inbox"), snap => {
    const items = [];
    snap.forEach(s => items.push(Object.assign({ id: s.id }, s.data(), { at: toMs(s.data().at) })));
    cb(items);
  }, () => {});
}

export function clearInbox(uid, id){ return deleteDoc(doc(db, "users", uid, "inbox", id)); }

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
