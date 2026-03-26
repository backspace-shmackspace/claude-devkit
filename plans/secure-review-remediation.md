# Plan: Secure Review Remediation (High + Medium Findings)

## Revision Log

| Rev | Date | Summary |
|-----|------|---------|
| 1 | 2026-03-26 | Initial draft. 6 work groups across 3 phases remediating 5 High + 12 Medium findings. |
| 2 | 2026-03-26 | Revised to address red team FAIL verdict (2 Critical, 4 Major), 3 librarian required edits, and 3 feasibility Major recommendations. Changes: **(F-1)** Added `generate_skill.py` `format_map` -> `.replace()` fix to WG-2. **(F-2/F-3)** Consolidated all `generate_senior_architect.py` fixes (format string, `validate_target_dir()`, `atomic_write()`, bare `except:`) into WG-1; file no longer appears in any other WG. **(F-4)** Rewrote WG-6 Step 1 with concrete file-staging pattern using work-group scoped file lists. **(F-5)** Integrated `deploy.sh` steps into WG-2 step list; removed orphaned section. **(F-6)** Added double-brace validation command to WG-1. **(Librarian R-1)** Removed WG-5 Step 3 (`git rm --cached`) since `.claude/settings.local.json` is already untracked. **(Librarian R-2)** Replaced Phase 3 Step 1 with forward reference to WG-2. **(Librarian R-3)** Fixed Assumption 3 wording about settings.local.json tracking status. **(Feasibility M-1/M-2/M-3)** Resolved by WG-1 consolidation. **(F-10)** Corrected acceptance criterion to reflect 4 deferred Medium findings. |

## Context

A full secure-review scan was conducted on 2026-03-26 (archived at `./plans/archive/secure-review/2026-03-26T14-42-21/`). The scan returned a **BLOCKED** verdict (risk score 7/10) with 5 High and 12 Medium findings across three scan dimensions (vulnerability, data flow, auth/authz).

The repository was migrated from internal GitLab to public GitHub on 2026-03-25 (`backspace-shmackspace/claude-devkit`), making PII scrubbing and input validation findings newly urgent.

**This plan remediates all 5 High and 12 Medium findings.** Low-severity findings (12 total) are explicitly out of scope and deferred to a follow-up hardening pass.

## Goals

1. Eliminate all 5 High-severity injection, data leakage, and path traversal findings
2. Remediate all 12 Medium-severity findings are resolved (except 4 deferred with justification -- see Non-Goals)
3. Apply existing correct patterns (`atomic_write()`, `validate_target_dir()`, `.replace()`) consistently across all generators and scripts
4. Reach PASS_WITH_NOTES or better on a re-scan

## Non-Goals

1. Low-severity findings (12 items) -- deferred to a follow-up hardening pass
2. Replacing absolute paths in historical plan artifacts (100+ files) -- this is a bulk refactor best done as a separate one-time script (Dataflow M-1)
3. Refactoring `eval` usage in test scripts (Vuln M-2) -- classified as Medium but is test-only code with hardcoded string literal inputs; no CI/CD pipeline exists to introduce untrusted input. Remediation requires refactoring the entire test runner, which is disproportionate effort for the risk level. Deferred to v1.1.
4. Addressing `/tmp/` in `validate_target_dir()` allowlist (Dataflow M-4) -- this is a design decision for test usability on single-user macOS; risk is low for the target audience. Deferred.
5. Addressing `/etc/passwd` access finding (Dataflow M-3) -- original scan rates it DREAD 1.8 and states "No immediate action required." Deferred.

## Assumptions

1. The repository owner consents to replacing their full name with GitHub handle `@backspace-shmackspace` in maintained-by lines and removing author/decider names from skill templates
2. The internal GitLab hostname (`gitlab.cee.redhat.com`) should be replaced with a generic placeholder
3. The `.claude/settings.local.json` file is machine-specific and is not currently tracked in git; adding it to `.gitignore` prevents accidental future tracking
4. `generate_senior_architect.sh` can be deprecated (replaced by deprecation notice) without breaking any CI/CD or automated workflow -- it is a convenience wrapper superseded by the Python equivalent
5. The `generate_skill.py` implementations of `atomic_write()` and `validate_target_dir()` are the reference patterns to adopt

## Architectural Analysis

### Key Drivers

| Driver | Weight | Rationale |
|--------|--------|-----------|
| Public repo security | Critical | Repository is now on public GitHub; PII and injection vectors are exposed |
| Pattern consistency | High | Good patterns exist in `generate_skill.py` and `undeploy_skill()` but are not applied uniformly |
| Backward compatibility | Medium | Deprecating `.sh` wrapper must not break existing users |
| Minimal blast radius | High | Each work group touches isolated file sets to enable parallel `/ship` execution |

### Design Principles Applied

1. **DRY (Don't Repeat Yourself):** Extract shared validation into a reusable function rather than copy-pasting
2. **Defense in Depth:** Input validation at every entry point, not just some
3. **Fail Secure:** Atomic writes prevent partial file corruption; explicit staging prevents accidental secret commits
4. **Least Privilege:** Narrow tool permissions to specific subcommands

## Proposed Design

### Approach Summary

Six work groups, each targeting a distinct set of files with no overlapping modifications:

| Work Group | Theme | Files Modified |
|------------|-------|----------------|
| WG-1 | Deprecate shell script + harden `generate_senior_architect.py` (all fixes) | 3 generator files, 1 README |
| WG-2 | Apply `atomic_write()`, `validate_target_dir()`, and `.replace()` to remaining generators + deploy.sh path traversal fix | 3 files |
| WG-3 | Fix `/secrets-scan` unredacted write | 1 skill file |
| WG-4 | Scrub PII and employer-specific references from committed files | 6 source files |
| WG-5 | Harden tool permissions + gitignore | 2 config files |
| WG-6 | Harden `/ship` commit pipeline | 1 skill file |

### Interfaces/Schema Changes

None. All changes are internal implementation fixes. No CLI interfaces, frontmatter schemas, or external APIs are modified.

### Data Migration

None required. The `.claude/settings.local.json` is already not tracked by git; adding it to `.gitignore` prevents accidental future tracking.

## Implementation Plan

### Phase 1: Remediate High Findings (WG-1 through WG-4)

These four work groups address all 5 High-severity findings and can execute in parallel.

---

#### Work Group 1: Deprecate shell script + harden `generate_senior_architect.py`

**Findings addressed:** H-1 (CWE-78 sed injection), H-2 (CWE-134 format string in `generate_senior_architect.py`), Vuln L-4 (dual implementation), Vuln M-3 / Authz M-3 (non-atomic writes in `generate_senior_architect.py`), Vuln M-4 (bare `except:` in `generate_senior_architect.py:295`), Vuln M-6 / Authz M-2 (no target dir validation in `generate_senior_architect.py`)

**Files modified:**
- `generators/generate_senior_architect.sh` (deprecation notice + functional disable)
- `generators/generate_senior_architect.py` (format string fix, `validate_target_dir()`, `atomic_write()`, bare `except:` fix)
- `generators/README.md` (update documentation to mark `.sh` as deprecated)

**Steps:**

1. [ ] **Deprecate `generate_senior_architect.sh`**: Replace the script body with a deprecation notice that prints a message and exits, directing users to the Python equivalent. Preserve the file (do not delete) so existing references get a clear error instead of "command not found".

   Replace the functional body (everything after the header/usage comment block) with:
   ```bash
   echo "DEPRECATED: generate_senior_architect.sh is deprecated."
   echo "Use the Python equivalent instead:"
   echo "  python3 generators/generate_senior_architect.py [target-directory] [--project-type TYPE]"
   echo ""
   echo "See: generators/README.md for updated usage."
   exit 1
   ```

2. [ ] **Fix format string injection in `generate_senior_architect.py`**: At line 344, replace `.format()` with chained `.replace()` calls (matching the pattern already used by `generate_agents.py` at lines 328-335):

   Change:
   ```python
   content = AGENT_TEMPLATE.format(
       project_name=project_name,
       project_type=project_type
   )
   ```

   To:
   ```python
   content = AGENT_TEMPLATE.replace('{project_name}', project_name)
   content = content.replace('{project_type}', project_type)
   ```

   Also update the `AGENT_TEMPLATE` constant: change all `{{...}}` double-brace escapes (e.g., `{{feature-name}}`, `{{date}}`, `{{YYYY-MM-DD}}`) to single-brace `{...}` since `.replace()` does not interpret braces. See Step 7 for exhaustive validation of leftover double-braces.

3. [ ] **Add `validate_target_dir()` to `generate_senior_architect.py`**: Port the function from `generate_skill.py` (lines 96-133). Insert it before the `generate_agent()` function. Call it from `main()` after argument parsing.

   Add the following imports at the top (if not already present):
   ```python
   import tempfile
   ```

   Add the function:
   ```python
   def validate_target_dir(path: str) -> tuple:
       """Validate target directory is within allowed boundaries."""
       try:
           resolved = Path(path).resolve()
           if not resolved.is_dir():
               return False, f"Target directory does not exist: {resolved}"
           if not os.access(resolved, os.W_OK):
               return False, f"Target directory is not writable: {resolved}"
           home_workspaces = Path.home() / "workspaces"
           tmp = Path("/tmp").resolve()
           devkit_root = Path(__file__).resolve().parent.parent
           for allowed_parent in [home_workspaces, tmp, devkit_root]:
               try:
                   resolved.relative_to(allowed_parent)
                   return True, ""
               except ValueError:
                   pass
           return False, f"Target directory must be under ~/workspaces/, {devkit_root}, or /tmp/"
       except Exception as e:
           return False, f"Invalid target directory: {e}"
   ```

   Call in `main()` after argument parsing:
   ```python
   valid, error = validate_target_dir(args.target_dir)
   if not valid:
       print(f"Error: {error}", file=sys.stderr)
       return 1
   ```

4. [ ] **Add `atomic_write()` to `generate_senior_architect.py`**: Port the function from `generate_skill.py` (lines 188-222). Replace the direct `open(agent_file, 'w')` write at line 350-351 with `atomic_write()`.

   Add the function:
   ```python
   def atomic_write(target_path: Path, content: str) -> tuple:
       """Write content to file atomically using temp file + rename."""
       try:
           target_path.parent.mkdir(parents=True, exist_ok=True)
       except Exception as e:
           return False, f"Cannot create directory: {target_path.parent}. {e}"
       tmp_path = None
       try:
           fd, tmp_path = tempfile.mkstemp(
               dir=target_path.parent, prefix=".agent-", suffix=".tmp"
           )
           with os.fdopen(fd, 'w') as f:
               f.write(content)
           os.replace(tmp_path, target_path)
           return True, ""
       except Exception as e:
           if tmp_path and os.path.exists(tmp_path):
               try:
                   os.unlink(tmp_path)
               except OSError:
                   pass
           return False, f"Cannot write to {target_path}. {e}"
   ```

   Replace the write block (lines 350-351):
   ```python
   # Old:
   with open(agent_file, 'w') as f:
       f.write(content)

   # New:
   success, error = atomic_write(Path(agent_file), content)
   if not success:
       print(f"Error: {error}", file=sys.stderr)
       return 1
   ```

5. [ ] **Fix bare `except:` in `generate_senior_architect.py`**: At line 295 (`detect_project_type` JSON parsing), replace `except:` with `except (json.JSONDecodeError, KeyError, OSError):`.

   ```python
   # Old:
   except:
       pass
   # New:
   except (json.JSONDecodeError, KeyError, OSError):
       pass
   ```

6. [ ] **Update `generators/README.md`**: Add deprecation notice to the `generate_senior_architect.sh` section. Add note directing users to the Python generator or `generate_agents.py --type senior-architect`.

7. [ ] **Validate no leftover double-brace escapes**: After the `.format()` to `.replace()` conversion, verify no `{{` sequences remain that should have been converted:

   ```bash
   grep -n '{{' generators/generate_senior_architect.py | grep -v '#' && echo "WARN: double-brace sequences may need conversion to single-brace" || echo "PASS: no leftover double-braces"
   ```

**Validation:**
```bash
# Verify .sh script prints deprecation and exits 1
bash generators/generate_senior_architect.sh . 2>&1 | grep -q "DEPRECATED" && echo "PASS" || echo "FAIL"

# Verify .py script still generates correctly (dry-run check)
python3 generators/generate_senior_architect.py /tmp --project-type "Test Project" --force 2>/dev/null
test -f /tmp/.claude/agents/senior-architect.md && echo "PASS" || echo "FAIL"
rm -rf /tmp/.claude/agents/senior-architect.md

# Verify no .format() calls remain on the template
grep -n '\.format(' generators/generate_senior_architect.py | grep -v 'argparse\|formatter_class' && echo "FAIL: .format() still present" || echo "PASS"

# Verify validate_target_dir rejects arbitrary paths
python3 -c "
import sys; sys.path.insert(0, 'generators')
from generate_senior_architect import validate_target_dir
ok, err = validate_target_dir('/etc')
assert not ok, 'Should reject /etc'
print('PASS: /etc rejected')
"

# Verify no bare except: remains
grep -n 'except:' generators/generate_senior_architect.py && echo "FAIL: bare except still present" || echo "PASS"

# Verify no leftover double-brace escapes
grep -n '{{' generators/generate_senior_architect.py | grep -v '#' && echo "WARN: check double-braces" || echo "PASS"
```

---

#### Work Group 2: Apply `atomic_write()`, `validate_target_dir()`, and `.replace()` consistently + deploy.sh fix

**Findings addressed:** Vuln M-3 (CWE-367 non-atomic writes in `generate_agents.py`), Vuln M-6 / Authz M-2 (CWE-22 no target dir validation in `generate_agents.py`), Vuln M-4 (CWE-755 bare except in `generate_skill.py`), H-2 (CWE-134 format string in `generate_skill.py` `format_map`), Vuln M-1 / Authz H-1 (CWE-22 path traversal in `deploy.sh`)

**Files modified:**
- `generators/generate_agents.py` (`validate_target_dir()`, `atomic_write()`)
- `generators/generate_skill.py` (bare `except:` fix at lines 220, 435; `format_map` -> `.replace()` at line 185)
- `scripts/deploy.sh` (path traversal validation)

**Steps:**

1. [ ] **Add `validate_target_dir()` to `generate_agents.py`**: Port the function from `generate_skill.py` (lines 96-133). Insert it before `generate_agents()`. Call it from `main()` after the existing existence/directory checks (around line 488). The function validates that the resolved target path is under `~/workspaces/`, the devkit root, or `/tmp/`.

   Add the following imports at the top (if not already present):
   ```python
   import tempfile
   ```

   Add the function:
   ```python
   def validate_target_dir(path: str) -> tuple:
       """Validate target directory is within allowed boundaries."""
       try:
           resolved = Path(path).resolve()
           if not resolved.is_dir():
               return False, f"Target directory does not exist: {resolved}"
           if not os.access(resolved, os.W_OK):
               return False, f"Target directory is not writable: {resolved}"
           home_workspaces = Path.home() / "workspaces"
           tmp = Path("/tmp").resolve()
           devkit_root = Path(__file__).resolve().parent.parent
           for allowed_parent in [home_workspaces, tmp, devkit_root]:
               try:
                   resolved.relative_to(allowed_parent)
                   return True, ""
               except ValueError:
                   pass
           return False, f"Target directory must be under ~/workspaces/, {devkit_root}, or /tmp/"
       except Exception as e:
           return False, f"Invalid target directory: {e}"
   ```

   Call in `main()`:
   ```python
   valid, error = validate_target_dir(args.target_dir)
   if not valid:
       print(f"Error: {error}", file=sys.stderr)
       return 1
   ```

2. [ ] **Add `atomic_write()` to `generate_agents.py`**: Port the function from `generate_skill.py` (lines 188-222). Replace the direct `open(agent_file, 'w')` write at line 408 with `atomic_write()`.

   Add the function:
   ```python
   def atomic_write(target_path: Path, content: str) -> tuple:
       """Write content to file atomically using temp file + rename."""
       try:
           target_path.parent.mkdir(parents=True, exist_ok=True)
       except Exception as e:
           return False, f"Cannot create directory: {target_path.parent}. {e}"
       tmp_path = None
       try:
           fd, tmp_path = tempfile.mkstemp(
               dir=target_path.parent, prefix=".agent-", suffix=".tmp"
           )
           with os.fdopen(fd, 'w') as f:
               f.write(content)
           os.replace(tmp_path, target_path)
           return True, ""
       except Exception as e:
           if tmp_path and os.path.exists(tmp_path):
               try:
                   os.unlink(tmp_path)
               except OSError:
                   pass
           return False, f"Cannot write to {target_path}. {e}"
   ```

   Replace the write block (lines 407-409):
   ```python
   # Old:
   with open(agent_file, 'w') as f:
       f.write(content)

   # New:
   success, error = atomic_write(agent_file, content)
   if not success:
       print(f"Error: {error}", file=sys.stderr)
       continue
   ```

3. [ ] **Fix bare `except:` in `generate_skill.py`**: At lines 220 and 435, replace `except:` with `except OSError:`. These are both file cleanup contexts where only filesystem errors are expected.

   Line 220 (temp file cleanup):
   ```python
   # Old:
   except:
       pass
   # New:
   except OSError:
       pass
   ```

   Line 435 (generated file removal on validation failure):
   ```python
   # Old:
   except:
   # New:
   except OSError:
   ```

4. [ ] **Replace `format_map` with `.replace()` in `generate_skill.py`**: In the `substitute_placeholders()` function at line 185, replace `format_map(defaults)` with chained `.replace()` calls. The `format_map(defaultdict(str))` pattern is vulnerable to attribute access injection (e.g., `--description "{__class__.__mro__}"` leaks Python class hierarchy).

   Replace the `substitute_placeholders()` function:
   ```python
   # Old:
   def substitute_placeholders(template: str, **kwargs) -> str:
       """Substitute placeholders in template using format_map with defaultdict."""
       defaults = defaultdict(str, kwargs)
       return template.format_map(defaults)

   # New:
   def substitute_placeholders(template: str, **kwargs) -> str:
       """Substitute placeholders in template using safe .replace() calls."""
       result = template
       for key, value in kwargs.items():
           result = result.replace('{' + key + '}', str(value))
       return result
   ```

   **Note:** The `defaultdict(str)` behavior (returning empty string for missing keys) is lost with `.replace()`. Missing placeholders will remain as literal `{placeholder}` in the output, which is the safer behavior -- it preserves intent visibility rather than silently erasing content.

5. [ ] **Add `validate_skill_name()` to `deploy.sh`**: Extract a shared validation function from the existing validation in `undeploy_skill()` (lines 52-56):

   ```bash
   validate_skill_name() {
       local skill="$1"
       if [[ "$skill" == */* ]] || [[ "$skill" == *..* ]] || [[ "$skill" == -* ]]; then
           echo "ERROR: Invalid skill name: '$skill' (must not contain '/', '..', or start with '-')" >&2
           return 1
       fi
       return 0
   }
   ```

   Place this function before `deploy_skill()` (around line 18).

6. [ ] **Call `validate_skill_name()` from `deploy_skill()`**: Add as the first operation:

   ```bash
   deploy_skill() {
       local skill="$1"
       validate_skill_name "$skill" || return 1
       ...
   }
   ```

7. [ ] **Call `validate_skill_name()` from `deploy_contrib_skill()`**: Same pattern.

8. [ ] **Refactor `undeploy_skill()` to use shared function**: Replace the inline validation with:

   ```bash
   undeploy_skill() {
       local skill="$1"
       validate_skill_name "$skill" || return 1
       ...
   }
   ```

**Validation:**
```bash
# Verify validate_target_dir rejects arbitrary paths
python3 -c "
import sys; sys.path.insert(0, 'generators')
from generate_agents import validate_target_dir
ok, err = validate_target_dir('/etc')
assert not ok, 'Should reject /etc'
print('PASS: /etc rejected')
"

# Verify atomic_write creates files
python3 -c "
import sys, tempfile, os; sys.path.insert(0, 'generators')
from generate_agents import atomic_write
from pathlib import Path
d = tempfile.mkdtemp()
p = Path(d) / 'test.md'
ok, err = atomic_write(p, 'test content')
assert ok and p.read_text() == 'test content', f'Failed: {err}'
os.unlink(p); os.rmdir(d)
print('PASS: atomic_write works')
"

# Verify no bare except: remains in generate_skill.py
grep -n 'except:' generators/generate_skill.py && echo "FAIL" || echo "PASS: no bare except"

# Verify format_map is no longer used in generate_skill.py
grep -n 'format_map' generators/generate_skill.py && echo "FAIL: format_map still present" || echo "PASS"

# Verify format injection is blocked
python3 -c "
import sys; sys.path.insert(0, 'generators')
from generate_skill import substitute_placeholders
result = substitute_placeholders('Hello {description}', description='{__class__.__mro__}')
assert '__class__' not in result or '{__class__.__mro__}' in result, 'format injection not blocked'
print('PASS: format injection blocked')
"

# Verify path traversal is rejected in deploy
./scripts/deploy.sh '../../.ssh' 2>&1 | grep -q "Invalid skill name" && echo "PASS" || echo "FAIL"

# Verify normal deployment still works
./scripts/deploy.sh dream 2>&1 | grep -q "Deployed" && echo "PASS" || echo "FAIL"
```

---

#### Work Group 3: Fix `/secrets-scan` unredacted write

**Findings addressed:** Dataflow H-1 (unredacted content in `./plans/`), Dataflow M-6 (predictable temp filenames)

**Files modified:**
- `skills/secrets-scan/SKILL.md`

**Steps:**

1. [ ] **Move scan target file to `/tmp/` with randomized name**: In Step 1 (lines 73-106), change the `SCAN_TARGET_FILE` path from `./plans/secrets-scan-${TIMESTAMP}.scan-target.txt` to a temporary file created with `mktemp`:

   Replace:
   ```bash
   SCAN_TARGET_FILE="./plans/secrets-scan-${TIMESTAMP}.scan-target.txt"
   ```

   With:
   ```bash
   SCAN_TARGET_FILE=$(mktemp /tmp/secrets-scan-XXXXXXXX.tmp)
   ```

2. [ ] **Use `mktemp` for file list temp files**: In Step 1, replace the predictable `/tmp/secrets-scan-filelist.tmp` paths:

   Replace:
   ```bash
   git ls-files 2>/dev/null > /tmp/secrets-scan-filelist.tmp
   git ls-files --others --exclude-standard 2>/dev/null >> /tmp/secrets-scan-filelist.tmp
   ```

   With:
   ```bash
   FILELIST_TMP=$(mktemp /tmp/secrets-scan-filelist-XXXXXXXX.tmp)
   git ls-files 2>/dev/null > "$FILELIST_TMP"
   git ls-files --others --exclude-standard 2>/dev/null >> "$FILELIST_TMP"
   ```

   And update the downstream references (`/tmp/secrets-scan-filelist.tmp` -> `"$FILELIST_TMP"`, `/tmp/secrets-scan-filelist-filtered.tmp` -> a second `mktemp` call).

3. [ ] **Eliminate `SCAN_INPUT` variable or unify with `SCAN_TARGET_FILE`**: In Step 2, `SCAN_INPUT` is set separately to the old `./plans/` path. After the Step 1 changes, set `SCAN_INPUT="$SCAN_TARGET_FILE"` directly, or eliminate `SCAN_INPUT` and use `$SCAN_TARGET_FILE` in all downstream grep commands.

4. [ ] **Add immediate cleanup after Step 2**: After Step 2 (pattern scan) completes, add explicit deletion of the scan target file:

   Add after the Step 2 code block (before Step 3):
   ```bash
   # Delete unredacted scan target immediately after pattern scan
   rm -f "$SCAN_TARGET_FILE"
   ```

5. [ ] **Remove scan target from archive step**: In Step 5 (lines 342-347), remove `./plans/secrets-scan-${TIMESTAMP}.scan-target.txt` from the `mv` command since it no longer exists in `./plans/`. Only archive the raw-findings and filtered-findings files.

   Replace:
   ```bash
   mv ./plans/secrets-scan-${TIMESTAMP}.scan-target.txt \
      ./plans/secrets-scan-${TIMESTAMP}.raw-findings.txt \
      ./plans/secrets-scan-${TIMESTAMP}.filtered-findings.md \
      ./plans/archive/secrets-scan/${TIMESTAMP}/ 2>/dev/null || true
   ```

   With:
   ```bash
   mv ./plans/secrets-scan-${TIMESTAMP}.raw-findings.txt \
      ./plans/secrets-scan-${TIMESTAMP}.filtered-findings.md \
      ./plans/archive/secrets-scan/${TIMESTAMP}/ 2>/dev/null || true
   ```

6. [ ] **Add cleanup for temp files at end of Step 1 code block**: Within the same Bash code block where temp files are created in Step 1, add explicit `rm -f` cleanup calls at the end of the block. A `trap ... EXIT` handler may also be included within the same code block as belt-and-suspenders, but should not be relied upon as the primary cleanup mechanism since each Bash tool invocation runs in a separate shell.

   ```bash
   # Cleanup temp files (within same Bash code block)
   rm -f "$SCAN_TARGET_FILE" "$FILELIST_TMP" "$FILELIST_FILTERED_TMP" 2>/dev/null
   ```

**Validation:**
```bash
# Verify the skill no longer writes scan targets to ./plans/
grep -n 'SCAN_TARGET_FILE=.*\./plans/' skills/secrets-scan/SKILL.md && echo "FAIL" || echo "PASS: no ./plans/ scan targets"

# Verify mktemp is used
grep -n 'mktemp' skills/secrets-scan/SKILL.md | grep -q 'mktemp' && echo "PASS: mktemp used" || echo "FAIL"

# Verify scan target is deleted after Step 2
grep -n 'rm -f.*SCAN_TARGET_FILE' skills/secrets-scan/SKILL.md | grep -q 'rm' && echo "PASS: cleanup present" || echo "FAIL"

# Verify SCAN_INPUT is unified or eliminated
grep -n 'SCAN_INPUT=.*\./plans/' skills/secrets-scan/SKILL.md && echo "FAIL: old SCAN_INPUT path" || echo "PASS"

# Validate skill structure
python3 generators/validate_skill.py skills/secrets-scan/SKILL.md
```

---

#### Work Group 4: Scrub PII and employer-specific references from committed files

**Findings addressed:** Dataflow H-2 (hardcoded identity), Dataflow M-5 (internal GitLab hostname)

**Files modified:**
- `CLAUDE.md` (line 1053)
- `README.md` (line 749)
- `GETTING_STARTED.md` (line 437)
- `contrib/journal/SKILL.md` (lines 299, 405, 463)
- `contrib/journal-review/SKILL.md` (line 349)
- `templates/senior-architect.md.template` (line 55)

**Steps:**

1. [ ] **Replace "Maintained by" lines** in `CLAUDE.md`, `README.md`, and `GETTING_STARTED.md`:

   Replace:
   ```
   **Maintained by:** Ian Murphy
   ```
   With:
   ```
   **Maintained by:** @backspace-shmackspace
   ```

2. [ ] **Replace internal GitLab URL** in `contrib/journal/SKILL.md` line 299:

   Replace:
   ```
   repo: gitlab.cee.redhat.com/imurphy/project-name
   ```
   With:
   ```
   repo: <your-git-host>/username/project-name
   ```

3. [ ] **Replace author/decider names** in `contrib/journal/SKILL.md` (lines 405 and 463) and `contrib/journal-review/SKILL.md` (line 349):

   Replace:
   ```
   **Deciders:** Ian Murphy
   ```
   With:
   ```
   **Deciders:** <your-name>
   ```

   Replace:
   ```
   **Author:** Ian Murphy
   ```
   With:
   ```
   **Author:** <your-name>
   ```

4. [ ] **Replace employer-specific model restriction** in `templates/senior-architect.md.template` line 55:

   Replace:
   ```
   - Restricted: `claude-opus-4-6@20250514` (Red Hat IT env)
   ```
   With:
   ```
   - Restricted: `claude-opus-4-6@20250514` (check org-specific restrictions)
   ```

**Validation:**
```bash
# Verify no "Ian Murphy" remains in source files (excluding plans/ entirely, since
# active plan files contain historical PII references in "before" examples)
grep -r "Ian Murphy" --include="*.md" --include="*.template" . \
  --exclude-dir=plans --exclude-dir=.git && echo "FAIL: PII found" || echo "PASS: PII scrubbed"

# Verify no internal GitLab hostname remains
grep -r "gitlab.cee.redhat.com" --include="*.md" . \
  --exclude-dir=plans --exclude-dir=.git && echo "FAIL: internal hostname found" || echo "PASS: hostname scrubbed"

# Verify no "Red Hat IT env" remains
grep -r "Red Hat IT env" --include="*.template" . && echo "FAIL: employer ref found" || echo "PASS: employer ref scrubbed"
```

---

### Phase 2: Remediate Medium Findings (WG-5 and WG-6)

These two work groups address remaining Medium findings and can execute in parallel with each other (but after Phase 1 if any depend on Phase 1 outputs -- they do not).

---

#### Work Group 5: Harden tool permissions + gitignore

**Findings addressed:** Vuln M-5 / Authz M-1 (overly broad permissions), Dataflow M-2 (settings.local.json should be gitignored)

**Files modified:**
- `.claude/settings.local.json` (narrow permissions)
- `.gitignore` (add `.claude/settings.local.json`)

**Note:** `.claude/settings.local.json` is already NOT tracked by git (`git ls-files .claude/settings.local.json` returns empty). No `git rm --cached` is needed. This work group adds it to `.gitignore` to prevent accidental future tracking.

**Steps:**

1. [ ] **Narrow `.claude/settings.local.json` permissions**: Replace the current broad allowlist with scoped entries. Specifically:

   **Remove** these overly broad entries:
   - `"Bash(git:*)"` -- already covered by specific git subcommand entries
   - `"Bash(python3:*)"` -- too broad; allows arbitrary Python execution
   - `"Bash(ssh:*)"` -- allows SSH to arbitrary hosts
   - `"Bash(ssh-add:*)"` -- pre-authorizes loading SSH keys
   - `"Bash(pip3 install:*)"` -- allows arbitrary package installation
   - `"Bash(brew install:*)"` -- allows arbitrary system package installation
   - `"Bash(op ssh:*)"` -- reveals 1Password usage

   **Remove** ephemeral/one-time entries (worktree-specific paths, one-off commands):
   - `"Bash(mkdir -p /tmp/ship-eA1Bmru0Xd/...)"` and similar
   - `"Read(//private/tmp/ship-eA1Bmru0Xd/skills/**)"` and similar
   - `"Bash(GIT_SEQUENCE_EDITOR=...)"` (one-time rebase command)
   - `"Bash(echo \"SSH_AUTH_SOCK=$SSH_AUTH_SOCK\")"` (debug command)
   - `"Bash(echo '=== Git signing config ===...)"` (debug command)
   - `"Bash(ls ~/.ssh/id_ed25519_*)"` (reveals SSH key paths)
   - `"Bash(/tmp/mailmap.txt:*)"` (one-time command)

   **Keep** these well-scoped entries:
   - `"Bash(git symbolic-ref:*)"` -- read-only git operation
   - `"Bash(git commit:*)"` -- needed for skill commit gates
   - `"Bash(git add:*)"` -- needed for staging
   - `"Bash(bash generators/test_skill_generator.sh)"` -- test runner
   - `"Bash(./scripts/deploy.sh)"` and variants -- deployment
   - `"Bash(gh auth:*)"`, `"Bash(gh repo:*)"`, `"Bash(gh api:*)"` -- GitHub CLI
   - `"Read(//tmp/**)"` -- temp file reads
   - Loop constructs (`for`, `do`, `done`, `echo`)

2. [ ] **Add `.claude/settings.local.json` to `.gitignore`**: Append to `.gitignore`:
   ```
   # Machine-specific Claude Code permissions (not for version control)
   .claude/settings.local.json
   ```

**Validation:**
```bash
# Verify broad patterns are removed
grep -E '"Bash\(git:\*\)"' .claude/settings.local.json && echo "FAIL: git:* still present" || echo "PASS"
grep -E '"Bash\(python3:\*\)"' .claude/settings.local.json && echo "FAIL: python3:* still present" || echo "PASS"
grep -E '"Bash\(ssh:\*\)"' .claude/settings.local.json && echo "FAIL: ssh:* still present" || echo "PASS"

# Verify gitignore entry
grep 'settings.local.json' .gitignore && echo "PASS: in gitignore" || echo "FAIL"

# Verify file is not tracked by git (already the case; confirm no regression)
git ls-files .claude/settings.local.json | grep -q . && echo "FAIL: tracked" || echo "PASS: untracked"
```

---

#### Work Group 6: Harden `/ship` commit pipeline

**Findings addressed:** Authz M-4 (git add -A stages secrets), Authz M-5 (no branch protection before soft reset)

**Files modified:**
- `skills/ship/SKILL.md` (Step 5a and Step 6)

**Steps:**

1. [ ] **Replace `git add -A` with explicit file staging** in Step 5a (lines 532-534):

   Replace:
   ```bash
   git add -A
   git commit -m "WIP: ship v3.3.0 first-pass implementation (pre-revision)"
   ```

   With:
   ```bash
   # Stage only files scoped by the plan's task breakdown.
   # The coordinator MUST construct this list from:
   #   1. Shared dependency files (from Step 2a)
   #   2. Each work group's "Files modified" list from the plan
   # Example: git add src/auth.ts src/auth.test.ts lib/helpers.ts
   # NEVER use git add -A or git add .
   git add $SHARED_DEP_FILES $WG1_FILES $WG2_FILES ...
   git commit -m "WIP: ship v3.4.0 first-pass implementation (pre-revision)"
   ```

   Add an instruction paragraph making it clear the coordinator must enumerate files from the plan:

   "**IMPORTANT:** The coordinator MUST enumerate the specific files from the plan's task breakdown and shared dependencies. Build the file list by concatenating: (1) shared dependency files committed in Step 2a, and (2) each work group's 'Files modified' list from the plan being shipped. Use `git add <file1> <file2> ...` with explicit paths. Never use `git add -A` or `git add .` as this risks staging secrets, `.env` files, or other sensitive content that may have been created during implementation. After staging, run `git status --porcelain` and verify that only expected files are staged."

2. [ ] **Add branch protection check** before `git reset --soft` in Step 6 (around line 583):

   Insert before the `git reset --soft HEAD~N` command:
   ```bash
   # Branch protection check: refuse to rewrite history on main/master
   CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED")
   if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
       echo "ERROR: /ship is running on protected branch '$CURRENT_BRANCH'."
       echo "Refusing to run 'git reset --soft' on a protected branch."
       echo "Create a feature branch first: git checkout -b feature/<name>"
       exit 1
   fi
   ```

   Add a note explaining the rationale:

   "**Branch protection:** The coordinator MUST verify the current branch is not `main` or `master` before executing `git reset --soft`. If running on a protected branch, the workflow stops with an error. This prevents accidental history rewriting on the default branch."

**Validation:**
```bash
# Verify git add -A is no longer in Step 5a
grep -n 'git add -A' skills/ship/SKILL.md && echo "FAIL: git add -A still present" || echo "PASS"

# Verify explicit file staging instruction exists
grep -n 'Files modified.*list\|SHARED_DEP_FILES\|plan.*task breakdown' skills/ship/SKILL.md | grep -q . && echo "PASS: explicit staging present" || echo "FAIL"

# Verify branch protection check exists in Step 6
grep -n 'protected branch\|CURRENT_BRANCH.*main\|CURRENT_BRANCH.*master' skills/ship/SKILL.md | grep -q . && echo "PASS: branch protection present" || echo "FAIL"

# Validate skill structure
python3 generators/validate_skill.py skills/ship/SKILL.md
```

---

### Phase 3: Deploy + validate (post-merge)

**Findings addressed:** N/A -- this phase validates the entire remediation.

**Steps:**

1. [ ] **Note:** The `deploy.sh` path traversal fix is included in Phase 1 WG-2 (Steps 5-8 above). No separate Phase 3 work is needed for `deploy.sh`.

2. [ ] **Deploy all modified skills**:
   ```bash
   ./scripts/deploy.sh secrets-scan
   ./scripts/deploy.sh ship
   ```

3. [ ] **Run the full test suite**:
   ```bash
   bash generators/test_skill_generator.sh
   ```

4. [ ] **Run `/secrets-scan all`** on the repo to verify no PII or secrets remain in source files.

5. [ ] **Run `/secure-review full`** to verify the remediation achieves PASS_WITH_NOTES or better.

---

## Rollout Plan

1. **Phase 1** (WG-1, WG-2, WG-3, WG-4): Execute in parallel via `/ship`. No dependencies between work groups.
2. **Phase 2** (WG-5, WG-6): Execute in parallel via `/ship`. No dependencies on Phase 1 outputs, but should be committed after Phase 1 to maintain clean git history.
3. **Phase 3**: Sequential validation. Run test suite, deploy skills, re-scan.
4. **Commit convention**: One commit per phase. Phase 1: `fix(security): remediate High findings from secure-review scan`. Phase 2: `fix(security): remediate Medium findings from secure-review scan`.

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Deprecating `.sh` script breaks existing users | Low | Low | Script still exists, prints deprecation message with migration path. Python equivalent already documented in README. |
| `validate_target_dir()` rejects legitimate user paths | Medium | Low | The allowlist already covers `~/workspaces/`, devkit root, and `/tmp/`. Any project using `gen-agent` from within a workspace or devkit is covered. Users targeting other paths get a clear error with the allowed paths listed. |
| PII scrubbing misses an instance | Low | Medium | Post-remediation grep validation catches remaining instances. The `/secrets-scan` re-run provides a second layer of verification. |
| `.replace()` breaks template content containing literal `{project_name}` | Low | Medium | The template only uses `{project_name}` and `{project_type}` as intentional placeholders. All `{{}}` escapes in the template must be converted to `{}` since `.replace()` does not interpret braces. Verified by the double-brace validation command (WG-1 Step 7) and generation test. |
| `substitute_placeholders()` change drops `defaultdict` silent-empty behavior | Low | Low | Missing placeholders now remain as literal `{placeholder}` in output instead of being silently erased. This is safer (preserves visibility) and the three archetype templates use explicit kwargs matching all placeholders. |
| Narrowing permissions causes skill execution to prompt excessively | Medium | Low | Only removed clearly overly broad patterns. The global `~/.claude/settings.json` still contains the core skill execution permissions. Local settings add project-specific overrides. Users can re-add permissions as needed. |
| `/ship` branch protection check blocks legitimate on-main workflows | Low | Low | The check only affects `git reset --soft` (history rewriting), not the commit itself. Users who intentionally work on main can still commit; they just cannot squash WIP commits on main, which is the desired safety behavior. |

## Test Plan

### Test Command
```bash
# Full validation suite
bash generators/test_skill_generator.sh
```

### Manual Verification Checklist

1. [ ] `bash generators/generate_senior_architect.sh .` prints deprecation notice and exits 1
2. [ ] `python3 generators/generate_senior_architect.py /tmp --project-type "Test" --force` generates a valid agent file
3. [ ] `python3 generators/generate_agents.py /etc --type coder --force` is rejected by `validate_target_dir()`
4. [ ] `python3 generators/generate_senior_architect.py /etc --force` is rejected by `validate_target_dir()`
5. [ ] `./scripts/deploy.sh '../../.ssh'` is rejected by `validate_skill_name()`
6. [ ] `./scripts/deploy.sh dream` succeeds
7. [ ] `grep -r "Ian Murphy" . --exclude-dir=plans --exclude-dir=.git` returns no matches in source files
8. [ ] `grep -r "gitlab.cee.redhat.com" . --exclude-dir=plans --exclude-dir=.git` returns no matches
9. [ ] `.claude/settings.local.json` is in `.gitignore`
10. [ ] `git ls-files .claude/settings.local.json` returns empty (already untracked; gitignore prevents future tracking)
11. [ ] `grep 'git add -A' skills/ship/SKILL.md` returns no matches
12. [ ] `grep 'CURRENT_BRANCH.*main' skills/ship/SKILL.md` returns a match (branch protection)
13. [ ] `grep 'mktemp' skills/secrets-scan/SKILL.md` returns matches (randomized temp files)
14. [ ] `grep 'SCAN_TARGET_FILE=.*\./plans/' skills/secrets-scan/SKILL.md` returns no matches
15. [ ] `python3 generators/validate_skill.py skills/secrets-scan/SKILL.md` exits 0
16. [ ] `python3 generators/validate_skill.py skills/ship/SKILL.md` exits 0
17. [ ] `grep -n 'format_map' generators/generate_skill.py` returns no matches
18. [ ] `grep -n '{{' generators/generate_senior_architect.py | grep -v '#'` returns no matches (no leftover double-braces)
19. [ ] Format injection test: `python3 -c "import sys; sys.path.insert(0,'generators'); from generate_skill import substitute_placeholders; r=substitute_placeholders('Hi {description}', description='{__class__.__mro__}'); assert '{__class__.__mro__}' in r; print('PASS')"` passes
20. [ ] `grep -n 'except:' generators/generate_senior_architect.py` returns no matches

## Acceptance Criteria

1. All 5 High-severity findings are resolved: sed injection eliminated (deprecation), format string eliminated (`.replace()` in both `generate_senior_architect.py` and `generate_skill.py`), secrets-scan uses temp files, PII scrubbed, path traversal validated
2. All 12 Medium-severity findings are resolved except 4 deferred with justification: Vuln M-2 (eval in tests), Dataflow M-1 (absolute paths in 100+ plan artifacts), Dataflow M-3 (`/etc/passwd` access, DREAD 1.8), Dataflow M-4 (`/tmp/` allowlist design decision)
3. `bash generators/test_skill_generator.sh` passes all 26 tests
4. No `grep -r "Ian Murphy"` matches in source files (excluding `plans/`)
5. No `grep -r "gitlab.cee.redhat.com"` matches in source files (excluding `plans/`)
6. `.claude/settings.local.json` is in `.gitignore` (file was already untracked; gitignore prevents accidental future tracking)
7. `generate_senior_architect.sh` prints deprecation notice and exits 1
8. `validate_target_dir()` is applied in both `generate_agents.py` and `generate_senior_architect.py`
9. `atomic_write()` is applied in both `generate_agents.py` and `generate_senior_architect.py`
10. No bare `except:` clauses remain in `generate_skill.py` or `generate_senior_architect.py`
11. `format_map` is no longer used in `generate_skill.py`; replaced with `.replace()` calls
12. `deploy.sh` validates skill names in all three entry-point functions
13. `/ship` Step 5a does not use `git add -A`; uses explicit file staging from plan scope
14. `/ship` Step 6 includes branch protection check before `git reset --soft`
15. `/secrets-scan` writes scan targets to `/tmp/` with randomized names and deletes immediately after scanning
16. A re-run of `/secure-review full` achieves PASS_WITH_NOTES or better (risk score <= 6/10)

## Task Breakdown Summary

| Work Group | Files Created | Files Modified | Parallel Safe |
|------------|--------------|----------------|---------------|
| WG-1 | 0 | `generators/generate_senior_architect.sh`, `generators/generate_senior_architect.py`, `generators/README.md` | Yes |
| WG-2 | 0 | `generators/generate_agents.py`, `generators/generate_skill.py`, `scripts/deploy.sh` | Yes |
| WG-3 | 0 | `skills/secrets-scan/SKILL.md` | Yes |
| WG-4 | 0 | `CLAUDE.md`, `README.md`, `GETTING_STARTED.md`, `contrib/journal/SKILL.md`, `contrib/journal-review/SKILL.md`, `templates/senior-architect.md.template` | Yes |
| WG-5 | 0 | `.claude/settings.local.json`, `.gitignore` | Yes |
| WG-6 | 0 | `skills/ship/SKILL.md` | Yes |

**File boundary verification:** No file appears in more than one work group. All `generate_senior_architect.py` changes are consolidated in WG-1 (format string fix, `validate_target_dir()`, `atomic_write()`, bare `except:` fix). All work groups can execute in parallel.

## Context Alignment

### CLAUDE.md Patterns Followed
- **Edit source, not deployment:** All skill modifications target `skills/*/SKILL.md`, not `~/.claude/skills/`
- **Validate before committing:** Plan includes `validate_skill.py` runs for modified skills
- **Follow v2.0.0 patterns:** Modified skills retain all 10 architectural patterns
- **Conventional commits:** `fix(security):` prefix for security remediation
- **Generators must use atomic writes:** Enforced by porting `atomic_write()` to remaining generators
- **Three-tier architecture:** Changes respect tier boundaries (skills, generators, templates modified independently)

### Prior Plans Referenced
- **`plans/agentic-sdlc-security-skills.md`** (APPROVED, Phase A complete in bcdce1f): Created the `/secrets-scan` and `/secure-review` skills that surfaced the findings being remediated here. The unredacted-write issue in `/secrets-scan` was a design oversight in that plan's Phase A implementation.
- **`plans/embedding-security-in-agentic-sdlc.md`**: Earlier iteration that established the security-first approach; this remediation plan is a direct continuation.
- **`plans/deep-code-security.md`**: Deep code security analysis that informed the security skills design.

### Deviations from Established Patterns
1. **WG-5 adds `.claude/settings.local.json` to `.gitignore`**: The file is already untracked; this prevents accidental future tracking. The file contains machine-specific permissions and SSH infrastructure details that should not be in a public repository.
2. **WG-1 deprecates rather than deletes `generate_senior_architect.sh`**: This deviates from the typical "remove unused code" pattern. Justified because existing documentation and muscle memory may reference the script; a deprecation notice provides a clear migration path.
3. **M-2 (eval in test scripts) is deferred** despite being Medium severity: This is a test-only finding requiring a test runner refactor. The risk is low (hardcoded string literal inputs, no CI/CD pipeline) and the effort is disproportionate. This deviation is documented in Non-Goals.

## Next Steps

1. **Execute Phase 1**: `/ship` this plan targeting WG-1 through WG-4 (parallel work groups)
2. **Execute Phase 2**: `/ship` targeting WG-5 and WG-6
3. **Execute Phase 3**: Run validation suite and re-scan
4. **Follow-up plan**: Create a separate plan for Low-severity hardening (12 findings deferred)
5. **Follow-up plan**: Create a one-time script to replace `/Users/imurphy/` absolute paths in historical plan artifacts (Dataflow M-1)

---

<!-- Context Metadata
discovered_at: 2026-03-26T14:42:00Z
revised_at: 2026-03-26
claude_md_exists: true
recent_plans_consulted: agentic-sdlc-security-skills.md, embedding-security-in-agentic-sdlc.md, deep-code-security.md
archived_plans_consulted: secure-review-2026-03-26T14-42-21 (summary, vulnerability, dataflow, authz)
review_files_addressed: secure-review-remediation.redteam.md (FAIL -> resolved), secure-review-remediation.review.md (PASS with edits -> applied), secure-review-remediation.feasibility.md (PASS with recommendations -> applied)
-->

## Status: APPROVED
