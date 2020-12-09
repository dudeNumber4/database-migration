::Database Migrator::

* This is the initial readme; the full readme will be delivered upon running the configuration powershell script.
* Before running the configuration script (ConfigureDatabaseMigrator.ps1 contained within DatabaseMigrationDeliverables.zip that should appear under your project), read the following requirements:
    * You just added this to the main/startup/service of your solution.  This service is where migrations will be executed from.
    * This is a solution running in visual studio.
    * This is in a git repo.
    * There is a database project (.sqlproj) in this solution.  If not, add one and then remove the database project from the overall build in solution properties.
        * If you already have one, it's a good idea to remove it from the overall build.
    * The name of the database project matches the name of your database.
* To run the configuration script:
    * Close this solution (probably not absolutely necessary, but projects will be updated and you will get VS complaining).
    * Extract contents of DatabaseMigrationDeliverables.zip (which should appear as an item under this project) into it's own directory under this project.
    * Run ./ConfigureDatabaseMigrator.ps1
* After running the configuration script, see DatabaseMigrator_README.MD