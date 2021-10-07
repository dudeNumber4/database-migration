# Database Change Management System
A system for automating the propogation of database changes throughout all dev/stage/prod instances.  Database diff scripts are generated between database state changes (`GenerateMigrationScript.ps1`).  Ad-Hoc scripts can be added at any time as well.  `CommitDatabaseScripts.ps1` adds scripts to a known directory for execution at runtime.  Scripts are numbered so that they can be replayed at any time (such as when creating an entirely new database and bringing it up to current state).  The record of scripts that have been executed is kept in a table created by `MigrationsJournal.sql`.  This script is placed as script #1 in the script runtime directory.  At script execution time ("Service" below), this journal is ensured to be present first.  The Service accounts for multiple instances starting up concurrently (load balancing).

## Components
* Database Project
  * Powershell Scripts
  * Database compare: `UpdateProject.scmp`
  * Well known "Scripts" directory and it's 2 subdirectories.
  * `DatabaseState.dacpac`: A file that captures database state represented by the project.
* A .Net project (your service) that processes the scripts.
  * DatabaseMigration/RuntimeScripts: Folder that contains the scripts that originated in the database project.
* Git Hooks: Refer to the separate ReadMe in the GitHooks folder.

### Dependencies
1. sqlpackage.exe: Sql Server Data Tools must be installed.
2. Visual Studio: The powershell scripts will only work from VS package manager console (see the scripts for details).
3. Sql Server.  `DatabaseMigrator.cs` assumes Sql Server, but could probably be easily modified for a different database.  There must only be one database to manage in the repository where this is put into place.
4. Git.
5. Powershell v7 or greater.  To ensure it's installed correctly, open a git bash shell and type `where pwsh`.  If it can't be found, find where it's installed and ensure that's on your path.
6. Note: You are expected to initially create your database project; the initial configuration script doesn't do that.  Your database project name and database name are expected to match.

#### Initial Configuration
* Install nuget package under your service.  Install will throw a ReadMe with initial configuration instructions that includes a powershell configuration srcipt.
* Add migrator code to your service:
  * `using var migrator = new DatabaseMigrator(new ConsoleStartupLogger());`
    * Logger is a façade to your logging system that implements IStartupLogger
  * `var results = migrator.PerformMigrations(YOUR_CONNECTION_STRING); // results contain schema changing scripts`
* Start/run your service.
  * Your database should now have a table named MigrationsJournal.  If not, check whatever logging you plugged in above.
* Set the current state of your database project:
   * Using `UpdateProject.scmp`:
     * Open the file, set the left side to point to your database; right side (target) to your database project.  NOTE: reference your local server as '.', not with your machine name.  This so your teammates can use the compare file as is - it will persist.
     * Hit compare.
       * Note: If you don't care about users, roles, etc., you can go into compare options and deselect those types of objects.
     * Update your database project (adding to it any objects that may already exist in your database).
     * Close it, saving changes/settings.

### Usage
* Here are the 2 main use cases:
  * Letting it help you with scripts. (In addition to this section, see next section below).
    * Upon branch creation, the current database state is captured (see section Database State for more).
    * Make your changes via code, directly in your database, or in the database project.
      * If you make changes in code or in the database, update the database project:
        * Launch `UpdateProject.scmp`, ensure the database is the selected item at top left; project is selected at top right.
        * Click compare.  Look at the differences, they should just include your recent changes.
        * Click "Update" to transfer the changes to the database project.
        * No need to save this file when closing it.
      * Open package manager console, and run `./MigrationDatabase/GenerateMigrationScript.ps1`
        * Note: _If you see something unexpected_, refer to the "Database State" section.
        * Review script that should pop up: READ THE WARNING ABOUT HOW TO TEST THE SCRIPT!!
        * Note that the generated script will be verbose (lots of `print` statements and comments); it's fine to delete all but what you really need.
        * _Recommended_: Add a single line comment at the top of the script describing what it does.  This makes for handy reading when reviewing scripts (section _Viewing / Modifying Committed Scripts_).
      * Run `./MigrationDatabase/CommitDatabaseScripts.ps1`
  * Writing your own scripts.
    * Add an ad-hoc script by right clicking on AdHoc folder in the database project -> add -> new database script (file name makes no difference; it's temporary).
      * In order to get the right UI to appear above your script (including the tooling to parse your script), select an item under the section "User Scripts."
    * Your script will assume database context (intellisense on database objects, etc.).
    * Save and close your script.
    * Run `./MigrationDatabase/CommitDatabaseScripts.ps1`
      * If you added a script that makes schema changes (you preferred to write your own rather than let the system generate one), ensure you make the corresponding update to the database project so the overall database state is correct.
      * Once the script has already been applied to your local database, you can do that using UpdateProject.scmp (see "If you make changes in code or in the database" above)
* Notes:
  * Even if you prefer to write your own scripts, it never hurts to run `./MigrationDatabase/GenerateMigrationScript.ps1` as outlined in "Basic Usage" above.  Sometimes this will actually remind you of a change you forgot you made.
  * It's a good practice to commit after making and testing changes, but before adding your change script.
  * It never hurts to run UpdateProject.scmp prior to making changes just to sanity-check that your local database matches what's in the database project.  This will ensure that `databaseState.dacpac` (that should've been created upon creating a new branch; see section "Database State") has the correct state.
  * If you have a task that will make table changes (especially if multiple), it's best to take a backup of your local database in it's pre-changed state.  It's not absolutely necessary, but it can be very helpful if you want to test the generated script before committing it.
  * it's not a good idea to have code _recreate_ database objects since database objects may have changes applied to them subsequent to creation, e.g., an index was added.  If they differ, then the database state will diverge from what's in the database project which is the source of truth for database objects.
  * Committed scripts live in DatabaseMigration/RuntimeScripts.
  * If you have already made the changes to your local database, and you write your own schema change script, the script should fail.  This is expected if your script is not idempotent, e.g., `drop object if exists`; if you made the changes _only_ in the database project, you _do_ still need them applied locally.  In any case, if the script fails, it won't be attempted again.
  * Other instances of your Service that hit other database instances will execute scripts that bring that database instance up to the current state.
  * Individual scripts may contain separate `Go` execution sections.
* Script Execution Order
  * The scripts you commit will execute _in order_ when promoted to other environments.  If order in your current change matters, e.g., you create a table and then populate that table, they must be committed in the proper order or made part of the same script.  You can commit a migration script and an ad-hoc script at the same time and the output will report in which order they were added.
* Testing
  * Sometimes the generated script will fail on other instances, e.g., you added a non-nullable column to a table that contains existing data.
  * If you add an Ad-Hoc script, it's assumed you've tested it.  If you generated a script, ensure to follow the advice/instructions about testing it that appear in the script.

#### I have a list of changes in mind, how can I simply generate a script for them?
Regardless of where you are in the process of making a change (perhaps you made some changes, them backed them out), you have a database instance in a given state, you know you need to make a given set of changes (or even just a single), and you want to generate a script.

Let's assume that your `dev` database is in the starting state.  Here are the steps:
* Open `UpdateProject.scmp`.
* Set the left side to connect to `dev`, set the right side to the database project.
* Click Update: this will make the database project match the state that dev is in.
* In package manager explorer, run `./MigrationDatabase/UpdateDatabaseStateFile.ps1`.  This sets the database state start point (the same thing that happens when you create a new branch).
* Make the necessary changes in your local database (or in the database project).
* If you made the changes in your local database, you will need to transfer them to the database project: Open `UpdateProject.scmp`, set the left side to your local database.  Click Update to update the database project.
* In package manager explorer, run `./MigrationDatabase/GenerateMigrationScript.ps1`
* Review the script; it should contain all the actions necessary to make the changes.  If it looks good, run `./MigrationDatabase/CommitDatabaseScripts.ps1`

##### Errors
* Startup.log in the same directory as the service will contain some error indications.
* The MigrationsJournal table in the database will show script executions.  If the AppliedCompleted column shows 0, the Msg column should show the error.
* To properly view the (multi-line) script that was executed that shows in the ScriptApplied column in SSMS, set query results to text (right click in a query window).
  * Additionally, you must set this option or the scripts that show in query results will be truncated:
  * Tools | Options | Query Results | SQL Server | Results to Text: Maximum number of characters displayed in each column: 65535
* The most straight-forward way to correct a failed script is to commit another script and re-deploy your service.
* To correct an error when you are able to restart the service:
  * Correct some condidition that exists in the database that caused the script to fail, delete the row in MigrationsJournal that recorded the failure for that script, and re-start the service.
  * In development, you may be able to drop every object in the database and re-run the service; all scrips will be re-applied.
* Above simple fix isn't enough or you can't restart the service:
  * In the target database run script `select * from MigrationsJournal where AppliedAttempted > DATEADD(day, -N, GetUtcDate())` where N is the number of days since the last deployment + 1.  This should give you the most recent scripts as well as those deployed on the previous deployment.
  * Locally, run script `./MigrationDatabase/ExtractResourceScripts.ps1` in package manager console.
  * In your local database run `select '[Script ' + convert(varchar, id) + ']', Script from ResourceScripts where id > N` where N is the Id of the last script that ran in the previous deployment.
    * See above SSMS setting to properly view output.
  * Ensure these most recent scripts match the rows in MigrationsJournal table."
  * For each failed script:
    * Using transactions/rollbacks, reproduce the error seen in MigrationsJournal.  Modify the script until it's correct.
  * Run these scripts against the database where they failed.
    * [optional] For completeness, each modified script should add an update for it's record in MigrationsJournal, e.g., `update MigrationsJournal set AppliedAttempted = GetUtcDate(), AppliedCompleted = 1 where Id = N`

##### Viewing / Modifying Committed Scripts
* Scripts can be viewed directly in their DatabaseMigration/RuntimeScripts directory.
* To extract scripts to a local database table, run `./MigrationDatabase/ExtractResourceScripts.ps1`.  The scripts will reside in a database table named ResourceScripts.  See notes in Errors section about properly viewing them.
  * To see the most recent scripts, run `select top 2 * from ResourceScripts order by id desc`

##### Database State
* Upon creation of a new branch, the current state of the database is cached to a file named `databaseState.dacpac`.  You may notice some output to this effect during branch creation.  After you work your changes and you invoke `GenerateMigrationScript`, the script that is generated compares the current state of the database project with the state cached at branch creation.
* This isn't perfect:
  a. _Multiple Branches_: If you create a branch, make some changes, update the database project, create another branch from that, make more changes, etc., your final generated script won't include changes you made in the first branch.
  b. _Merge/Rebase_: You create a branch, make some changes, merge/rebase onto another branch that has other changes, your final generated script will include changes already made in the other branch.
  c. The git hook for creation/cache only works if you create a new branch _and you've never created a branch by that name before_.  I don't currently know of a way around this; the hook would have to be quite a bit smarter to account for it.
  d. Note that, upon running `CommitDatabaseScripts`, the system will compare local database project state with local database state and warn the user if the two are not in sync.
* If the generated script doesn't include changes you expected, here are your options:
  * Modify the generated script as necessary before running `CommitDatabaseScripts`.
  * Delete the generated script and write your own as an Ad-Hoc script.
  * _Multiple Branches_:
    * Commit/stash current changes if necessary.
    * View log; checkout to the commit at the beginning of the first branch (`git checkout -b temp SHA`).  This checkout should not regenerate the state file.
    * Run script `UpdateDatabaseStateFile`.
    * Checkout back to the branch you just left.
    * Re-run script `GenerateMigrationScript`.
  * _Merge/Rebase_:
    * Commit/stash current changes if necessary.
    * View log; checkout to the commit prior to the merge/rebase (`git checkout -b temp SHA`).  This checkout should not regenerate the state file.
    * Run script `GenerateMigrationScript`.
    * Checkout back to the branch you just left.
    * The generated script should contain just the changes you need.
* In any case, if you're sure that you want to set the current state file to match what is in the database project, run script `./MigrationDatabase/UpdateDatabaseStateFile.ps1` to do so.
  * If you realize this didn't happen upon branch creation, for instance...

##### Scripts that Change Schema
* `PerformMigrations` returns a list of scripts that have been applied which were schema-changing.  The consuming service may decide to do something in response to that.

##### Merging
* If your branch and another both add a new script there will be a merge conflict.  You will need to keep one and add the other under a new file name with the next number increment.
