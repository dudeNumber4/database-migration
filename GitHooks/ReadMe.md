# Git Hooks
Configures the repo for database migrator usage.

## Components
* Deployment
  * deploy-database-git-scripts.ps1 sitting in the root of the repo configures the other components.
  * Configures the following components.
* Merge Driver
  * Configured as a merge driver in the main config file.
  * .gitattributes tells which merge driver to call when a conflict occurs for .resource files
  * ResolveScriptResourceDifferences.ps1 (called by merge driver)
* Create Branch Hook
  * .git/hooks/post-checkout
  * Fires when (most) new branches are created.
  * CreateBranchHook.ps1 - called by the hook.
  * Searches for MSBuild and a database project in the repo.  If found, builds the database project and stored the output in the database project root.
  * This is used by the GenerateMigrationScript to compare the state of the database at the beginning of the branch to current state.

### Merge Driver Tests
* Used when initially testing.  The first one, "most basic" is scripted in AutomatedTest.ps1
```
• most basic
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (add)
		§ 3: 'second from Other'
	○ Current (add)
		§ 3: 'second from Current'
	○ Merge other to master
	○ Switch to current, merge master
	○ After Merge:
		§ 1: 'create table'
		§ 2: 'first'
		§ 3: 'second from Other'
		§ 4: 'second from Current'
• Add multiples in other
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (add)
		§ 3: 'second from Other'
		§ 4: 'third from Other'
	○ Current (add)
		§ 3: 'second from Current'
	○ Merge other into master
	○ After Merge master into current:
		§ 1: 'create table'
		§ 2: 'first'
		§ 3: 'second from Other'
		§ 4: 'third from Other'
		§ 5: 'second from Current'
• Add multiples in current
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (add)
		§ 3: 'second from Other'
	○ Current (add)
		§ 3: 'second from Current'
		§ 4: 'third from Current'
	○ Merge other to master
	○ After Merge master to current:
		§ 1: 'create table'
		§ 2: 'first'
		§ 3: 'second from Other'
		§ 4: 'second from Current'
		§ 5: 'third from Current'
• Feature branch
	• Master starts with
		§ "create table"
		§ "two"
	• Current
		§ switch to 'current'
		§ Sub branch A
		§ Add 3: 'feature branch added 3'
		§ switch to current; merge A in and nuke it
		§ Sub branch B
		§ add 4: 'four'
		§ switch to current; merge B in and nuke it
		§ Ensure current contains expected scripts.
	• Branch to other
		§ back to master; branch 'other' from that
		§ add 3: 'other branch added 3', remove 4
		§ switch to master; merge other in and nuke it
		§ Ensure master contains expected scripts.
	• Final merge
		§ switch to current; merge in master
	• Expected final
		• 1: "create table"
		• 2: "two"
		§ 3: 'other branch added 3'
		§ 4: 'feature branch added 3'
		§ 5: "four"
• Monkey'd with history
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (add)
		§ 3: 'second from Other'
	○ Current (add & change 2)
		§ 2: 'first changed'
		§ 3: 'second from Current'
	○ Merge other to master
	○ Merge master into current:
		§ 1: 'create table'
		§ 2: 'first changed'
		§ 3: 'second from Other'
		§ 4: 'second from Current'
• Both monkey'd with history and they differ
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (just change)
		§ 2: 'first changed'
	○ Current (just change)
		§ 2: 'first also changed'
	○ Merge other into master
	○ Merge master into other: Both branches being merged have modified an historical script.  Script number: 2
• Both monkey'd with history (and they are the same)
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (just change)
		§ 2: 'first changed'
	○ Current (just change)
		§ 2: 'first changed'
	○ Merge other into master
	○ After merge master into current
		§ 1: 'create table'
		§ 2: 'first changed'
• History was changed, and scripts were added.
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (just add)
		§ 3: 'second from other'
	○ Current (change & add)
		§ 2: 'second from current'
		§ 3: 'third from current'
	○ Merge other to master
	○ Merge master into current:
		§ 1: 'create table'
		§ 2: second from current (because it was historical)
		§ 3: second from other
		§ 4: third from current
• both modifying different object
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (just add)
		§ 3: blah drop table other blah
	○ Current (just add)
		§ 3: HI drop table current HI
	○ Merge other into master
	○ After Merge master into current:
		§ 1: 'create table'
		§ 2: 'first'
		§ 3: blah drop table other blah
		§ 4: HI drop table current HI
• both modifying same object
	○ Master
		§ 1: 'create table'
		§ 2: 'first'
	○ Other (just add)
		§ 3: blah drop table bubba blah
	○ Current (just add)
		§ 3: HI DROP TABLE BUBBA HI
	○ Merge other into master
	○ Upon Merge master into current:
		§ Halt; conflict indicator: "drop table bubba"
• Lacking foundation script
	○ NOTE: I haven't figured out what remain from running above scripts, but this one always seems to give unexpected results the first time (finds multiple historical in ancestor); passes the second.
	○ Master
		§ 1: 'create table'
	○ Other
		§ 1: 'junk'
	○ Current
		§ 1: 'more junk'
	○ Merge other into master
	○ Upon merging master into current:
		§ Halt; missing foundational script.
```

### Deploy Script (deploy-database-git-scripts.ps1) Tests
```
• Setup
	○ config contains a chunk of some type (grab from some other repo)
	○ No .gitattributes file exists
	○ No ResolveScriptResourceDifferences.ps1
	○ No .git/hooks/post-checkout
• Run and check
	○ config contains 2 chunks (what was already present above and the new one for the merge driver)
	○ .gitattributes contains the one line
	○ ResolveScriptResourceDifferences.ps1 contains proper contents
	○ .git/hooks/post-checkout contains proper contents
	○ CreateBranchHook.ps1 contains proper contents
• Run again
	○ Check all of above again
```