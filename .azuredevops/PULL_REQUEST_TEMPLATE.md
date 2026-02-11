> **Note:** This checklist applies only to PRs from main to release/prod. For feature PRs to main, ignore these instructions.

---

⚠️ When you do a squash merge PR to release/prod.. ⚠️

- .. make sure the PR title always start with `fix:`, `feat:` or `release:`.
- .. click *Complete* and choose *Squash commit* under 'merge type'.
- .. check the box "Customize merge commit message" and remove Azures added title, ex. "Merged PR 40:" so that the title starts with one of the semantic release key words above.  


| Type      | Version bump | Example   |
|-----------|--------------|-----------|
| fix       | patch        | 1.0.1     |
| feat      | minor        | 1.2.0     |
| release   | major        | 2.0.0     |

---
### Describe what this PR does

<!-- Describe what changed in the code the effect it has. -->
