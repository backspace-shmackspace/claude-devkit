# Code Review: devkit-hygiene-improvements (Round 2)

**Date:** 2026-03-27
**Plan:** `plans/devkit-hygiene-improvements.md`
**Reviewer:** code-reviewer agent v1.0.0
**Round:** 2 (verification pass — M1 fix check + regression verification)

---

## Code Review Summary

M1 from Round 1 is confirmed fixed. All four work groups remain correct. No Critical or Major findings exist across any of the four files. Minor findings from Round 1 are unchanged in status — none have regressed, and no new issues were introduced.

---

## Critical Issues (Must Fix)

None.

---

## Major Findings (Should Fix)

None. M1 is resolved.

### M1 Resolution (Verified Fixed)

**M1 — WG-3: `set -e` active in Test 5 cleanup block of `scripts/test-integration.sh`**

Fixed. Lines 114-116 now read:

```bash
rm -rf "$TEST_DIR" || true
rm -rf "$DEPLOY_DIR/smoke-coord" || true
rm -rf "$DEPLOY_DIR/smoke-pipe" || true
```

The `|| true` guards are present on all three `rm -rf` lines, consistent with the trap handler's own pattern (lines 38-40). A cleanup failure can no longer abort the script before the summary is printed. The fix matches the recommendation exactly.

---

## Minor Findings (Consider)

The following minor findings from Round 1 are unchanged. None have regressed. No new minors introduced.

### m1 — WG-1: Header comment "up to 47 tests" could note the conditional count more precisely

`generators/test_skill_generator.sh` line 9 says "up to 47 tests." This is technically correct (Test 49 is conditional), but "up to 47 tests (46 without contrib skills)" would be clearer. Documentation-only nit; logic is correct.

### m2 — WG-1: Test 50 appears correctly in the inventory comment (no action needed)

Confirmed: Test 50 is listed in the header inventory. No regression.

### m3 — WG-3: `set -e` and `validate-all.sh` interaction (positive confirmation)

`run_test()` correctly uses `set +e`/`set -e` around eval. Test 2's call to `validate-all.sh` is correctly isolated. No issue.

### m4 — WG-3: Test 4 (meta-test) doubles runtime; not noted in header

Test 4 runs the full unit test suite from within the integration test. The script header says "5 tests" but does not warn about runtime cost. Minor documentation gap.

### m5 — WG-1: `DEPLOY_SCRIPT` assigned in Test 31 block, implicitly relied upon by Tests 47-49

`DEPLOY_SCRIPT` is assigned at line 429 inside the Test 31 setup block and persists to Tests 47-49. If Test 31 were ever conditionally skipped or removed, Tests 47-49 would fail with an empty path. Low risk currently (no conditional around Test 31). Moving the assignment to the top-level declarations section alongside `SKILLS_DIR` would make the dependency explicit.

### m6 — WG-4: `ARCHETYPE_GUIDE.md` has no version or "last updated" metadata

The guide contains no date or version header. A metadata comment block would help future editors assess staleness as archetypes evolve. Optional polish.

### m7 — WG-2: `LOCAL_SET=0` with `-eq 0` comparison (positive confirmation)

Correct idiomatic bash. No action needed.

### m8 — WG-3: Test 1 inline cleanup + trap handler double-rm (positive confirmation)

Belt-and-suspenders design is intentional and correct. `rm -rf` on a non-existent path succeeds silently. No issue.

---

## Regression Check

Verified all four files against their Round 1 state:

| File | Status | Notes |
|------|--------|-------|
| `scripts/test-integration.sh` | No regression | M1 fixed (lines 114-116 have `\|\| true`); all other logic unchanged |
| `generators/test_skill_generator.sh` | No regression | Trap handler at line 50-55, Tests 47-49, Test 50 all intact and correct |
| `skills/ship/SKILL.md` | No regression | `LOCAL_SET=0/1` pattern at lines 94-110 is exactly as specified; prose at line 89 correctly documents "even if that value is advisory" edge case |
| `generators/ARCHETYPE_GUIDE.md` | No regression | Decision tree, comparison table, all four archetype sections, and cross-references are present and accurate |

---

## Learnings Check

The five known coder patterns from `.claude/learnings.md` were re-verified. No patterns present in any of the four files.

1. **Stale internal step cross-references** — Not applicable.
2. **Script returns false success when expected inputs are absent** — `validate-all.sh` is a test subject here, not being implemented. Not applicable.
3. **Settings precedence check tests outcome rather than source** — Fixed by WG-2. Pattern not present in the corrected code.
4. **Revision loop prose omits re-running newly added parallel check** — Not applicable.
5. **Conditional branching uses implicit else rather than explicit else guard** — Pattern not present.

---

## What Went Well

- **M1 fix is minimal and precise.** Only the three `rm -rf` lines in Test 5 were changed; no surrounding logic was disturbed.
- **`|| true` style matches the trap handler.** Lines 114-116 are now consistent with lines 38-40 of the same file — same guard pattern, same intent.
- **No scope creep in the fix.** The revision touched exactly what M1 required and nothing else. The file is otherwise identical to Round 1.
- **All four work groups remain structurally sound.** The WG-2 bug fix, WG-1 trap handler, WG-4 decision guide, and the overall test numbering and inventory are all correct.

---

## Recommendations

All Round 1 minor recommendations (m1, m5, m6) remain open as optional improvements for future maintenance. None are blocking.

---

## Verdict

**PASS**

No Critical or Major findings remain. M1 is confirmed fixed. All four files are correct. The implementation is ready to commit.
