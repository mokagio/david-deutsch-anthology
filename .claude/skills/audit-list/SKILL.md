---
name: audit-list
description: |
  Check every link in `list.yml` and find audio URLs for podcast interviews that lack one.
  Adds `audio_url` to entries where audio was found; reports dead links without touching them.
  Use when asked to "audit the list", "check the links", "find missing audio", or invokes /audit-list.
allowed-tools: Bash(ruby *), Read, Edit, Grep
user-invocable: true
---

# Audit the list

Two passes over `list.yml`: link liveness across every section, and audio for the sections the feed publishes (`FeedBuilder::LABELS`) — finding it where it is missing, and re-measuring it where it is already recorded.

[`docs/audio-sourcing.md`](../../../docs/audio-sourcing.md) explains the host behaviour behind most of what this reports — why a 401 from YouTube is not a dead video, why a 429 is not a verdict, why an unreachable host is not a missing page.
Append to it when a host does something new.

## 1. Run the audit

```sh
ruby .claude/skills/audit-list/scripts/audit_list.rb --json > /tmp/audit.json
```

Takes several minutes — it resolves audio for every interview without an `audio_url`, and measures every file the list already names but has not sized.
Narrow it with `--links-only` or `--audio-only` when only one pass is wanted.

The report keys:

- `audio_found` — a new `audio_url`, with its `audio_type` and `audio_length`, the `entry_url` identifying which entry, and `matched_title` when it came from matching an episode in a show's feed.
- `audio_sized` — an entry that had a URL but no size or type.
- `audio_stale` — a recorded length that no longer matches the file by more than 1%. Ad insertion moves it a fraction of a percent; more than that means the recorded number is wrong or the file was replaced.
- `audio_unreadable` — a recorded `audio_url` that could not be measured. Worth a look: the file may have moved.
- `audio_missing` — no audio anywhere. Usually a video-only appearance. Leave alone.
- `broken_links` — confirmed dead.
- `unchecked_links` — the checker could not reach the host. Not evidence of anything.

## 2. Record what it found

```sh
ruby .claude/skills/audit-list/scripts/audit_list.rb --report /tmp/audit.json --write
```

`--write` inserts `audio_url`, `audio_type` and `audio_length` into each entry, keeping them together and adding only keys the entry lacks, so applying a report twice is a no-op.
It refuses to write unless the file still parses, the interview count is unchanged, and exactly as many of each key appeared as were applied.

The size and type matter as much as the URL: they are what an `<enclosure>` must declare, and recording them is what stops the build probing 34 third-party hosts on every deploy.
It once probed at build time, and Substack blocks GitHub's runners — four episodes disappeared from a deploy that reported success.

Do not hand-edit `list.yml` for this, and never rewrite it through Ruby's YAML dumper: the file uses anchors (`&naval`, `*naval`) and comments, and a round-trip renames every anchor to `&1` and drops every comment.

Read the diff before committing.
When `matched_title` differs noticeably from the entry's own title, flag it — that match was a heuristic, and the diff is the only place a human sees it.

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
