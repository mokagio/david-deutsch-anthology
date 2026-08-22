---
name: audit-list
description: |
  Check every link in `list.yml` and find the audio and artwork the feed needs but the list does not record.
  Adds the `audio` block and `image_url` to entries where they were found; reports dead links without touching them.
  Use when asked to "audit the list", "check the links", "find missing audio", "find artwork", or invokes /audit-list.
allowed-tools: Bash(ruby *), Read, Edit, Grep
user-invocable: true
---

# Audit the list

Two passes over `list.yml`: link liveness across every section, and media for the sections the feed publishes (`FeedBuilder::LABELS`) — finding audio and artwork where they are missing, and re-measuring the audio where it is already recorded.

[`docs/audio-sourcing.md`](../../../docs/audio-sourcing.md) explains the host behaviour behind most of what this reports — why a 401 from YouTube is not a dead video, why a 429 is not a verdict, why an unreachable host is not a missing page.
Append to it when a host does something new.

## 1. Run the audit

```sh
ruby .claude/skills/audit-list/scripts/audit_list.rb --json > /tmp/audit.json
```

Takes several minutes — it resolves audio for every interview with no `audio` block, measures every file the list already names, and looks for the artwork of every entry that has none.
Narrow it with `--links-only` or `--audio-only` when only one pass is wanted; `--audio-only` covers artwork too, since both come out of the same lookups.

The report keys, which name the audio fields flat — `ListWriter::KEYS` maps them to the `audio` block in the file:

- `audio_found` — a new `audio_url`, with its `audio_type` and `audio_length`, the `entry_url` identifying which entry, and `matched_title` when it came from matching an episode in a show's feed.
- `audio_sized` — an entry that had a URL but no size or type.
- `audio_stale` — a recorded length that no longer matches the file by more than 1%. Ad insertion moves it a fraction of a percent; more than that means the recorded number is wrong or the file was replaced.
- `audio_unreadable` — a recorded audio URL that could not be measured. Worth a look: the file may have moved.
- `audio_missing` — no audio anywhere. Usually a video-only appearance. Leave alone.
- `artwork_found` — an `image_url`, with the `scope` it came from: `episode` is the episode's own picture, `show` is the show's, which every episode of that show would carry. `size` is what the file measured.
- `artwork_missing` — no square picture of a usable size anywhere. A show whose entries all come back empty is worth one `image_url` on its `show` anchor by hand, which every entry sharing the anchor then inherits.
- `broken_links` — confirmed dead.
- `unchecked_links` — the checker could not reach the host. Not evidence of anything.

## 2. Record what it found

```sh
ruby .claude/skills/audit-list/scripts/audit_list.rb --report /tmp/audit.json --write
```

`--write` inserts the `audio` block and `image_url` into each entry, keeping them together and adding only keys the entry lacks — a type and a length found for a URL the entry already has go into the block that is there — so applying a report twice is a no-op.
It refuses to write unless the file still parses, the entry count is unchanged, and exactly as many of each key appeared as were applied.
`ListWriter` lives in [`lib/list_writer.rb`](../../../lib/list_writer.rb) and is covered by `rake test`.

The size and type matter as much as the URL: they are what an `<enclosure>` must declare, and recording them is what stops the build probing 34 third-party hosts on every deploy.
It once probed at build time, and Substack blocks GitHub's runners — four episodes disappeared from a deploy that reported success.

Do not hand-edit `list.yml` for this, and never rewrite it through Ruby's YAML dumper: the file uses anchors (`&naval`, `*naval`) and comments, and a round-trip renames every anchor to `&1` and drops every comment.

Read the diff before committing.
When `matched_title` differs noticeably from the entry's own title, flag it — that match was a heuristic, and the diff is the only place a human sees it.
Artwork found `via page` deserves the same look: `og:image` is measured for squareness and size, which catches a banner crop but not a site logo standing in for the episode.

## 3. Verify

```sh
git diff --stat list.yml                                    # additions only, no deletions
diff <(git show HEAD:list.yml | grep -oE ': [&*][a-z_]+' | sort) <(grep -oE ': [&*][a-z_]+' list.yml | sort)
```

Count `&` naively and you will scare yourself: the audio URLs carry `&` in their query strings.

## 4. Report, do not fix

Surface `broken_links` to the user and stop.
Fixing a dead link means finding where the content moved, which is a judgement call, not a substitution.

Mention `unchecked_links` only in passing; a TLS handshake this script cannot complete usually says more about the checker than the link.
