#!/usr/bin/env bash
# subagent-statusline.sh — Claude Code `subagentStatusLine` renderer.
#
# Replaces the default `name · description · token count` row of each subagent
# in the agent panel with the same fields plus the subagent's MODEL (and its
# effort, when one is set):
#
#   code-reviewer · Review the diff · sonnet-5.5 · high · 12.3k
#   Explore · Find the config loader · … · 800
#
# `…` stands in for the model while Claude Code has not resolved it yet (the
# `model` field is omitted until then).
#
# Contract (https://code.claude.com/docs/en/statusline, "Subagent status
# lines"): one JSON object on stdin carrying a `tasks` array; one JSON line per
# row on stdout, `{"id": "<task id>", "content": "<row body>"}`. A task with no
# id is left out of the output, which keeps its default row.
#
# Managed by chezmoi at ~/.claude/subagent-statusline.sh and wired up by
# ~/.claude/settings.json. Like statusline.sh it runs on every refresh tick, so
# it is one `jq` and nothing else: no network, no logging, and no `set -e` — a
# payload it cannot parse degrades to no output (default rows), never a crash.
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

jq -c '
  # Strip C0, DEL and C1 control bytes from anything echoed into a row, so a
  # crafted agent name or description cannot inject escape sequences.
  def s: (. // "") | tostring | explode
         | map(select(. > 31 and . != 127 and (. < 128 or . > 159))) | implode;
  # claude-sonnet-5-5 -> sonnet-5.5, claude-haiku-4-5-20251001 -> haiku-4.5;
  # a trailing [1m] style suffix is kept. Anything else passes through.
  def short:
    s as $m
    | ([$m | capture("^claude-(?<f>opus|sonnet|haiku)-(?<a>[0-9]+)(?:-(?<b>[0-9]{1,2}))?(?:-[0-9]{8})?(?<x>\\[[^\\]]*\\])?$")?][0]) as $c
    | if $c == null then $m
      else $c.f + "-" + $c.a + (if $c.b then "." + $c.b else "" end) + $c.x end;
  def tok:
    if type != "number" then empty
    elif . >= 1000000 then "\((. / 100000 | floor) / 10)M"
    elif . >= 1000 then "\((. / 100 | floor) / 10)k"
    else "\(floor)" end;
  def clip($n): if length > $n then .[0:$n - 1] + "…" else . end;
  ((.columns | if type == "number" and . > 10 then floor else 200 end)) as $cols
  | (.tasks | if type == "array" then . else [] end)[]
  | select(type == "object" and ((.id | type) == "string") and .id != "")
  | { id: .id,
      content: (
        [ ((.name | s) as $n | if $n != "" then $n else (.agentType | s) end),
          ((.label | s) as $l | if $l != "" then $l else (.description | s) end | clip(60)),
          ((.model | short) as $m | if $m != "" then $m else "…" end),
          (.effort | s),
          (.tokenCount | tok)
        ] | map(select(. != "")) | join(" · ") | clip($cols)
      ) }
' 2>/dev/null || true
exit 0
