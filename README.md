# Database Change Management System
A 2-part (mostly) system for automating the propogation of database changes throughout all dev/stage/prod instances.

## Components
1. Database Project
  1. Powershell Scripts
  2. Database compare: UpdateProject.scmp
  3. Assumes folders "Scripts" and their 2 children exist.
  4. DatabaseState.dacpac: A file that captures the current database state.
2. Service: A C# project that processes the scripts.
  1. SqlCmd.cs: Does the actual work.
  2. DatabaseMigrationScripts.resources: A resource file that contains the scripts that originated back in the database project.

### Dependencies
1. sqlpackage.exe: Data tools must be installed.
2. Visual Studio: The powershell scripts will only work from VS package manager console (see the scripts for details).
3. Sql Server.  SqlCmd.cs (in Service) assumes Sql Server, but could probably be easily modified.
4. Sqlcmd.exe.  This currently lives in SqlCmdResources.resx and is streamed out when needed.  It could live elesewhere, but this is easiest method.

#### Configuration
1. Add a database project to your solution, then add all the components of this database project except the actual dbo folder.
2. Add all items in "DatabaseMigration" directory inside the console application to your service/executable that will be responsible for executing database scripts 
   (might be nuget package, but can't really stand on it's own without the database project).
3. Set the current state of your database:
  1. Using UpdateProject.scmp, update your database project: open it, configure it for your database, then update
  2. Build your database project.
  3. Copy DatabaseProject\bin\Debug\MigrationDatabase.dacpac over DatabaseProject\DatabaseState.dacpac
4. Add everything in the "DatabaseMigration" directory to your Service.
  1. Set the build action property of DatabaseMigrationScripts.resources to Embedded Resource.
5. Search the solution for ":Configure:"
6. Add the MigrationsJournal table (in this database project) to your service's database.  Service will assume that table to be present.
  1. This table will need to be added manually to other instances (the system)

#### Usage
1. Database Changes
  1. Make database changes using any method.
    1. Via application code.
    2. Via database tooling, e.g., SSMS.
    3. Via the database project scripts / objects.
  2. Update the database project using UpdateProject.scmp.
  3. Open package manager console, and run ./MigrationDatabase/GenerateMigrationScript.ps1
    1. Review script that should pop up.
  4. Run ./MigrationDatabase/CommitDatabaseScripts.ps1
  5. Commit changes to source.
2. Ad-Hoc Scripts
  1. Right click on AdHoc folder in the database project; add new database script.
    1. Or write the script elsewhere and manually copy it into that directory.
  2. Write your script using database context (intellisense on database objects, etc.).
  3. Don't execute the script; system assumes these are to execute via the Service.
  4. Run ./MigrationDatabase/CommitDatabaseScripts.ps1
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

##### Manual Test
* Beginning state:
	* Database table Entity only has Id, Name
	* No entries in Journal table (see AddTableEntry).
	* [database project]\DatabaseState.dacpac reflects database table state above
	* Ensure there is already a script file (even if it's empty) in the "Migrations" folder.
	* Truncate table Entity
	* Refresh DatabaseMigrationScripts.resources with the content of Empty.resources
* Make backup of beginning dacpac state to compare against later.
	* "C:\temp\beginningState.dacpac"
* Add "NewColumn" to table.
* Update the database project using UpdateProject.scmp
* Select the console project
* Run GenerateMigrationScript
	* Ensure it tells you to select the database project
* Select the database project and Run GenerateMigrationScript again
	* Ensure the script pops up.
	* Ensure it's in the "Migrations" directory.
	* Ensure the custom comment is at the top.
* Run CommitDatabaseScripts
	* Ensure it tells you that there are multiple scripts in Migrations folder.
* Delete the extra junk sql file and Run CommitDatabaseScripts again
	* Ensure the console output reads OK.
	* Ensure the Scripts/Migrations folder is empty.
	* Ensure the journal table has the new entry.
	* Ensure DatabaseState.dacpac and the recent build file match.
	* Ensure beginningState.dacpac and new one don't match.
* Launch the executable; ensure it reports that it skipped the new script.
* Remove NewColumn from entity table and delete the row from the journal table that says it's been applied.
* Launch the executable; ensure it reports that it ran the script, that the table has the column back, and that the journal table entry is back.
* Create a script in the AdHoc directory: insert Entity values ('console test', 'hello from console test')
* Launch the executable; ensure it reports that it ran the new script.
	* Ensure Entity has that row and that the journal contains the new entry.

