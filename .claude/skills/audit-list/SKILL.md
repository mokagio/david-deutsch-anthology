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

Two passes over `list.yml`: link liveness, and audio discovery for `podcast_interviews`.

## 1. Run the audit

```sh
ruby .claude/skills/audit-list/scripts/audit_list.rb --json > /tmp/audit.json
```

Takes several minutes — it resolves audio over the network for every interview without an `audio_url`.
Narrow it with `--links-only` or `--audio-only` when only one pass is wanted.

The report has four keys:

- `audio_found` — an audio URL to add, with the `entry_url` identifying which entry, and `matched_title` when it came from matching an episode in a show's feed.
- `audio_missing` — no audio anywhere. Usually a video-only appearance. Leave alone.
- `broken_links` — confirmed dead.
- `unchecked_links` — the checker could not reach the host. Not evidence of anything.

## 2. Add the audio URLs

```sh
ruby .claude/skills/audit-list/scripts/audit_list.rb --report /tmp/audit.json --write
```

`--write` inserts `audio_url` beneath the line that already identifies each entry.
It only ever adds that one key, and refuses to write unless the file still parses, the interview count is unchanged, and exactly as many `audio_url` values appeared as findings were applied.

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
