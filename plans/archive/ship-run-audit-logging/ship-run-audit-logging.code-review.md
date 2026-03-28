# Code Review: ship-run-audit-logging (Revision Round 2)

**Plan:** `plans/ship-run-audit-logging.md`
**Reviewer:** code-reviewer agent (standalone)
**Date:** 2026-03-28
**Round:** 2 of 2 (revision verification)

---

## Verdict: PASS

All four Major findings from Round 1 have been fixed. One new Minor finding was introduced by the Step 6 restructuring (see m1 below). No Critical or Major findings remain.

---

## Previous Findings Status

| Finding | Status | Notes |
|---------|--------|-------|
| **M1** — Step 6 missing audit log finalization | **FIXED** | Full verification block, `run_end`, `git add --force`, L3 key staging, and state file cleanup are all present (lines 1053–1114 of `skills/ship/SKILL.md`) |
| **M2** — Step 3f missing `step_start`/`step_end` events | **FIXED** | `step_start` at line 730, `step_end` at line 768 — both present and matching the pattern of all other substeps |
| **M3** — Tests B and C missing from test suite | **FIXED** | Test 55 (architect, line 543) and Test 56 (audit, line 548) added to `generators/test_skill_generator.sh`; header comment updated to "up to 56 tests" |
| **M4** — HMAC key injection risk in `read_state_field` | **FIXED** | `read_state_field` now uses `python3 - "$STATE_FILE" "$field" <<'PYEOF'` heredoc pattern, passing both state file path and field name as `sys.argv` — eliminates the string interpolation injection surface entirely |

---

## Critical Findings

None.

---

## Major Findings

None.

---

## Minor Findings

### m1 — `step_end` for Step 6 fires after the state file has been deleted

In `skills/ship/SKILL.md`, the audit log finalization block (lines 1053–1114) deletes the state file as its last action:

```bash
# Cleanup state file (not needed after run)
rm -f ".ship-audit-state-${RUN_ID}.json"
```

The `step_end` event for Step 6 is then emitted in a later, separate `Bash` block (lines 1185–1188):

```bash
bash scripts/emit-audit-event.sh ".ship-audit-state-${RUN_ID}.json" \
  '{"event_type":"step_end","step":"step_6_commit_gate",...}'
```

Because `emit-audit-event.sh` checks for the state file existence and exits 0 silently when it is missing, this call will always drop the `step_end` event — the state file was already deleted in the prior block. The result is that every audit log will be missing the `step_end` for Step 6, regardless of maturity level.

A secondary consequence: the `step_end` block is positioned after `**If FAIL:**` prose in the markdown, so the FAIL branch also never receives a `step_end` (it stops the workflow before reaching that block). This means no execution path for Step 6 produces a `step_end` event.

**Suggested fix:** Move the `step_end` emission to just before the `rm -f` cleanup line within the finalization block — or emit it earlier, immediately before the `run_end` event. The `step_start` for Step 6 is at the very top of the step; the matching `step_end` should be the last event before state file deletion, not after it.

**Impact:** Query utility `timeline <run_id>` will not be able to compute duration for Step 6 (missing `step_end` timestamp pair). This is low-severity because Step 6 is the final step and the `run_end` event provides an approximate close time.

---

### m2 — Round 1 m2 (`file_modification` event as comment-only) is partially addressed

The previous review flagged that the `file_modification` bash block was commented-out. In the current code (lines 712–720), the emit call is now executable but retains a comment saying "Example (replace WG_NUM, WG_NAME, and FILES_JSON with actual values)". The call itself is live (not commented out), so the LLM executing `/ship` will see it and run it. This is a material improvement over the previous round.

The residual concern is that `FILES_JSON` is not constructed in the bash block — it is described in prose but not scaffolded as code. This means the LLM must infer how to build the JSON array at runtime. In practice, a well-prompted LLM will handle this, but it is less reliable than a code scaffold (e.g., `FILES_JSON=$(printf '%s\n' $scoped_files | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().split()))")`). This is a minor nit, not a blocking issue, and is noted for a follow-up if `file_modification` events prove unreliable in practice.

---

### m3 — Test ordering in `test_skill_generator.sh` has a gap in numeric sequence (cosmetic)

Tests 55 and 56 are inserted between Test 52 and the end section, but they are numerically out of order relative to their position in the file (55, 56 appear before 52, 53, 54 in the file). The test runner does not depend on numeric ordering and all tests run, so this is purely cosmetic. The header comment correctly lists the range "51–56."

---

## Positives

**All four Major findings are cleanly resolved with no overcorrection.** M4's fix (passing `STATE_FILE` and `field` as `sys.argv` via heredoc) is the correct pattern for eliminating shell injection in inline Python — it's more idiomatic and more complete than the original string interpolation. The implementation is textbook.

**`set -euo pipefail` is now consistent.** Round 1's m1 finding (the dropped `-e` flag) is fixed. The existing `|| echo ""` / `2>/dev/null || true` guards on failure-tolerant code paths remain correct and make the intent explicit.

**Tests 55 and 56 correctly reference `SKILLS_DIR/skills/architect/SKILL.md` and `SKILLS_DIR/skills/audit/SKILL.md`.** The variable reference matches the `SKILLS_DIR` alias used throughout the file. These tests will run correctly.

**`file_modification` event is now an executable call** rather than a commented-out example, resolving the prior m2 concern at the actionable level.

**Step 3f instrumentation is complete and correctly placed.** The `step_start` before the cleanup loop and `step_end` at the end of Step 3f follow the exact pattern used in all other substeps (3a–3e), including consistent use of `agent_type: coordinator`.

**WIP commit message version string is correct.** The Step 5a WIP commit now reads `WIP: ship v3.6.0 first-pass implementation (pre-revision)`, matching the bumped skill version.

**Learnings-check: known patterns verified.**

Checked against `.claude/learnings.md` `## Coder Patterns > ### Missed by coders, caught by reviewers`:
- **Stale cross-references:** m5 from Round 1 (WIP commit message) is fixed. No new stale references found.
- **Script returns false success on empty input:** Not present.
- **Settings precedence uses value, not source:** Not applicable.
- **Revision loop prose omits new parallel check:** Not applicable.
- **Conditional branching uses implicit else:** Not present in new code.
- **`rm -rf` in cleanup without `|| true` under `set -e`:** `rm -f` (not `rm -rf`) is used in the state file cleanup. `emit-audit-event.sh` now has `set -euo pipefail`, but the `rm -f` on the state file in the SKILL.md bash block is not under `-e` (each Bash tool call is a separate shell). Not a defect.

---

## Summary

The implementation has converged. All blocking issues from Round 1 are resolved. The one new minor finding (m1: `step_end` for Step 6 is always dropped because the state file is deleted before the emit call runs) is low-severity and does not affect the correctness of the audit trail or the maturity-aware retention model — it affects only the `timeline` query for Step 6 duration. The fix is a one-line reorder within the finalization block. It can be addressed in a follow-up change or as a quick patch before deployment.

No Critical or Major findings remain. **PASS.**
