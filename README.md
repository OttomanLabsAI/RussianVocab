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
| `vendor/firebase-bundle.js` | Firebase Auth + Firestore SDK, bundled and pinned |
| `config.js` | **Your Firebase keys go here** |
| `firestore.rules` | Security rules — paste into the Firebase console |
| `wrangler.jsonc`, `_headers`, `.assetsignore` | Cloudflare deployment: project config, cache headers, files kept off the site |

Until `config.js` is filled in, the site runs in device-only mode: words save in
the browser, Export/Import JSON works, and the Sign in button explains that
accounts aren't set up. Nothing breaks.

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

## How syncing behaves

- Signed out: words auto-save in the browser (localStorage), plus manual
  Export/Import JSON.
- First sign-in on a device with words: the device seeds the account.
- Sign-in where the account and the device **both** have words and they differ:
  the app asks — **Use account / Merge both / Keep this device**. If the device
  hasn't changed since its last sync, the account version is adopted silently.
- While signed in: saves are debounced to Firestore (~1s) and flushed when the
  tab closes. Status is shown next to the account button.
- Conflict model is last-write-wins per save — fine for one person across
  devices, not built for simultaneous editing.

## Data model

```
users/{uid}          → { v, chunks, count, settings: {group}, updated }
users/{uid}/w/{0..n} → { words: [ up to 1,000 word objects ] }
```

Words are chunked at 1,000 per document to stay far under Firestore's 1 MB
document limit — no practical ceiling on list size. Each word object:
`{ ru, ac, pr, en, pos, g, x }` (word, stress-marked form, pronunciation,
translation, part of speech, group, gender/aspect extra).

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
