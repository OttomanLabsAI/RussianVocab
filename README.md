# RussianVocab — Russian Vocabulary Builder

A static site: search a 45,698-entry Russian–English dictionary, add words to a
personal file organised by part of speech, and (optionally) sign in so the file
syncs across devices. No server of your own — accounts and storage run on
Firebase directly from the browser.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole app (UI + logic) |
| `dict.json` | The dictionary (2.7 MB, fetched once and cached) |
| `vendor/firebase-bundle-2.js` | Firebase Auth + Firestore SDK plus the app's sync/sets/log API, bundled and pinned |
| `vendor/fsrs-bundle.js` | The ts-fsrs spaced-repetition scheduler, bundled and pinned |
| `tools/` | Source + build script for the vendor bundles (`npm install && npm run build`, commit the output; not needed to deploy) |
| `config.js` | **Your Firebase keys go here** |
| `firestore.rules` | Security rules — paste into the Firebase console |
| `wrangler.jsonc`, `_headers`, `.assetsignore` | Cloudflare deployment: project config, cache headers, files kept off the site |

`config.js` carries the project's public client keys. Without them the site
falls back to device-only mode: words save in the browser and the Sign in
button explains that accounts aren't set up. Nothing breaks.

## Run it locally

```
python3 -m http.server 8000
# open http://localhost:8000
```

(It must be served over http — opening index.html as a file:// URL blocks the
dictionary fetch.)

## Design

The interface follows the OttomanLabsAI "boxed-mosaic editorial" system: white
paper, ink `#111111`, two greys (`#5A5A5A`, `#A9A9A9`) and a single burgundy
accent `#B01018` reserved for warnings and small hover flourishes. Everything
lives in square-cornered 1px ink boxes on a 14px-gap mosaic; list rows separate
with dashed hairlines. Three type voices only: Afacad Flux for uppercase
micro-labels and controls, Newsreader for prose and italic hints, Prata for
headings. Dark mode is a pure token inversion behind the ◐ button in the
header, persisted in localStorage. Keep new UI inside these tokens — nothing
may hardcode a colour that breaks under inversion.

## Set up accounts (one-time, ~10 minutes)

1. **Create a Firebase project** at console.firebase.google.com (free Spark plan
   is plenty: 50k monthly auth users, 1 GB Firestore).
2. **Authentication → Sign-in method**: enable **Email/Password** and
   (optionally) **Google**.
3. **Authentication → Settings → Authorized domains**: add the domain you'll
   host on (localhost is pre-authorized). Google sign-in won't work from
   unlisted domains.
4. **Firestore Database → Create database** (production mode, pick a region
   near your users, e.g. europe-west2 for London).
5. **Firestore → Rules**: replace the contents with `firestore.rules` from this
   repo and Publish. This locks every user to their own data.
6. **Project settings → General → Your apps → Add app → Web**: register the
   app, copy the config object, and paste its values into `config.js`
   (apiKey, authDomain, projectId, appId). These keys are safe to ship in
   client code — the rules are what protect the data.

## Deploy to Cloudflare

The repo is configured as a Cloudflare Workers static-assets project
(`wrangler.jsonc`): only the site files are served — repo files like this
README are excluded via `.assetsignore` — and `_headers` sets the cache
policy (long/immutable for `dict.json` and `vendor/*`; rename those files
when they change, short cache for `index.html` and `config.js`).

**Automatic deploys (recommended):** in the Cloudflare dashboard go to
*Workers & Pages → Create → Workers → Import a repository*, pick this repo,
and accept the detected settings (no build command, deploy command
`npx wrangler deploy`). Every push to the default branch then deploys to
`russianvocab.<your-subdomain>.workers.dev`; custom domains attach in the
worker's Settings → Domains & Routes.

**One-off deploy from your machine:**

```
npx wrangler login
npx wrangler deploy
```

After the first deploy, add the `workers.dev` URL (and any custom domain) to
Firebase **Authentication → Settings → Authorized domains**, or sign-in will
be refused from the live site.

## Installable app (PWA)

The site is a progressive web app: `manifest.json` + `icons/` make it
installable ("Add to Home Screen" on iOS Safari, the install prompt on
Android/desktop Chrome), and `sw.js` caches the app shell and the whole
dictionary so it opens and searches offline. Word edits made offline save
locally and sync the next time the device is online and signed in.

When changing any precached file (`index.html`, `config.js`, `dict.json`,
the vendor bundle), bump `VERSION` at the top of `sw.js` in the same push so
installed clients pick up the new copy.

## How syncing behaves

- Signed out: words auto-save in the browser (localStorage).
- First sign-in on a device with words: the device seeds the account.
- Sign-in where the account and the device **both** have words and they differ:
  the app asks — **Use account / Merge both / Keep this device**. If the device
  hasn't changed since its last sync, the account version is adopted silently.
- While signed in: saves are debounced to Firestore (~1s) and flushed when the
  tab closes. Status is shown next to the account button.
- Conflict model is last-write-wins per save — fine for one person across
  devices, not built for simultaneous editing.

## Review mode (FSRS)

The word file doubles as a spaced-repetition queue, scheduled by
[ts-fsrs](https://github.com/open-spaced-repetition/ts-fsrs) with default
parameters. A word's card state lives on the word object itself as `c`
(state, due, stability, difficulty, reps, lapses, learning step, last
review — compact keys), so it syncs through the existing chunk mechanism
with no schema migration: **a word without `c` is a new card**, which is
also what makes the change reversible — delete `c` and you're back to a
plain word list. New cards enter at a user-adjustable daily cap (default
20, `settings.newPerDay`); the day's intake is tracked in
`settings.introDay`/`introCount`. Every grade appends to a per-day log for
future parameter optimisation, buffered locally when offline
(`pendingLog` in localStorage) and flushed when back online — a rating is
never lost to a dropped connection.

## Pronunciation audio

The dictionary data carries no recordings, so audio is resolved at play
time: single words first check Wikimedia Commons for a Wiktionary
`Ru-<word>.ogg` recording (cached by the service worker once heard);
phrases and anything without a recording fall through silently to browser
SpeechSynthesis with a ru-RU voice. Auto-play on reveal during reviews is
a setting, default off.

## Word sets (teacher → student)

A signed-in user picks words from their file, names the set, and gets a
7-character code (unambiguous alphabet — no 0/O/1/I/l) plus a share link
at `/s/CODE`. Redeeming merges the set's words into the redeemer's file:
duplicates skipped, imported words tagged with the set name, newcomers
entering the review queue as new cards under the daily cap. Sets are
snapshots — later edits by the creator never touch a student's file.

## Data model

```
users/{uid}                    → { v, chunks, count, settings: {group, newPerDay,
                                   introDay, introCount, autoSay}, updated }
users/{uid}/w/{0..n}           → { words: [ up to 1,000 word objects ] }
users/{uid}/log/{YYYYMMDD}     → { e: [ {w, r, at, el, sc, st} ], updated }   ← review log
sets/{CODE}                    → { owner, name, desc, words[], count, created }
sets/{CODE}/redemptions/{uid}  → { user, at }
```

Words are chunked at 1,000 per document to stay far under Firestore's 1 MB
document limit — no practical ceiling on list size. Each word object:
`{ ru, ac, pr, en, pos, g, x, t, c }` (word, stress-marked form,
pronunciation, translation, part of speech, group, gender/aspect extra,
added-at epoch ms, FSRS card state — `t` and `c` are absent on words that
predate those features). The redemptions subcollection is one doc per
redeeming user, so a per-student progress dashboard can be added later
without migration.

**After deploying a version that adds collections (like this one): re-paste
`firestore.rules` into the Firebase console and Publish** — sets and review
logs are denied by the old rules until you do.

## Releases

Every push to the default branch is a release, tagged in an ascending
vMAJOR.MINOR sequence (v1.0, v1.1, …). Each push bumps the minor; a major bump
is reserved for a ground-up overhaul. Tags and GitHub releases are created
manually by the repo owner from the release text supplied with each push.

## Licensing / attribution

Dictionary data: [OpenRussian](https://en.openrussian.org) via
github.com/Badestrand/russian-dictionary — **CC-BY-SA**. Keep the footer
attribution visible; the dataset itself remains share-alike. Frequency ranking
derived from the OpenSubtitles corpus (hermitdave/FrequencyWords).

Code: MIT (see `LICENSE`).

## Development

`window.USE_EMULATORS = true` in `config.js` connects to local Firebase
emulators (auth :9099, firestore :8080) — leave it `false` in production.
