---
name: verification-before-completion
description: Use when about to claim work is complete, before committing or creating PRs - requires fresh verification evidence before any completion claim. Triggers on phrases like "done", "finished", "ready to commit", "all tests pass", "looks good", "should work", "I think that's it".
version: 1.0.0
type: reference
attribution: Adapted from superpowers plugin (v4.3.1) by Jesse Vincent, MIT License
---

# Verification Before Completion

## Overview

Every completion claim requires fresh evidence. No exceptions.

## The Iron Law

**NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.**

"I believe it works" is not evidence. "The tests passed at 14:32" is evidence.

If you have not run verification commands in this session and read their output, you have not verified.

## The Gate Function

Before ANY claim that work is complete, execute this sequence:

```
1. IDENTIFY  - What claims am I about to make?
2. RUN       - Execute the verification commands
3. READ      - Read the actual output (not what I expect to see)
4. VERIFY    - Does the output support each claim?
5. CLAIM     - Only now state completion, citing evidence
```

**Every step is mandatory.** Skipping any step means the gate has not been passed.

### Step 1: IDENTIFY

List every claim you are about to make. Be specific:

```
NOT: "It works"
YES: "All 47 tests pass, the build succeeds, and the new endpoint returns 200"
```

Common implicit claims to surface:
- "Tests pass" -- which tests? All of them? Just the new ones?
- "Build succeeds" -- clean build or incremental?
- "Bug is fixed" -- does the specific reproduction case now succeed?
- "No regressions" -- have you run the full test suite, not just new tests?
- "Ready to merge" -- does it pass lint, type checking, and formatting too?

### Step 2: RUN

Execute the actual verification commands. Not from memory. Not from a previous run.

```
REQUIRED: Run the commands NOW, in this session
REQUIRED: Use the Bash tool to execute them
REQUIRED: Run the FULL suite, not a subset (unless the user explicitly scoped it)

FORBIDDEN: Assuming tests still pass from earlier
FORBIDDEN: Referencing results from before your changes
FORBIDDEN: Skipping slow tests without stating you skipped them
```

### Step 3: READ

Read the actual output. All of it.

```
REQUIRED: Read exit codes
REQUIRED: Read failure messages, not just success counts
REQUIRED: Read warnings (they may indicate real problems)

FORBIDDEN: Scanning for "X tests passed" and ignoring everything else
FORBIDDEN: Assuming green because the command "looked like it worked"
```

### Step 4: VERIFY

For each claim from Step 1, check whether the evidence supports it:

```
Claim: "All tests pass"
Evidence: Exit code 0, output shows "47 passed, 0 failed"
Verdict: SUPPORTED

Claim: "No regressions"
Evidence: Only ran new test file, not full suite
Verdict: NOT VERIFIED -- full suite not executed
```

If any claim is NOT VERIFIED, go back to Step 2 and run what's missing.

### Step 5: CLAIM

State completion with evidence citations:

```
"Implementation complete:
- All 47 tests pass (exit code 0)
- Build succeeds (no errors, 2 warnings -- both pre-existing)
- New endpoint returns 200 with correct response body
- Lint and type checking pass"
```

## What Each Claim Requires

| Claim | Required Evidence |
|-------|-------------------|
| "Tests pass" | Test runner output showing pass count, zero failures, exit code 0 |
| "Build succeeds" | Build command output with exit code 0 |
| "Bug is fixed" | Reproduction steps now produce expected behavior |
| "No regressions" | Full test suite passes (not just new tests) |
| "Feature works" | Demonstrated behavior matching acceptance criteria |
| "Ready to commit" | Tests + build + lint + type check all pass |
| "Ready for review" | All of the above + self-review completed |
| "Performance improved" | Before and after measurements with methodology |

## Red Flags -- STOP and Go Back to Step 2

If you notice yourself thinking or about to write any of these, STOP:

- **"Should work"** -- Should is not evidence. Run it.
- **"I think all tests pass"** -- Think is not evidence. Run them.
- **"It looks correct"** -- Looks is not evidence. Verify it.
- **"I'm confident this works"** -- Confidence is not evidence. Prove it.
- **"Tests were passing earlier"** -- Earlier is stale. Run them again.
- **"This is a safe change"** -- Safe changes break things too. Verify.
- **"It's just a typo fix"** -- Typo fixes break builds. Run the build.
- **Expressing satisfaction before running tests** -- Satisfaction is a feeling, not a verification.

## Common Rationalizations

| Rationalization | Why It Fails | What to Do Instead |
|----------------|--------------|---------------------|
| "I just ran the tests a minute ago" | You changed code since then | Run them again |
| "This change is too small to break anything" | Small changes cause big failures | Run the verification |
| "The tests are slow, I'll skip them" | Skipped tests are unverified claims | Run them, or explicitly state "tests not run due to time constraint" |
| "I saw the output scroll by" | Scrolling past is not reading | Read the actual results |
| "The important tests pass" | Partial verification = partial claim | Run all tests or scope your claim |
| "It compiled, so it works" | Compilation proves syntax, not behavior | Run behavioral tests |
| "I'll fix that test later" | A failing test means tests don't pass | Fix it now or state the failure |
| "That failure is flaky / pre-existing" | Prove it -- show it fails on the base branch too | Verify the flake claim |

## Key Patterns

### After Writing Tests (Red-Green Verification)

```
1. Write the test
2. RUN the test -- watch it FAIL (confirms test detects the issue)
3. Write the implementation
4. RUN the test -- watch it PASS (confirms implementation works)
5. RUN the full suite -- confirm no regressions
6. NOW you can claim: "Test passes, no regressions"
```

### After Bug Fixes

```
1. Reproduce the bug (run the failing case, see the failure)
2. Apply the fix
3. RUN the reproduction case -- see it succeed
4. RUN the full test suite -- no regressions
5. NOW you can claim: "Bug fixed, verified with reproduction case, no regressions"
```

### Before Committing

```
1. RUN full test suite
2. RUN build command
3. RUN linter / formatter / type checker (if project uses them)
4. READ all outputs
5. ALL pass with exit code 0?
   YES: Proceed to commit
   NO: Fix first, then start from step 1
```

### When Delegating to Agents

```
After agent completes:
1. READ the agent's claimed results
2. RUN the verification commands YOURSELF
3. Do the results match the claims?
   YES: Proceed
   NO: The agent's claims are wrong. Fix or re-dispatch.

NEVER trust agent completion claims without re-running verification.
```

## When to Apply This Gate

Apply this gate before ANY of these actions:

- Telling the user "it's done" or "it works"
- Creating a git commit
- Creating or updating a pull request
- Claiming a task is complete
- Moving on to the next task
- Reporting success to the user
- Any variation of "finished", "complete", "ready", "all good"

## Relationship to Other Skills

- **After systematic-debugging:** You've found and fixed the root cause. Now verify the fix before claiming it works.
- **After test-driven-development:** You've gone through red-green-refactor. Now run the full suite before claiming done.
- **Before /ship commit gate:** This gate runs before you reach Step 6. Fresh verification at Step 4 (tests) is mandatory.

## The Bottom Line

**Evidence, not confidence.** Run it. Read it. Then claim it.

The cost of running verification is minutes. The cost of a false completion claim is rework, broken builds, and eroded trust.

If you cannot run the verification, say so: "I cannot verify [X] because [reason]. Do you want me to proceed without verification or investigate how to verify?"
