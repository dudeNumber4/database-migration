# Database Change Management System
A system for automating the propogation of database changes throughout all dev/stage/prod instances.  Database diff scripts are generated between database state changes (`GenerateMigrationScript.ps1`).  Ad-Hoc scripts can be added at any time as well.  `CommitDatabaseScripts.ps1` adds scripts to a known directory for execution at runtime.  Scripts are numbered so that they can be replayed at any time (such as when creating an entirely new database and bringing it up to current state).  The record of scripts that have been executed is kept in a table created by `MigrationsJournal.sql`.  This script is placed as script #1 in the script runtime directory.  At script execution time ("Service" below), this journal is ensured to be present first.  The Service accounts for multiple instances starting up concurrently.

## Components
* Database Project
  * Powershell Scripts
  * Database compare: `UpdateProject.scmp`
  * Well known "Scripts" and it's 2 subdirectories.
  * `DatabaseState.dacpac`: A file that captures database state represented by the project.
* DatabaseMigrator: A C# project that processes the scripts.
  * `DatabaseMigrator.cs`: entry point.
  * DatabaseMigration/RuntimeScripts: Folder that contains the scripts that originated in the database project.
* Service: A sample service that utilizes DatabaseMigrator
* Git Hooks: Refer to the separate ReadMe in the GitHooks folder.

### Dependencies
1. sqlpackage.exe: Sql Server Data Tools must be installed.
2. Visual Studio: The powershell scripts will only work from VS package manager console (see the scripts for details).
3. Sql Server.  `DatabaseMigrator.cs` assumes Sql Server, but could probably be easily modified for a different database.  There must only be one database to manage in the repository where this is put into place.
4. Git version (whatever version introduced merge hooks; I really couldn't determine).
5. Powershell v6 (core) or greater.  To ensure it's installed correctly, open a git bash shell and type `where pwsh`.  If it can't be found; find where it's installed and ensure that's on your path.

#### Initial Configuration (i.e., what the nuget package that doesn't yet exist should do)
* Add a database project to your solution.
  * Note that the database name is, by default, the same as the database project.  This could probably be detected by the scripts, but is not currently the case; it assumes they are the same.
  * As such, name the database project to match your database name.  If you don't already have a database, create one with the same name as your database project.
    * The database name must be consistent across all environments.  I think this is a good thing.
  * Add all .ps1 and psm1 scripts from the root of this `MigrationDatabase` project to the root of your database project.
  * Add folders Scripts/AdHoc and Scripts/Migrations to your database project.
  * Copy `UpdateProject.scmp` from this `MigrationDatabase` to your database project.
  * In your solution configuration, remove the database project from the build for Debug and Release; it will never need to be part of the normal build process and will fail if called from .net core CLI.
  * Add a table named MigrationsJournal to your database project.  Set it's (text) definition to this project's table of that name.
* Set the current state of your database project:
   * Using `UpdateProject.scmp`:
     * Open the file, set the left side to point to your database; right side (target) to your database project.  NOTE: reference your local server as '.', not with your machine name.  This so your teammates can use the compare file as is - it will persist.
     * Hit compare.
     * Update your database project (adding to it any tables that may already exist in your database).
     * Close it, saving changes/settings.
* Copy the `DatabaseMigration` project into your solution.
* Reference `DatabaseMigration` from your Service.
* Search the solution for ":Configure:" and change where necessary.
* Copy `deploy-database-git-scripts.ps1` to the root of your repo.  Open a powershell console and run it: `. ./deploy-database-git-scripts.ps1`
* Somewhere in your service startup, call DatabaseMigrator.PerformMigrations.
* Run your service; ensure table MigrationsJournal has been added to your database.
* Copy this ReadMe into your database project.  Search / Replace "MigrationDatabase" below this point and change to your database project name.

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

##### Merging
* If your branch and another both add a new script there will be a merge conflict.  You will need to keep one and add the other under a new file name with the next number increment.

###### Manual System Test Plan
* Beginning state (temp/junk database):
  * Create below table; no other tables should exist in the database.
  * `CREATE TABLE [dbo].[Entity]([Id] [int] IDENTITY(1,1) primary key, [Name] [nvarchar](50) NULL)`
  * [database project]\DatabaseState.dacpac reflects database table state above (run UpdateProject.scmp to compare, update database project, then run script UpdateDatabaseStateFile.ps1)
	* Directory DatabaseMigration\RuntimeScripts should only have the 1.sql (the initial MigrationsJournal creation script).
* Make backup of MigrationDatabase\DatabaseState.dacpac to compare against later.
	* "C:\temp\beginningState.dacpac"
* Add "NewColumn" (varchar 20) to table directly in Entity.sql
* Select the service project
* Run `GenerateMigrationScript`
	* Ensure it tells you to select the database project
* Select the database project and Run `GenerateMigrationScript` again
  * Ensure a script pops up for adding "NewColumn" to table Entity.
  * Ensure it's in the Scripts\Migrations directory.
  * Ensure a custom comment is at the top informing you about the script generated.
  * Ensure the script will "parse" using the toolbar.
* Close the script and run `GenerateMigrationScript` again.
  * It should create the same script under a different (guid) name.
* Close the script file and run `CommitDatabaseScripts`
  * Ensure it tells you that there are multiple scripts in Migrations folder.
* Delete one of the guid sql files in the Scripts\Migrations folder and Run `CommitDatabaseScripts` again.
  * Ensure it named the guid file in DatabaseMigration\RuntimeScripts to 2.sql
  * Ensure the Scripts/Migrations folder is empty.
  * Ensure the DatabaseMigration references the new script under the \RuntimeScripts folder
* Launch the executable; ensure it _doesn't_ report that it skipped script 2.
* Ensure table `MigrationsJournal` exists with one record (for script 2).
* Ensure the new column was added to the table.
* Create 2 scripts in the AdHoc directory by right clicking on the AdHoc folder in the database project.  They can both have as their command: `insert Entity values ('console test', 'console test')`
* Run `CommitDatabaseScripts`
  * Ensure console output reports that the new scripts were added as resource files.
  * Ensure that the files you created and the project references to them (in the database project) have been cleaned up.
  * Ensure that both files were added to DatabaseMigration\RuntimeScripts
  * Ensure that bothe files' properties are build action embedded resource, copy if newer.
* Launch the service.
  * Ensure it reports that it skipped script #2 (already applied).
  * Ensure Entity table has the rows added by the scripts, and that the journal contains 2 new entries recording script them.
* `drop table MigrationsJournal`
* `truncate table Entity`
* `alter table Entity drop column NewColumn`
* Launch the service.
  * Ensure it recreates the MigrationsJournal table, re-adds column NewColumn to Entity, and adds the 2 rows to Entity.
* Add another ad-hoc script that will generate an error upon execution.
* Commit the script, run the service.
* Ensure the row added to MigrationsJournal shows that the script was attempted, but not completed.