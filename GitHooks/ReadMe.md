# Git Hooks
Configures the repo for database migrator usage.

## Components
* Deployment
  * deploy-database-git-scripts.ps1 sitting in the root of the repo configures the other components.
  * Configures the following components.
* Create Branch Hook
  * .git/hooks/post-checkout
  * Fires when (most) new branches are created.
  * CreateBranchHook.ps1 - called by the hook.
  * Searches for MSBuild and a database project in the repo.  If found, builds the database project and stored the output in the database project root.
  * This is used by the GenerateMigrationScript to compare the state of the database at the beginning of the branch to current state.

##### Deploy Script (deploy-database-git-scripts.ps1) manual tests
* Setup
  * gitignore doesn't contain any of our file types
  * No .git/hooks/post-checkout hook
  * CreateBranchHook.ps1 doesn't exist
* Run and check
  * gitignore has our file types
  * .git/hooks/post-checkout contains proper contents
  * GitHooks/CreateBranchHook.ps1 contains proper contents
* Run again
  * Check all of above again (idempotent)
* Run this command until you find a branch name that doesn't appear in the reflog:
  * `git reflog | grep 'temp'`
  * Checkout to that branch
  * Ensure the hook reports that it's building the database project and setting the database state file.
