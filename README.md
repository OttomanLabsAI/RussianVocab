# Vocab Folio

A vocabulary card file, on the web and as a native iPhone/iPad app: search a
built-in dictionary, add words to a personal file organised by part of speech,
review them with spaced repetition, and (optionally) sign in so the file syncs
across devices. The first language pair is English → Russian (a 45,698-entry
dictionary); more are planned. No server of your own — accounts and storage
run on Firebase directly from the browser and the app.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole app (UI + logic) |
| `dict.json` | The dictionary (2.7 MB, fetched once and cached) |
| `vendor/firebase-bundle-4.js` | Firebase Auth + Firestore SDK plus the app's sync/sets/log/teaching API, bundled and pinned |
| `vendor/fsrs-bundle.js` | The ts-fsrs spaced-repetition scheduler, bundled and pinned |
| `tools/` | Source + build script for the vendor bundles (`npm install && npm run build`, commit the output; not needed to deploy) |
| `ios/` | The native iOS/iPadOS app (SwiftUI, XcodeGen spec, tests) — see `ios/README.md` |
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
`russianvocab.<your-subdomain>.workers.dev` (the worker keeps its original
name so the address doesn't change; a custom domain can carry the Vocab Folio
name — attach it in the worker's Settings → Domains & Routes).

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

## Languages

On first visit the app asks for the learner's language, then the language
they are learning, listing only pairs that have a dictionary behind them
(`LANGS`/`PAIRS` in `index.html`, `Languages.swift` on iOS — keep the two in
step). Today that is English → Russian. The choice is stored as
`settings.native` / `settings.learning`, so it syncs to the account; a device
that picks before signing in carries the choice up, and signing in on a new
device brings it down. The header's language label reopens the picker.

## Lists and the Saved tab

Every word sits in a list (its `g`). The **Lists** page renames a list
(every word follows, as do the current list and deck), creates an empty one,
or deletes one — keeping its words as ungrouped, or dropping them too. Lists
the learner created live in `settings.lists` so an empty list survives until
it is deleted; the dropdown and the review decks are the union of that and
the words' groups.

The **Saved** tab at the top of the rail is everything the learner actually
added — from the dictionary, a JSON file, a set or a teacher — newest first,
each row naming its list and, for teacher-sent words, who sent it. The
starter file every new copy gets is left out: a word is "saved" when it
carries an added-at stamp (`t`) or isn't one of the starter keys. The site
opens on this tab once anything is saved.

## Review mode (FSRS)

The word file doubles as a spaced-repetition queue, scheduled by
[ts-fsrs](https://github.com/open-spaced-repetition/ts-fsrs) with default
parameters (FSRS-6, the algorithm Anki uses). A word's card state lives on
the word object itself as `c`
(state, due, stability, difficulty, reps, lapses, learning step, last
review — compact keys), so it syncs through the existing chunk mechanism
with no schema migration: **a word without `c` is a new card**, which is
also what makes the change reversible — delete `c` and you're back to a
plain word list. New cards enter at a user-adjustable daily cap (default
20, `settings.newPerDay`); the day's intake is tracked in
`settings.introDay`/`introCount`. A session is everything due plus a random
pick of that day's new cards, shuffled together — new words mixed among
reviews, never in file order. Word lists double as **decks** — pick one
in the review screen (`settings.deck`) to review it alone. Every grade
appends to a per-day log for future parameter optimisation, buffered
locally when offline (`pendingLog` in localStorage) and flushed when back
online — a rating is never lost to a dropped connection.

Grading is a yes/no. After revealing the card the question is *Did you get
it right?* — **Correct** or **Incorrect**, which are Good and Again
underneath, so FSRS still does the scheduling. Tick **Multiple choice** at
the top of the settings and each card instead offers five choices — the
answer plus four others, drawn from the learner's own file (same part of
speech first) and then common dictionary words, never two alike; the pick
decides correct or not, the right answer is shown, and Next moves on.
Keys: space reveals or moves on, 1/2 are Incorrect/Correct, 1–5 pick a
choice.

Two switches sit with the deck: **Direction** flips the card to show the
English first and ask for the Russian (`settings.reverse`; the card's FSRS
state is shared, so a word's schedule is one schedule whichever way it is
asked), and **Added** limits the session to words added today or in the
last 7/30/90 days (`settings.since`, counted from local midnight) — the
added-at stamps are what make "review this week's words" possible. The due
badge follows both filters.

## Progress

The Progress panel is the Anki-style stats page: today's count and
again-rate, card counts (new / learning / young / mature — mature meaning
an interval of 21+ days), a GitHub-style calendar of reviews over the last
12 months, reviews due over the next 30 days, and all-time totals with
streaks. It runs off `stats.days` on the user doc — a `{YYYYMMDD: {n, a}}`
aggregate bumped on every grade and merged by taking the larger count per
day, so history survives whichever word file wins a sync.

## iOS and iPadOS app

`ios/` holds a native SwiftUI app that shares the same Firebase project and
data — sign in with the website's email and password and your file, lists,
review history and progress are already there. Same dictionary (it bundles
`dict.json`), the official Swift FSRS with the same FSRS-6 parameters, same
design tokens and fonts. See `ios/README.md` for the Mac build steps
(XcodeGen → Xcode), the parity tests that prove the two schedulers agree,
and the Xcode Cloud setup that turns every push to `main` into a TestFlight
build (`ios/ci_scripts/ci_post_clone.sh` generates the project on the build
machine).

## Pronunciation audio

The dictionary data carries no recordings, so audio is resolved at play
time: single words first check Wikimedia Commons for a Wiktionary
`Ru-<word>.ogg` recording (cached by the service worker once heard);
phrases and anything without a recording fall through silently to browser
SpeechSynthesis with a ru-RU voice. Auto-play on reveal during reviews is
a checkbox in the review settings ("Play the word on reveal"), default off.

## Word sets (teacher → student)

A signed-in user picks words from their file, names the set, and gets a
7-character code (unambiguous alphabet — no 0/O/1/I/l) plus a share link
at `/s/CODE`. Redeeming merges the set's words into the redeemer's file:
duplicates skipped, imported words tagged with the set name, newcomers
entering the review queue as new cards under the daily cap. Sets are
snapshots — later edits by the creator never touch a student's file.

## Teacher accounts

Any account can be a teacher: **Teaching → Create my teacher code** mints a
7-character code (`teachers/{CODE}` → `{uid, email}`). A student enters it
under **Teaching → My teachers**, which writes two records in one batch —
`users/{teacher}/students/{student}` (the consent record, which only the
student can create and which the rules check) and
`users/{student}/teachers/{teacher}` (the student's own list). Either side can
end the link. A teacher may have any number of students, a student any number
of teachers.

A linked teacher can read the student's file (`users/{student}` and its `w`
chunks) and sees each student's word count, last save and last review, and
their whole file by list. Adding or removing words never writes the student's
file directly: the teacher sends an item to `users/{student}/inbox` —
`{from, email, list, add[], remove[], at}` — and the student's app (web or
iOS) applies it the moment it is open, stamps each word with the time it was
sent and the teacher's email (`t`, `by`), files it under the list the teacher
named, tells the student, and deletes the item. The student's own device stays
the only writer of its word file, so a teacher working while the student is
mid-session can't overwrite anything. The teacher sees what is still waiting
and can withdraw it. Removals are sent the same way (words marked "removal
sent" until applied).

## Data model

```
users/{uid}                    → { v, chunks, count, settings: {group, lists[], newPerDay,
                                   introDay, introCount, autoSay, deck, reverse, since,
                                   native, learning},
                                   stats: { days: { YYYYMMDD: {n, a} } }, updated }
users/{uid}/w/{0..n}           → { words: [ up to 1,000 word objects ] }
users/{uid}/log/{YYYYMMDD}     → { e: [ {w, r, at, el, sc, st} ], updated }   ← review log
users/{uid}/students/{suid}    → { email, code, at }      ← uid is the teacher; written by the student
users/{uid}/teachers/{tuid}    → { email, code, at }      ← uid is the student
users/{uid}/inbox/{id}         → { from, email, list, add[], remove[], at }   ← applied and deleted by the student's app
teachers/{CODE}                → { uid, email, created }
sets/{CODE}                    → { owner, name, desc, words[], count, created }
sets/{CODE}/redemptions/{uid}  → { user, at }
```

Words are chunked at 1,000 per document to stay far under Firestore's 1 MB
document limit — no practical ceiling on list size. Each word object:
`{ ru, ac, pr, en, pos, g, x, t, c, by }` (word, stress-marked form,
pronunciation, translation, part of speech, group, gender/aspect extra,
added-at epoch ms, FSRS card state, sender's email for teacher-sent words —
`t`, `c` and `by` are absent where they don't apply). The redemptions subcollection is one doc per
redeeming user, so a per-student progress dashboard can be added later
without migration.

**After deploying a version that adds collections (like this one): re-paste
`firestore.rules` into the Firebase console and Publish** — teacher links,
inboxes, sets and review logs are denied by the old rules until you do.

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
