# Git and GitHub

Two tasks: the difference between `git commit -m` and `git commit -a -m`, and using `git cherry-pick`
to move a single commit between branches.

Every command below was actually executed in a throwaway repository; the output is pasted verbatim.

---

## Task 1 — `git commit -a -m` vs `git commit -m`

**What this does:** modifies a tracked file and creates a new untracked one, then tries to commit both ways to show exactly what each form picks up.

```bash
echo "line 2 - modified" >> tracked.txt     # modify a TRACKED file
echo "brand new file"    > untracked.txt    # create a NEW file
git status --short
git commit -m "..."                          # nothing staged
git commit -a -m "..."                       # auto-stage tracked changes
```

**Output**

```
$ git init -b main && git add tracked.txt && git commit -m "Initial commit with tracked.txt"

# Now modify the TRACKED file and create a NEW untracked file
$ echo "line 2 - modified" >> tracked.txt
$ echo "brand new file" > untracked.txt

$ git status --short
 M tracked.txt
?? untracked.txt

########## Attempt 1: git commit -m  (nothing staged) ##########
$ git commit -m "try to commit without staging"
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   tracked.txt

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	untracked.txt

no changes added to commit (use "git add" and/or "git commit -a")

########## Attempt 2: git commit -a -m ##########
$ git commit -a -m "Commit with -a: picks up modified tracked files"
[main 09ab78a] Commit with -a: picks up modified tracked files
 1 file changed, 1 insertion(+)

$ git status --short      # untracked.txt was NOT committed
?? untracked.txt

$ git show --stat --oneline HEAD | head -5
09ab78a Commit with -a: picks up modified tracked files
 tracked.txt | 1 +
 1 file changed, 1 insertion(+)

########## To commit the new file, it must be staged explicitly ##########
$ git add untracked.txt && git commit -m "Add untracked.txt explicitly"
committed
$ git status --short
(clean)

$ git log --oneline
e0789c8 Add untracked.txt explicitly
09ab78a Commit with -a: picks up modified tracked files
a7b3f68 Initial commit with tracked.txt
```

### Reading `git status --short`

```
 M tracked.txt      <- Modified, tracked, NOT staged (the space is column 1 = staging area)
?? untracked.txt    <- git has never seen this file
```

The two-character code is `[staged][unstaged]`. A space in the first column means nothing is staged.

### What happened

**`git commit -m` refused outright:** `no changes added to commit`. Git separates the *working
directory* from the *staging area* (index), and `commit` only ever packages what is **staged**.
Editing a file does not stage it.

**`git commit -a -m` committed `tracked.txt` but not `untracked.txt`.** That is the entire subtlety:

> `-a` means "stage all files git is **already tracking**", not "stage everything".

`git status` after the `-a` commit still showed `?? untracked.txt`. Git will not add a file to the
repository without being asked — which is why `-a` cannot accidentally commit your `.env`, your
`node_modules` or a 2 GB log file.

To include a new file it must be staged explicitly with `git add`.

### The three states

```
  working directory  ──git add──►  staging area (index)  ──git commit──►  repository
     (you edit)                       (you choose)                        (permanent)
                └──────────── git commit -a ────────────┘
                              (tracked files only)
```

| Command | Modified tracked files | New untracked files |
| --- | --- | --- |
| `git commit -m "msg"` | ❌ only if already `git add`-ed | ❌ |
| `git commit -a -m "msg"` | ✅ automatically | ❌ |
| `git add . && git commit -m "msg"` | ✅ | ✅ |
| `git add -p` | ✅ chosen hunks only | ❌ |

### When to use which

`-a` is a convenience for the common case: you edited three files you already track and want them all
in one commit. It is not a shortcut for `git add .`.

The habit worth keeping is `git status` before every commit, and `git add -p` when a change should be
split — it walks you through hunk by hunk, which produces commits that are actually reviewable. `-a`
sweeps everything tracked into one commit, and that is how unrelated changes end up sharing a message.

Also worth knowing: `git commit -a` does **not** run `.gitignore` logic differently — ignored files
stay ignored either way. And `git add .` respects `.gitignore` too, which is why the `.gitignore` in
this repository keeps `tls.key` out.

---

## Task 2 — `git cherry-pick`

**What this does:** builds a feature branch containing three commits, one of which is an urgent bugfix, then moves only that one commit onto `main`.

### The setup and the problem

**Output**

```
########## Set up: main plus a feature branch with 3 commits ##########
$ git checkout -b feature
Switched to a new branch 'feature'
$ ... three commits on feature ...

$ git log --oneline --graph --all
* 57f0e7c Add feature B
* ce67dde Fix critical auth bug
* e70ed96 Add feature A
* 9299104 Initial release

$ git checkout main
Switched to branch 'main'
$ ls    # main does not have any of the feature work
app.txt

########## The problem ##########
# Only the auth bugfix is needed on main right now.
# Merging 'feature' would drag feature A and B along with it.

$ git log feature --oneline | cat
57f0e7c Add feature B
ce67dde Fix critical auth bug
e70ed96 Add feature A
9299104 Initial release
```

This is the situation cherry-pick exists for. The auth fix needs to ship **now**, but it sits in the
middle of a feature branch. `git merge feature` would bring feature A and feature B with it — both
unfinished, neither tested.

### Cherry-picking the single commit

```bash
git cherry-pick ce67dde
```

**Output**

```
########## Cherry-pick just that one commit ##########
$ HOTFIX=$(git log feature --format='%h' --grep='auth bug')
$ echo $HOTFIX
ce67dde

$ git cherry-pick $HOTFIX
[main da9953d] Fix critical auth bug
 Date: Thu Sep 17 21:46:27 2026 +0000
 1 file changed, 1 insertion(+)
 create mode 100644 hotfix.txt

$ ls    # only the hotfix arrived, not featureA/featureB
app.txt
hotfix.txt

$ git log --oneline --graph --all
* 57f0e7c Add feature B
* ce67dde Fix critical auth bug
* e70ed96 Add feature A
| * da9953d Fix critical auth bug
|/  
* 9299104 Initial release

$ git show --stat --oneline HEAD | head -4
da9953d Fix critical auth bug
 hotfix.txt | 1 +
 1 file changed, 1 insertion(+)
```

`ls` confirms it: `main` now has `app.txt` and `hotfix.txt` — and **not** `featureA.txt` or
`featureB.txt`. Exactly one commit's worth of change moved.

The graph is the part worth studying:

```
* 57f0e7c Add feature B
* ce67dde Fix critical auth bug        <- the original, on feature
* e70ed96 Add feature A
| * da9953d Fix critical auth bug      <- the copy, on main
|/
* 9299104 Initial release
```

**Same message, same diff, different SHA** — `ce67dde` versus `da9953d`. Cherry-pick does not move a
commit; it **replays its diff** as a brand-new commit with a new parent, a new timestamp and therefore
a new hash. The two branches now each contain that change independently.

That is the thing to understand about cherry-pick, and the source of its one real hazard: when
`feature` is eventually merged into `main`, the fix exists twice in the history. Git usually handles
it (the diffs are identical, so the second application is a no-op), but if anyone amended either copy,
you get a conflict over a change that was already applied.

### When it conflicts

**What this does:** cherry-picks a commit that touches a file `main` has also changed, then shows both ways out.

**Output**

```
########## A cherry-pick that conflicts ##########
# Both branches changed config.txt differently.
$ git cherry-pick 04795a3
Auto-merging config.txt
CONFLICT (add/add): Merge conflict in config.txt
error: could not apply 04795a3... Set timeout to 30 on feature
hint: After resolving the conflicts, mark them with
hint: "git add/rm <pathspec>", then run
hint: "git cherry-pick --continue".
hint: You can instead skip this commit with "git cherry-pick --skip".
hint: To abort and get back to the state before "git cherry-pick",
hint: run "git cherry-pick --abort".

$ git status --short
AA config.txt

$ cat config.txt        # conflict markers
<<<<<<< HEAD
config: timeout=10
=======
config: timeout=30
>>>>>>> 04795a3 (Set timeout to 30 on feature)

$ git cherry-pick --abort     # back out cleanly
(aborted)
$ cat config.txt
config: timeout=10
$ git status --short
(clean)

########## Resolving instead of aborting ##########
$ git cherry-pick 04795a3
Auto-merging config.txt
CONFLICT (add/add): Merge conflict in config.txt
error: could not apply 04795a3... Set timeout to 30 on feature
hint: After resolving the conflicts, mark them with
$ echo "config: timeout=30" > config.txt   # pick the incoming value
$ git add config.txt && git cherry-pick --continue
[main 20b8b7e] Set timeout to 30 on feature
 Date: Thu Sep 17 21:46:43 2026 +0000
 1 file changed, 1 insertion(+), 1 deletion(-)

$ git log --oneline -3
20b8b7e Set timeout to 30 on feature
e9e52f9 Set timeout to 10 on main
da9953d Fix critical auth bug
$ cat config.txt
config: timeout=30
```

`AA config.txt` in `git status` means **both sides added** the same path — an add/add conflict. The
markers show the two versions:

```
<<<<<<< HEAD                  <- what is on main now
config: timeout=10
=======
config: timeout=30            <- what the cherry-picked commit wants
>>>>>>> 04795a3 (Set timeout to 30 on feature)
```

Two ways out, both shown above:

| Command | Effect |
| --- | --- |
| `git cherry-pick --abort` | restore the branch exactly as it was — `config.txt` went back to `timeout=10` and the tree came back clean |
| `git cherry-pick --continue` | after editing the file and `git add`-ing it, complete the pick |
| `git cherry-pick --skip` | give up on this commit and move to the next (when picking a range) |

`--abort` is the safe default when a conflict is unexpected. Nothing is lost — the commit is still on
the source branch.

### Useful forms

| Command | What it does |
| --- | --- |
| `git cherry-pick <sha>` | one commit |
| `git cherry-pick <sha1> <sha2>` | several, in the order given |
| `git cherry-pick A..B` | a range, **excluding** A |
| `git cherry-pick A^..B` | a range, **including** A |
| `git cherry-pick -n <sha>` | apply to the working tree but do not commit |
| `git cherry-pick -x <sha>` | append `(cherry picked from commit ...)` to the message |

**`-x` is worth defaulting to** on shared branches — six months later it is the only record of where
a duplicated commit came from.

### Cherry-pick vs merge vs rebase

| | Takes | Use for |
| --- | --- | --- |
| **cherry-pick** | selected commits | a hotfix that must ship before its branch is ready |
| **merge** | an entire branch, preserving history | the normal way to integrate finished work |
| **rebase** | your commits, replayed onto a new base | tidying your own branch before opening a PR |

Cherry-pick is a targeted tool. Reaching for it routinely instead of merging produces duplicated
history that is painful to reason about later — the usual legitimate cases are backporting a fix to a
release branch, or rescuing a commit from a branch that is being abandoned.

---

## Summary

| # | Task | Key result |
| --- | --- | --- |
| 1 | `commit -m` vs `commit -a -m` | `-m` refused with nothing staged; `-a` took the tracked change but left `?? untracked.txt` |
| 2 | `cherry-pick` | one commit copied to `main` as a **new SHA**; only `hotfix.txt` arrived |
| 2b | conflict handling | `AA` add/add conflict, resolved once with `--abort` and once with `--continue` |
