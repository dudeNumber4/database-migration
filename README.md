# Database Change Management System
A (mostly) 2-part system for automating the propogation of database changes throughout all dev/stage/prod instances.  Database diff scripts are generated between database state changes (GenerateMigrationScript.ps1).  Ad-Hoc scripts can be added at any time as well.  CommitDatabaseScripts.ps1 adds scripts to DatabaseMigrationScripts.resources.  Scripts are numbered so that they can be replayed at any time (such as when creating an entirely new database and bringing it up to current state).  The record of scripts that have been executed is kept in a table created by MigrationsJournal.sql.  This script is placed as script #1 the first time CommitDatabaseScripts.ps1 is run.  At script exetution time ("Service" below), this journal is ensured to be present first.  The Service accounts for multiple instances starting up concurrently.

## Components
* Database Project
  * Powershell Scripts
  * Database compare: UpdateProject.scmp
  * Assumes directories "Scripts" and their 2 subdirectories exist.
  * DatabaseState.dacpac: A file that maintains the current database state.
* Service: A C# project that processes the scripts.
  * DatabaseMigrator.cs: entry point.
  * DatabaseMigrationScripts.resources: A resource file that contains the scripts that originated in the database project.

### Dependencies
1. sqlpackage.exe: Data Tools must be installed.
2. Visual Studio: The powershell scripts will only work from VS package manager console (see the scripts for details).
3. Sql Server.  DatabaseMigrator.cs (in Service) assumes Sql Server, but could probably be easily modified.

#### Configuration
* Add a database project to your solution, then add all the components of this database project except the actual dbo folder.
  * Note that the database name is, by default, the same as the project.  This can be overridden by setting the system defined $(DatabaseName) variable (currently in the SQLCMD Variables page of the database project).  This could probably be detected by the scripts, but is not currently the case; it assumes they are the same.
  * As such, rename the database project to match your database name.
    * The database name must be consistent across all environments.  I think this is a good thing.
  * In your solution configuration, remove the database project from the build; it will never need to be part of the normal build process and will fail if called from .net CLI.
* Add all items in "DatabaseMigration" directory inside the console application to your service/executable that will be responsible for executing database scripts 
   (might be nuget package, but can't really stand on it's own without the database project).
* Set the current state of your database:
   * Using UpdateProject.scmp:
     * Open the file, set the left side to point to your database; right side (target) to your database project.
     * Hit compare.
     * Update your database project.
     * Close it, saving changes/settings.
   * Run `./MigrationDatabase/UpdateDatabaseState.ps1`
* Add everything in the "DatabaseMigration" directory to your Service.
  * Set the build action property of DatabaseMigrationScripts.resources to "Content," "Copy Always."
* Search the solution for ":Configure:" and change where necessary.
* Add the MigrationsJournal.sql file (in this database project) to your database project.
* Run UpdateProject.scmp to update your database state.
* Generate your first script to run by running `GenerateMigrationScript.ps1` in package manager console.
* Commit changes.
* This script (plus the one to add the journal table which will placed in the first position) will be the first scripts other instances execute.

#### Usage
* Database Changes
  * Make database changes using any method.
    * Via application code.
    * Via database tooling, e.g., SSMS (caveat below).  If you use this method, transfer those changes to the database project using UpdateProject.scmp (launching it will show a UI for that purpose).  No need to save this file if prompted.
    * Via the database project scripts / objects.
  * Open package manager console, and run `./MigrationDatabase/GenerateMigrationScript.ps1`
    * Review script that should pop up.  Note that the generate script will be verbose (lots of `print` statements and comments).  The generation is a convenience; it's fine to delete all but what you really need.
  * Run `./MigrationDatabase/CommitDatabaseScripts.ps1`.  This "commits" the change to a resource file.
  * Commit changes to source.
  * Note that if you have already made the changes to your local database, the script will fail.  This is expected; if you made the changes _only_ in the database project, you do want them applied locally.  If the script fails, it won't be attempted again.
* Ad-Hoc Scripts
  * Add either way:
    * Right click on AdHoc folder in the database project; add new database script.
    * Write the script elsewhere and manually copy it into that directory.
  * If adding directly to AdHoc folder, your script will assume database context (intellisense on database objects, etc.).
  * Don't execute the script; system assumes these are to be executed via the Service.
  * Run `./MigrationDatabase/CommitDatabaseScripts.ps1`
  * Run Service (you could do this step after the next or even after pushing changes, but if there was an issue with the script and you didn't fix it, other instances will experience that issue).
  * Commit changes; script will now live in DatabaseMigrationScripts.resources.
* Other instances of your Service that hit other database instances will execute scripts that bring that database instance up to the current state.

##### Errors
* Startup.log in the same directory as the service will contain error indications and skipped (if already applied or attempted) scripts.
* The MigrationsJournal table in the database will show script executions.  If the AppliedCompleted column shows 0, the Msg column should show the error.
* To properly view the (multi-line) script that was executed that shows in the ScriptApplied column in SSMS, set query results to text (right click in a query window).
  * Additionally, you must set this option or the scripts that show in query results will be truncated:
  * Tools | Options | Query Results | SQL Server | Results to Text: Maximum number of characters displayed in each column: 65535
* To correct an error when you are able to restart the service:
  * Correct some condidition that exists in the database that caused the script to fail, delete the failed row in MigrationsJournal, and re-start the service.
* Above simple fix isn't enough or you can't restart the service:
  * In the target database run script `select * from MigrationsJournal where AppliedAttempted > DATEADD(day, -N, GetUtcDate())` where N is the number of days since the last deployment + 1.  This should give you the most recent scripts as well as those deployed on the previous deployment.
  * Locally, run script `./MigrationDatabase/ExtractResourceScripts.ps1` in package manager console.
  * In your local database run `select '[Script ' + convert(varchar, id) + ']', Script from ResourceScripts where id > N` where N is the Id of the last script that ran in the previous deployment.
    * See above SSMS setting to properly view output.
  * Ensure these most recent scripts match the rows in MigrationsJournal."
  * For each failed script:
    * Using transactions/rollbacks, reproduce the error seen in MigrationsJournal.  Modify the script until it's correct.
    * For completeness, each modified script should add an update for it's record in MigrationsJournal, e.g., `update MigrationsJournal set AppliedAttempted = GetUtcDate(), AppliedCompleted = 1 where Id = N`
  * Run these scripts on the target database.

##### Viewing / Modifying scripts in the resource
* To simply view the scripts in the resource, run `./MigrationDatabase/ExtractResourceScripts.ps1`.  The scripts will reside in a database table.  See notes in Errors section about properly viewing them.
* To modify the scripts in the resource for whatever reason:
  * Open visual studio developer command prompt.
  * `resgen ServiceProject/DatabaseMigrationScripts.resources ServiceProject/DatabaseMigrationScripts.resx`
  * Open DatabaseMigrationScripts.resx in visual studio.
  * From here, if necessary (such as to delete or correct a script), you could remove scripts, save, delete the original .resources file, and re-run resgen in reverse.

##### Database State
* The database state may get out of sync.  This means you run GenerateChangeScript and the changes include something that is already present in the database project, so you don't expect it as a new change.  One way this could happen is if you run some ad-hoc scripts and change the database project without running GenerateChangeScript as part of that process.
* In any case, if you're sure that you want to set the current state according to what is in the database project, run script `./MigrationDatabase/UpdateDatabaseState.ps1` to do so.

##### Merge Conflicts
* Merge conflicts (another team member merged database changes before yours) are non-resolvable.  In this event, you will have to re-do your changes:
  1. Whether you made them there, your changes should be present in your local database because you've tested them.  So I'll make that assumption.
  2. Undo changes on the following:
     1. In the database project (unless the only change you made was to add an ad-hoc script).
     2. DatabaseMigrationScripts.resources
     3. DatabaseState.dacpac.
  3. Follow instructions under main "Usage" section above.  Don't forget to re-do the step to transfer database changes to the database project via UpdateProject.scmp if necessary.

###### Manual Test Plan
* Beginning state (temp/junk database):
  * `CREATE TABLE [dbo].[Entity]([Id] [int] IDENTITY(1,1) primary key, [Name] [nvarchar](50) NULL)`
  * MigrationsJournal table doesn't exist in the database.
  * [database project]\DatabaseState.dacpac reflects database table state above:
	* Run UpdateProject.scmp to compare, uncheck the MigrationsJournal table (since it does exist in the project and we don't want to delete it), update the database project.
	* Run UpdateDatabaseState.
* Ensure there is already a script file (even if it's empty) in the "Migrations" folder.
* Refresh DatabaseMigrationScripts.resources with the content of Empty.resources
* Make backup of beginning dacpac state to compare against later.
	* "C:\temp\DatabaseMigration\BeginningState.dacpac"
* `alter table Entity add NewColumn varchar(10) null`
* Update the database project using UpdateProject.scmp
* Select the console project
* Run `GenerateMigrationScript`
	* Ensure it tells you to select the database project
* Select the database project and Run GenerateMigrationScript again
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
* Launch the executable.
  * An error should've been written to console.  This is expected because the new column already exists in your database instance.
  * Ensure the MigrationsJournal table is now present in the database.
  * MigrationsJournal table should have one row that reports the error that occurred above.
  * Ensure the row added to MigrationsJournal that had an error shows AppliedCompleted 0.
* Create 2 scripts in the AdHoc directory by right clicking on the AdHoc folder in the database project.  Make them both: `insert Entity values ('hi', 'mom')`
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
* Run ExtractResourceScripts.  Ensure it creates the table.
