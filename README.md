# Database Change Management System
A (mostly) 2-part system for automating the propogation of database changes throughout all dev/stage/prod instances.  Database diff scripts are generated between database state changes (GenerateMigrationScript.ps1).  Ad-Hoc scripts can be added at any time as well.  CommitDatabaseScripts.ps1 adds scripts to DatabaseMigrationScripts.resources.  Scripts are numbered so that they can be replayed at any time (such as when creating an entirely new database and bringing it up to current state).  The record of scripts that have been executed is kept in a table created by MigrationsJournal.sql.  This script is placed as script #1 the first time CommitDatabaseScripts.ps1 is run.  At script exetution time ("Service" below), this journal is ensured to be present first.  The Service accounts for multiple instances starting up concurrently.

## Components
1. Database Project
  1. Powershell Scripts
  2. Database compare: UpdateProject.scmp
  3. Assumes directories "Scripts" and their 2 subdirectories exist.
  4. DatabaseState.dacpac: A file that captures the current database state.
2. Service: A C# project that processes the scripts.
  1. SqlCmd.cs: Does the actual work.
  2. DatabaseMigrationScripts.resources: A resource file that contains the scripts that originated in the database project.

### Dependencies
1. sqlpackage.exe: Data tools must be installed.
2. Visual Studio: The powershell scripts will only work from VS package manager console (see the scripts for details).
3. Sql Server.  SqlCmd.cs (in Service) assumes Sql Server, but could probably be easily modified.
4. SqlCmd Utility.  This currently lives in SqlCmdResources.resx and is streamed out when needed.  It could live elesewhere, but this is easiest method.  If SqlCmd is installed (see SqlCmd.SqlCmdFoundOnPath), that copy will be used.

#### Configuration
1. Add a database project to your solution, then add all the components of this database project except the actual dbo folder.
2. Add all items in "DatabaseMigration" directory inside the console application to your service/executable that will be responsible for executing database scripts 
   (might be nuget package, but can't really stand on it's own without the database project).
3. Set the current state of your database:
  1. Using UpdateProject.scmp, update your database project: open it, configure it for your database, then update
  2. Build your database project.
  3. Copy DatabaseProject\bin\Debug\DatabaseProjectName.dacpac over DatabaseProject\DatabaseState.dacpac
4. Add everything in the "DatabaseMigration" directory to your Service.
  1. Set the build action property of DatabaseMigrationScripts.resources to Embedded Resource.
5. Search the solution for ":Configure:" and change where necessary.
6. Add the MigrationsJournal table (in this database project) to your database.
  1. Run UpdateProject.scmp to update your database state and generate your first script to run.
  2. Commit changes.
  3. This script (adding the journal table) will be the first script other instances execute.

#### Usage
1. Database Changes
  1. Make database changes using any method.
    1. Via application code.
    2. Via database tooling, e.g., SSMS.
    3. Via the database project scripts / objects.
  2. Update the database project using UpdateProject.scmp.
  3. Open package manager console, and run ./DatabaseProjectFolderName/GenerateMigrationScript.ps1
    1. Review script that should pop up.
  4. Run ./DatabaseProjectFolderName/CommitDatabaseScripts.ps1
  5. Commit changes to source.
2. Ad-Hoc Scripts
  1. Right click on AdHoc folder in the database project; add new database script.
    1. Or write the script elsewhere and manually copy it into that directory.
  2. Write your script using database context (intellisense on database objects, etc.).
  3. Don't execute the script; system assumes these are to execute via the Service.
  4. Run ./DatabaseProjectFolderName/CommitDatabaseScripts.ps1
  5. Run Service (you could do this step after the next or even after pushing changes, but if there was an issue with the script, other instances will experience that issue).
  6. Commit changes; script will now live in DatabaseMigrationScripts.resources.
3. Other instances of your Service that hit other database instances will execute scripts that bring that database instance up to the state represented by DatabaseState.dacpac
4. Viewing / Modifying scripts in the resource
  1. From the resource file (DatabaseMigrationScripts.resources)
    1. Open visual studio developer command prompt.
    2. resgen ServiceProject/DatabaseMigrationScripts.resources ServiceProject/DatabaseMigrationScripts.resx
    3. Open DatabaseMigrationScripts.resx in visual studio.
    4. From here, if necessary, you could remove scripts, save, and run resgen in reverse.
  2. From the build exe/dll of your Service
    1. Using telerik's JustDecompile or similar decompiler.
    2. The scripts will be seen at Root/Resources/RootNamespace.DatabaseMigration.DatabaseMigrationScripts.resources

##### Manual Test Plan
* Beginning state:
	* Database table 'Entity' only has Id, Name
	* Journal table doesn't exist in the database.
  * [database project]\DatabaseState.dacpac reflects database table state above (run UpdateProject.scmp to compare, build database project, copy the output over DatabaseState.dacpac
	* Ensure there is already a script file (even if it's empty) in the "Migrations" folder.
	* `truncate table Entity`
	* Refresh DatabaseMigrationScripts.resources with the content of Empty.resources
* Make backup of beginning dacpac state to compare against later.
	* "C:\temp\beginningState.dacpac"
* Add "NewColumn" (varchar 10) to table.
* Update the database project using UpdateProject.scmp
* Select the console project
* Run GenerateMigrationScript
	* Ensure it tells you to select the database project
* Select the database project and Run GenerateMigrationScript again
  * Ensure it warns that the journal table isn't present.  Run MigrationsJournal.sql to add the table.
* Run GenerateMigrationScript again
	* Ensure a script pops up for adding "NewColumn" to table Entity.
	* Ensure it's in the "Migrations" directory.
	* Ensure a custom comment is at the top informing you about the script generated.
* Run CommitDatabaseScripts
	* Ensure it tells you that there are multiple scripts in Migrations folder.
* Delete the extra junk sql file in the Migrations folder and Run CommitDatabaseScripts again.
	* Ensure it informs you that it's adding the journal table as the first script.
	* Ensure the Scripts/Migrations folder is empty.
	* Ensure DatabaseState.dacpac and the recent build file match.
	* Ensure beginningState.dacpac and new one don't match.
  * Ensure file DatabaseMigrationScripts.resources.bak (in same directory as the original) has been cleaned up.
  * Ensure a row in MigrationsJournal exists for the column creation script.
* Launch the executable; ensure it reports that it skipped the script (it added a row for you the developer in MigrationsJournal because you applied it).  Ensure other output is as expected (no errors).
* Create 2 scripts in the AdHoc directory by right clicking on the AdHoc folder in the database project.  They can both have as their command: `insert Entity values ('console test', 'console test')`
* Run CommitDatabaseScripts
  * Ensure console output reports that the new scripts were added to resource.
  * Ensure that the files you created and the project references to them have been cleaned up.
* Launch the executable.
  * Ensure it reports that it ran the 2 new scripts (#3 & 4).
  * Ensure Entity table has the rows added by the scripts, and that the journal contains 2 new entries recording script them.
* `drop table MigrationsJournal`
* `alter table Entity drop column NewColumn`
* Launch the executable.
  * Ensure it recreates the MigrationsJournal table, re-adds column NewColumn to Entity, and adds the 2 rows to Entity.