# Test Cases — Backlog Items 2, 1, 3

These test cases define expected behaviour for upcoming implementations.
Run each after the corresponding item is complete.

---

## Item 2: User Restore Improvements

### Context
- Source instance has 4 users: agent1, full-admin, manage1, supervisor1
- Target instance has 1 user: localadmin
- Cross-account: source 111111111111, target 222222222222
- Users cannot be created cross-account (password/DirectoryUserId unavailable)
- Restore should UPDATE users that already exist on target, SKIP those that don't

### Test 2.1: Preflight username check

**Setup:** Target has only `localadmin`. Source backup has 4 users.

**Run:**
```bash
connect_restore --dry-run helper
# (or preflight section specifically)
```

**Expected output:**
```
⚠ 4 of 4 source users missing on target instance
  Missing: agent1, full-admin, manage1, supervisor1
  → Pre-create via Identity Center or Connect console before restore
```

**Pass criteria:**
- Warns but does NOT abort the restore
- Lists each missing username
- Restore continues with other sections

### Test 2.2: User update for pre-existing user

**Setup:** Create `agent1` on target manually. Source backup has agent1 with:
- RoutingProfile: "Basic Routing Profile"
- SecurityProfiles: ["Agent"]
- HierarchyGroup: (none)

**Run:**
```bash
connect_restore helper
```

**Expected output:**
```
  ✓ Updated agent1 routing profile → Basic Routing Profile
  ✓ Updated agent1 security profiles → Agent
```

**Pass criteria:**
- `update-user-routing-profile` called with correct target routing profile ID
  (resolved via name, not source ID)
- `update-user-security-profiles` called with correct target security profile IDs
- No error on users that don't exist on target (skip gracefully)

### Test 2.3: User update skips missing users

**Setup:** Source has 4 users. Target has only `agent1`.

**Run:**
```bash
connect_restore helper
```

**Expected output:**
```
  ✓ Updated agent1 routing profile → Basic Routing Profile
  ✓ Updated agent1 security profiles → Agent
  - Skipped full-admin (not found on target)
  - Skipped manage1 (not found on target)
  - Skipped supervisor1 (not found on target)
```

**Pass criteria:**
- No API errors for missing users
- Each missing user logged as skip, not failure
- Restore exit code 0 (skipped users are not errors)

### Test 2.4: Dry run shows what would change

**Run:**
```bash
connect_restore --dry-run helper
```

**Expected output:**
```
  [dry] Would update agent1 routing profile → Basic Routing Profile
  [dry] Would update agent1 security profiles → Agent
  [skip] full-admin not found on target
  ...
```

**Pass criteria:**
- No actual API calls made
- Clearly indicates what would happen

### Test 2.5: Validate Layer 7 after successful user update

**Run:**
```bash
connect_validate -m full --target <target-instance-id> qs-builder-in-sydney
```

**Expected (after agent1 created and updated):**
```
  [7.1] ✗ Users → 3 of 4 missing
  [7.2] ✓ User routing profiles (1/1 matched)
  [7.3] ✓ User security profiles (1/1 matched)
```

**Pass criteria:**
- 7.1 reflects actual missing count (3 not 4)
- 7.2 and 7.3 only check users that exist on target
- No false failures for users that were successfully updated

---

## Item 1: connect_plan Modularisation

### Context
- `connect_plan` is ~900 lines, single file
- Logical sections: prompts, flows, modules, queues, routing profiles, quick connects,
  lambda prefix mapping, lex bot prefix mapping
- Must produce byte-identical output before/after refactor
- Should gain `--only`/`--skip` flags matching backup/restore pattern

### Test 1.1: Byte-identical output (regression)

**Setup:** Existing backup dirs for source and target.

**Run BEFORE refactor:**
```bash
connect_plan qs-builder-in-sydney dr-solution-target helper-before
```

**Run AFTER refactor:**
```bash
connect_plan qs-builder-in-sydney dr-solution-target helper-after
```

**Pass criteria:**
```bash
diff -r helper-before helper-after
# Must produce NO output (byte-identical)
```

### Test 1.2: --only flag

**Run:**
```bash
connect_plan --only flows qs-builder-in-sydney dr-solution-target helper-only
```

**Pass criteria:**
- Helper dir contains only flow-related files (flow_*.json entries in helper file)
- No prompt, queue, routing, or quick connect entries present
- Exit code 0

### Test 1.3: --skip flag

**Run:**
```bash
connect_plan --skip prompts,routing qs-builder-in-sydney dr-solution-target helper-skip
```

**Pass criteria:**
- Helper dir contains everything EXCEPT prompt and routing entries
- Flow, queue, quick connect entries still present
- Exit code 0

### Test 1.4: Section naming matches run_section pattern

**Pass criteria:**
- `bin/lib/plan/` directory exists
- Files follow naming convention: `prompts.sh`, `flows.sh`, `modules.sh`,
  `queues.sh`, `routing.sh`, `quick_connects.sh`, `lambdas.sh`, `lex_bots.sh`
- Each file is independently syntax-valid: `bash -n bin/lib/plan/*.sh`
- Main `connect_plan` is < 100 lines (thin orchestrator)

### Test 1.5: common.sh sourced (not duplicated)

**Pass criteria:**
- `grep -c "hex_code\|path_encode\|dos2unix" bin/lib/plan/*.sh` returns 0
  (no re-definitions — all inherited from common.sh via parent)
- `grep "section_header" bin/lib/plan/*.sh` shows each module using the shared function

### Test 1.6: bash -n all files

```bash
bash -n bin/connect_plan && bash -n bin/lib/plan/*.sh
# Exit code 0
```

---

## Item 3: Flow Content Normalized Diff (Layers 9.3 / 10.4)

### Context
- After confirming flows EXIST (10.1), verify their CONTENT matches
- Must normalize IDs/ARNs before comparing (source and target have different IDs)
- Maps already available: queue name→ID, flow name→ID, lambda name→ARN, etc.
- "Original Sample inbound flow" has 7 dead refs — good edge case

### Test 3.1: Identical flow content passes

**Setup:** Flow restored successfully, no manual edits on target.

**Run:**
```bash
connect_validate -m full --only 10 --target <id> qs-builder-in-sydney
```

**Expected:**
```
  [10.1] ✓ All flows exist (10/10)
  [10.2] ✓ All flows ACTIVE (10/10)
  [10.3] ✓ Flow types correct (10)
  [10.4] ✓ Flow content matches (10/10)
```

**Pass criteria:**
- 10.4 compares normalized content (IDs replaced with names)
- All 10 flows pass content check

### Test 3.2: Modified flow content detected

**Setup:** Manually edit one flow on target (add a Play prompt block).

**Run:**
```bash
connect_validate -m full --only 10 --target <id> qs-builder-in-sydney
```

**Expected:**
```
  [10.4] ✗ Flow content matches
         → 1 flow(s) differ: DR-test-flow-with-lambda
```

**Pass criteria:**
- Correctly identifies which flow differs
- Does NOT false-positive on ID differences (those are expected cross-account)

### Test 3.3: Dead flow refs don't cause false failures

**Setup:** "Original Sample inbound flow" has 7 dead flow refs (UUIDs that don't
exist on either instance).

**Run:**
```bash
connect_validate -m full --only 10 --target <id> qs-builder-in-sydney
```

**Pass criteria:**
- Dead refs appear identically in source backup and target live content
- Normalization treats them as opaque UUIDs (unchanged on both sides)
- Flow passes content check (dead refs are symmetric — same on source and target)

### Test 3.4: Lambda ARN normalization

**Setup:** Source Lambda ARN: `arn:aws:lambda:ap-southeast-2:111111111111:function:my-func`
Target Lambda ARN: `arn:aws:lambda:ap-southeast-2:222222222222:function:my-func`

**Pass criteria:**
- Normalization replaces both with canonical form (e.g., `lambda:my-func`)
- Content comparison treats them as equivalent
- No false FAIL due to account ID difference in ARN

### Test 3.5: Queue ID normalization

**Setup:** Flow references source queue ID `abc-123`. Target queue with same name
has ID `def-456`.

**Pass criteria:**
- Normalization replaces queue IDs with queue names
- Content comparison treats them as equivalent

### Test 3.6: Prompt ID normalization

**Setup:** Flow references source prompt ID. Target prompt with same name has
different ID.

**Pass criteria:**
- Prompt IDs normalized to prompt names
- No false FAIL

### Test 3.7: Module content check (Layer 9.3)

**Run:**
```bash
connect_validate -m full --only 9 --target <id> qs-builder-in-sydney
```

**Expected (when modules exist and match):**
```
  [9.1] ✓ All modules exist
  [9.2] ✓ All modules published
  [9.3] ✓ Module content matches (0/0)
```

**Pass criteria:**
- Same normalization logic applies to modules
- Gracefully handles 0 modules (skip, don't fail)

### Test 3.8: JSON output includes content diff

**Run:**
```bash
connect_validate -m full -j --only 10 --target <id> qs-builder-in-sydney
```

**Pass criteria:**
- JSON output includes test ID `10.4` with result and detail
- If FAIL, detail indicates which flow(s) differ

---

## Running All Tests

After each item is implemented:

```bash
# Syntax check (always)
bash -n bin/connect_backup && bash -n bin/connect_restore && \
bash -n bin/connect_plan && bash -n bin/connect_validate && \
bash -n bin/connect_deps_backup && bash -n bin/connect_deps_restore && \
echo "ALL SYNTAX OK"

# Local validation (no creds)
cd bin && ./connect_validate -m local qs-builder-in-sydney

# Cross-account validation (needs target creds)
./connect_validate -m full \
  --target <target-instance-id> \
  --target-profile <target-profile> \
  qs-builder-in-sydney
```
