using DatabaseMigration;
using DatabaseMigration.Utils;
using System;
using System.Collections.Generic;

namespace Service
{

    class Program
    {

        static int Main(string[] args)
        {
            // :Configure: Put this somewhere in your service startup passing your connection string.
            using var migrator = new DatabaseMigrator(new ConsoleStartupLogger());
            var schemaChangingScripts = new List<string>();
            migrator.PerformMigrations(@"Server=.\SQLExpress;Trusted_Connection=Yes;Database=MigrationDatabase", schemaChangingScripts);
            schemaChangingScripts.ForEach(s => Console.WriteLine($"Encountered schema changing script: {Environment.NewLine}{s}"));
            Console.WriteLine("Done with migrations.");
            Console.ReadLine();
            return 0;
        }

    }

}
