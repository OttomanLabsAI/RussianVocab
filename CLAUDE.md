# Vocab Folio

A vocabulary card file: the website (`index.html`, served as Cloudflare
Workers static assets, no build step) and the native iOS/iPadOS app (`ios/`,
SwiftUI via XcodeGen) share one Firebase project and one data model. See
`README.md` and `ios/README.md`.

## Releases

Every push to `main` is a release, versioned vMAJOR.MINOR with the minor
bumped on every push. Develop on `claude/development`, then release to
`main`. The owner creates GitHub releases by hand from the release text in the
reply — never push tags. Append each release to the ledger below in the same
push.

## Prompt archive

`prompt text/` holds the records for the version currently in service -
nothing else. Shipping version N replaces the folder's contents wholesale,
in the same push that releases the version: remove the previous version's
folder(s) and add `prompt text/N/` containing `input.txt` (the prompt, byte
for byte), `output.txt` (the reply that shipped it, byte for byte),
`ai model.txt` (three lines: Anthropic / Claude / Fable 5 Max unless the
owner directs otherwise) and any input images or files the owner provided.
The files are owner-supplied records: never edit, reformat, trim or
regenerate them.

## Release ledger

| Tag | Title | Prompt |
|---|---|---|
| v1.0 | A dictionary and card file, boxed in ink | — |
| v1.1 | The site finds its home on Cloudflare | — |
| v1.2 | The header learns to breathe a little | — |
| v1.3 | Words now follow you across devices | — |
| v1.4 | The phone becomes a proper study companion | — |
| v1.5 | Finding and filing words in one tap | — |
| v1.6 | Every word remembers its moment | — |
| v1.7 | The site becomes an app that works anywhere | — |
| v1.8 | Whole lessons arrive in a single file | — |
| v1.9 | The card file learns when to ask again | — |
| v1.10 | The card file comes to iPhone and iPad | — |
| v1.11 | A new name, and a question about languages | 1 |
