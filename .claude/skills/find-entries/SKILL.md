---
name: find-entries
description: |
  Look for David Deutsch appearances that `list.yml` does not have — Apple's episode index, the back catalogue of every show already listed, the YouTube channels it names, then the web for what none of those reach.
  Reports candidates to judge; adds nothing on its own.
  Use when asked to "find new interviews", "what are we missing", "check for new appearances", "look for episodes", or invokes /find-entries.
allowed-tools: Bash(ruby *), Bash(curl *), Bash(grep *), Read, Edit, WebSearch, WebFetch
user-invocable: true
---

# Find entries the list is missing

`/audit-list` looks inward — every link it checks is one the list already has.
This looks outward, and the two halves of it are not interchangeable: a script sweeps the sources that can be enumerated, and the search that follows covers what no index holds.
Skipping the second half misses the appearances that never became a podcast episode.

## 1. Sweep

```sh
ruby .claude/skills/find-entries/scripts/find_entries.rb --json > /tmp/found.json
```

Two or three minutes. Four sources, each blind to what the others see:

- **Apple's episode index**, searched under four terms. The only source that can find a show he has never been on before.
- **The back catalogue of every show in the list**, whole. A show that has had him on once is the likeliest to have him on again, and this reads all of it, not the recent end.
  An episode qualifies by naming him in its title, unless the show has 20 episodes or fewer, where the whole catalogue is reported: a short feed is a show that is his or nearly all his, and its episodes are titled by subject.
- **The YouTube channels the list names**, through each channel's Atom feed — which carries only the last 15 uploads, so it finds what is new and nothing older.
- **Spotify**, searched under three terms, and asked for the catalogue of every show the list holds by an `open.spotify.com/show/` URL — those have no feed to find, and were reported unreachable every sweep until now.
  A Spotify hit is a lead, never audio: the file is theirs to play, and the 30-second `audio_preview_url` they do offer is worse than nothing to a feed that publishes what it records. Expect to find the same conversation elsewhere before adding it.

Spotify needs an application's own credentials in the environment — `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET`, made at [developer.spotify.com](https://developer.spotify.com/dashboard), no user login, free.
Without them that source is skipped and says so under `skipped_sources`; everything else sweeps as before.

His own channel is not among them. The list holds it as a single link under `other` and enumerates nothing from it: the anthology collects appearances, and a channel of his own uploads is covered by the link.
`--own-channel` sweeps it anyway, for the case that earns it — a talk he gave elsewhere that exists nowhere but there. Expect clips.

`--source itunes`, `--source spotify` or `--source feeds` narrows it; `--feed URL` adds a feed the list does not know about; `--since YYYY-MM-DD` keeps the report to what appeared after the last sweep; `--all` prints what was suppressed and why.

What comes back is sifted against `list.yml` by URL, by audio file, and by wording-plus-date, in that order of confidence.
The thresholds lean towards reporting: a duplicate costs one glance, a suppressed appearance is never seen again.

The report keys:

- `new` — the candidates to judge. `source` is `apple`, `spotify`, `rss` or `youtube`.
- `known_count` — sifted out as already listed. A large number here is the sweep working.
- `ignored_count` — dropped by `ignore.yml`, the judgements earlier runs already made.
- `unreachable_shows` — shows whose feed could not be found, so their catalogue was **not** swept. Not evidence there is nothing new on them.
- `skipped_sources` — a source that could not run at all, and why. Same warning, one level up.

## 2. Search for what the sweep cannot reach

The sweep enumerates feeds. These leave no feed to enumerate, so search for them:

- **A guest appearance on a YouTube channel that is not in the list.** The largest gap by far, because the channel sweep only reaches channels he has already been on.
- **A talk, panel or lecture** posted by a university, institute or conference.
- **A print or written interview**, which `print_interviews` collects and no audio index carries.
- **A show too new or too small for Apple's index.**

Search the year rather than the topic — `David Deutsch interview 2026`, `David Deutsch podcast <year>` — and search his name against the venues that recur in the list.
Cross-check anything found against `list.yml` before treating it as new:

```sh
grep -n -i '<show or title fragment>' list.yml
```

## 3. Judge each candidate

Three questions, in this order. The first two are where the sweep is weakest.

**Is it him?** Apple's index cannot tell one David Deutsch from another, and there are several — a direct-response copywriter who guests on marketing shows, a pastor, a wellness partner.
The show is usually the tell; the episode description settles it.

**Is it an appearance, or is it about him?** A book summary, review, reading or audiobook; a reaction episode; or two hosts discussing his work — none of these belong in the list, and they outnumber the real finds.
A title containing `David Deutsch` or one of his book titles is only a search hit, not evidence that he participated. Confirm participation from the episode description, credits or recording before reporting it as a candidate.
ToKCast is the hard case: Brett Hall's episodes are mostly commentary, and some are David answering a question directly.

**Is it the whole thing?** A preview, a trailer and a clip all carry the full episode's title.
Runtime discriminates where the title does not — `duration` is in the report for the sources that state it.

## 4. Add what survives

One at a time, through `/add-entry`, which resolves the audio, the artwork and the show and inserts the entry in order.
Give it the show's own episode page where there is one; an Apple URL works, and a `trackViewUrl` from the report is a fine input.

Report what was found before adding anything, and let the list's owner say which are wanted.
An appearance is a judgement about what belongs in an anthology, not a lookup.

## 5. Record the judgements

Anything dismissed for a reason that will hold next time goes in [`ignore.yml`](ignore.yml) — a namesake's show, a series of commentary titles.
Every run re-finds what the last run dismissed, and a report nobody reads to the end is worse than no report.

Matching there ignores case, punctuation and quote marks, so the patterns are written plainly.
Prefer a `titles` pattern over a `shows` entry when the show can still carry a real appearance: dropping ToKCast wholesale would hide the interviews among the commentary.

If a host or an index did something the sourcing doc does not describe, append it to [`docs/audio-sourcing.md`](../../../docs/audio-sourcing.md).
