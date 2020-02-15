# Database Change Management System
A system for automating the propogation of database changes throughout all dev/stage/prod instances.  Database diff scripts are generated between database state changes (`GenerateMigrationScript.ps1`).  Ad-Hoc scripts can be added at any time as well.  `CommitDatabaseScripts.ps1` adds scripts to DatabaseMigrationScripts.resources.  Scripts are numbered so that they can be replayed at any time (such as when creating an entirely new database and bringing it up to current state).  The record of scripts that have been executed is kept in a table created by `MigrationsJournal.sql`.  This script is placed as script #1 the first time `CommitDatabaseScripts.ps1` is run.  At script exetution time ("Service" below), this journal is ensured to be present first.  The Service accounts for multiple instances starting up concurrently.

## Components
* Database Project
  * Powershell Scripts
  * Database compare: `UpdateProject.scmp`
  * Assumes directories "Scripts" and their 2 subdirectories exist.
  * `DatabaseState.dacpac`: A file that captures database state represented by the project.
* DatabaseMigrator: A C# project that processes the scripts.
  * `DatabaseMigrator.cs`: entry point.
  * `DatabaseMigrationScripts.resources`: A resource file that contains the scripts that originated in the database project.
* Service: A sample service that utilizes DatabaseMigrator
* Git Hooks: Refer to the separate ReadMe in the GitHooks folder.

### Dependencies
1. sqlpackage.exe: Sql Server Data Tools must be installed.
2. Visual Studio: The powershell scripts will only work from VS package manager console (see the scripts for details).
3. Sql Server.  `DatabaseMigrator.cs` assumes Sql Server, but could probably be easily modified for a different database.
4. Git version (whatever version introduced merge hooks/drivers; I really couldn't determine).
5. Powershell v6 (core) or greater.  To ensure it's installed correctly, open a git bash shell and type `where pwsh`.  If it can't be found; find where it's installed and ensure that's on your path.

#### Initial Configuration (i.e., what the nuget package that doesn't yet exist should do)
* Add a database project to your solution, then add all the components of this database project except the actual dbo folder (with one exception below).
  * Note that the database name is, by default, the same as the project.  This could probably be detected by the scripts, but is not currently the case; it assumes they are the same.
  * As such, rename the database project to match your database name.
    * The database name must be consistent across all environments.  I think this is a good thing.
  * In your solution configuration, remove the database project from the build; it will never need to be part of the normal build process and will fail if called from .net core CLI.
* Set the current state of your database:
   * Using `UpdateProject.scmp`:
     * Open the file, set the left side to point to your database; right side (target) to your database project.  NOTE: reference your local server as '.', not with your machine name.  This so your teammates can use the compare file as is - it will persist.
     * Hit compare.
     * Update your database project.
     * Close it, saving changes/settings.
* Add the `MigrationsJournal.sql` file (in dbo folder) to your database project's dbo (or explicitly named schema if you have one) folder.  After the first time you run your service, this table will be in your database.
* Reference "DatabaseMigrator" from your Service.
  * Set the build action property of DatabaseMigrationScripts.resources to "Content," "Copy Always."
* Search the solution for ":Configure:" and change where necessary.
* Open a powershell console and run `deploy-database-git-scripts.ps1`
* In .bash_profile or .bashrc add `export GIT_MERGE_AUTOEDIT=no`
  * Otherwise you'll get a *halting* message upon _properly resolved_ merge conflicts.  I don't understand why git does this; it just seems wrong to me.

#### Usage
* It never hurts to run UpdateProject.scmp prior to making changes just to sanity-check that your local database matches what's in the database project.  This will ensure that `databaseState.dacpac` (that should've been created upon creating a new branch -see section "Database State") has the correct state.
* Schema Changes
  * _Note_: It's a good practice to commit after making and testing changes, but before committing the database change script.
  * Letting the system generate your script:
    * _Note_: If you are familiar with TSQL DDL, you have a simple database change, and you know what script will be required for the change, see Ad-Hoc section below.
    * If you have a task that will make table changes (especially if multiple), it's best to take a backup of your local database in it's pre-changed state.  It's not absolutely necessary, but it can be very helpful if you want to test the generated script before committing it.
    * Make database changes using any method.
      * Via application code.  Note that it's not a good idea to have code _recreate_ database objects since database objects may have changes applied to them subsequent to creation, e.g., an index was added.  If they differ, then the database state will diverge from what's in the database project which is the source of truth for database objects.
      * Via database tooling, e.g., SSMS (preferred).
        * If you use this method, transfer those changes to the database project using `UpdateProject.scmp`:
          * Launch `UpdateProject.scmp`, ensure the database is the selected item at top left; project is selected at top right.
          * Click compare.  Look at the differences, they should just include your recent changes.
          * Click "Update" to transfer the changes to the database project.
          * No need to save this file when closing it.
      * Via the database project scripts / objects.
    * Open package manager console, and run `./MigrationDatabase/GenerateMigrationScript.ps1`
      * Note: _If you see something unexpected_, refer to the "Database State" section.
      * Review script that should pop up: READ THE WARNING ABOUT HOW TO TEST THE SCRIPT!!
      * Note that the generated script will be verbose (lots of `print` statements and comments); it's fine to delete all but what you really need.
      * _Recommended_: Add a single line comment at the top of the script describing what it does.  This makes for handy reading when reviewing scrips (section _Viewing / Modifying scripts in the resource_).
    * Run `./MigrationDatabase/CommitDatabaseScripts.ps1`.  This "commits" the change to resource file `DatabaseMigrationScripts.resources`.
    * Commit changes to source.
    * Note that if you have already made the changes to your local database, the script should fail.  This is expected if your script is not idempotent; if you made the changes _only_ in the database project, you do want them applied locally.  In any case, if the script fails, it won't be attempted again.
* Ad-Hoc Scripts
  * Add an ad-hoc script by right clicking on AdHoc folder in the database project -> add -> new database script (file name makes no difference; it's temporary).
  * Your script will assume database context (intellisense on database objects, etc.).
  * Note that it's a good idea to make ad-hoc scripts idempotent, e.g., `drop object if exists`.  This way, the script will never record an error.
  * Run `./MigrationDatabase/CommitDatabaseScripts.ps1`
    * If you added a script that makes schema changes (you preferred to write your own rather than let the system generate one), ensure you make the corresponding update to the database project so the overall database state is correct.
  * Commit (to source control) changes; script lives in `DatabaseMigrationScripts.resources`.
* Other instances of your Service that hit other database instances will execute scripts that bring that database instance up to the current state.
* Script Execution Order
  * The scripts you commit will execute _in order_ when promoted to other environments.  If order matters, e.g., you create a table and also add a script to populate that table, they must be committed in the proper order.  You can commit a migration script and an ad-hoc script at the same time (and the output will report in which order they were added), but in this case it's better to commit the create table script first, then commit the ad-hoc populate script.
* Testing
  * Sometimes the generated script will fail on other instances, e.g., you added a non-nullable column and the script will try to move data from the existing table into the new one without explicitly providing a value for the new non-nullable column.
  * If you add an Ad-Hoc script, it's assumed you've tested it.  If you generated a script, ensure to follow the advice/instructions about testing it that appear in the script.

##### Errors
* Startup.log in the same directory as the service will contain some error indications.
* The MigrationsJournal table in the database will show script executions.  If the AppliedCompleted column shows 0, the Msg column should show the error.
* To properly view the (multi-line) script that was executed that shows in the ScriptApplied column in SSMS, set query results to text (right click in a query window).
  * Additionally, you must set this option or the scripts that show in query results will be truncated:
  * Tools | Options | Query Results | SQL Server | Results to Text: Maximum number of characters displayed in each column: 65535
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

##### Viewing / Modifying scripts in the resource
* To simply view the scripts in the resource, run `./MigrationDatabase/ExtractResourceScripts.ps1`.  The scripts will reside in a database table named ResourceScripts.  See notes in Errors section about properly viewing them.
  * To see the most recent scripts, run `select top 2 * from ResourceScripts order by id desc`
* To modify the scripts in the resource for whatever reason:
  * Open visual studio developer command prompt.
  * `resgen ServiceProject/DatabaseMigrationScripts.resources ServiceProject/DatabaseMigrationScripts.resx`
  * Open DatabaseMigrationScripts.resx in visual studio.
  * From here, you can make changes, save, delete the original .resources file, and re-run resgen in reverse (.resx -> .resources).

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
    * Run script `UpdateDatabaseState`.
    * Checkout back to the branch you just left.
    * Re-run script `GenerateMigrationScript`.
  * _Merge/Rebase_:
    * Commit/stash current changes if necessary.
    * View log; checkout to the commit prior to the merge/rebase (`git checkout -b temp SHA`).  This checkout should not regenerate the state file.
    * Run script `GenerateMigrationScript`.
    * Checkout back to the branch you just left.
    * The generated script should contain just the changes you need.
* In any case, if you're sure that you want to set the current state to match what is in the database project, run script `./MigrationDatabase/UpdateDatabaseState.ps1` to do so.
  * If you realize this didn't happen upon branch creation, for instance...

##### Merging
* A merge conflict will occur under either of these conditions:
  1. Your branch and another branch modified the same numbered historical script.
  2. Your branch and another branch are modifying the same database object.
* In this event, you will have to manually merge scripts.  The following assumes you have aborted a merge (`git merge --abort`):
  1. See section "Viewing / Modifying scripts in the resource" above.  Run the `resgen` command described.
  2. Open the .resx file in visual studio, identify the script(s) you have added.  If it's difficult to find the one you added, you can follow the first two bullet points in the "viewing" section to quickly identify your script id/number.  Once you know that, you can find your script number in the .resx file.  Note that you can actually search the .resx while open.
  3. Copy your script (and it's number) somewhere separately.  Copy the .resx file outside the repo somewhere.
  4. Switch to the branch you need to merge with.
  5. Follow the same steps to copy out the other branch's script(s) and their numbers.
  6. Examine the scripts; ensure they don't conflict.
  7. Switch back to your branch.  Open the .resx file you saved separately.
  8. Add/update the scripts to the .resx with proper numbers.  Ex: both scripts were committed as script #15.  One must assume #15, the other #16.  Note that they will be executed in that order.
  9. Run the `resgen` command to convert the .resx back to .resources.
  10. Delete the .resx and commit this new version of .resources to your branch.

##### Revert Changes Already Committed to Source
* This should be _very rare_.
* You want to re-do scripts at a given point in git commit history.
* Identify the point in history you want to begin with (just prior to the changes you want to eliminate).  Revert / checkout that commit.
* Copy `DatabaseMigrationScripts.resources` to a location outside the repo.
* Checkout back to current, overwrite `DatabaseMigrationScripts.resources`.
* Re-do the process under Usage.

###### Manual System Test Plan
* Beginning state (temp/junk database):
  * `CREATE TABLE [dbo].[Entity]([Id] [int] IDENTITY(1,1) primary key, [Name] [nvarchar](50) NULL)`
  * Database table 'Entity' only has Id, Name
  * MigrationsJournal table doesn't exist in the database.
  * [database project]\DatabaseState.dacpac reflects database table state above (run UpdateProject.scmp to compare, build database project, copy the output over DatabaseState.dacpac
	* Ensure there is already a script file (even if it's empty) in the "Migrations" folder.
	* `truncate table Entity`
	* Refresh DatabaseMigrationScripts.resources with the content of Empty.resources
* Make backup of beginning dacpac state to compare against later.
	* "C:\temp\beginningState.dacpac"
* Add "NewColumn" (varchar 10) to table using SSMS (or other tool) directly.
* Update the database project using UpdateProject.scmp
* Select the console project
* Run `GenerateMigrationScript`
	* Ensure it tells you to select the database project
* Select the database project and Run GenerateMigrationScript again
  * Ensure it warns that the journal table isn't present.  Run MigrationsJournal.sql to add the table.
* Run `GenerateMigrationScript` again
  * Ensure a script pops up for adding "NewColumn" to table Entity.
  * Ensure it's in the "Migrations" directory.
  * Ensure a custom comment is at the top informing you about the script generated.
  * Ensure the script will "parse" using the toolbar.
* Run `CommitDatabaseScripts`
  * Ensure it tells you that there are multiple scripts in Migrations folder.
* Delete the extra junk sql file in the Migrations folder and Run `CommitDatabaseScripts` again.
  * Ensure it informs you that it's adding the journal table as the first script.
  * Ensure the Scripts/Migrations folder is empty.
  * Ensure DatabaseState.dacpac and the recent build file match.
  * Ensure beginningState.dacpac and new one don't match.
  * Ensure file DatabaseMigrationScripts.resources.bak (temp file in same directory as the original) has been cleaned up (doesn't exist).
* Launch the executable; ensure it reports that it skipped the script (it added a row for you the developer in MigrationsJournal because you applied it).  Ensure other output is as expected (no errors).
* Create 2 scripts in the AdHoc directory by right clicking on the AdHoc folder in the database project.  They can both have as their command: `insert Entity values ('console test', 'console test')`
* Run `CommitDatabaseScripts`
  * Ensure console output reports that the new scripts were added to resource.
  * Ensure that the files you created and the project references to them have been cleaned up.
* Launch the service.
  * Ensure it reports that it ran the 2 new scripts (#3 & 4).
  * Ensure Entity table has the rows added by the scripts, and that the journal contains 2 new entries recording script them.
  * Ensure the journal table ScriptApplied column shows the script.
* `drop table MigrationsJournal`
* `alter table Entity drop column NewColumn`
* Launch the service.
  * Ensure it recreates the MigrationsJournal table, re-adds column NewColumn to Entity, and adds the 2 rows to Entity.
* Add another ad-hoc script that will generate an error upon execution.
* Commit the script, run the service.
* Ensure the row added to MigrationsJournal shows that the script was attempted, but not completed.