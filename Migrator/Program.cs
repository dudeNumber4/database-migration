using DatabaseMigration;
using DatabaseMigration.Utils;
using System;
using System.Collections;
using System.Linq;
using System.Resources;

namespace Service
{

    class Program
    {

        static int Main(string[] args)
        {
            // :Configure: Put this somewhere in your service startup passing your connection string.
            using (var migrator = new DatabaseMigrator(new ConsoleStartupLogger()))
            {
                migrator.PerformMigrations(@"Server=.\SQLExpress;Trusted_Connection=Yes;Database=MigrationDatabase");
            }
            Console.WriteLine("Done with migrations.");
            Console.ReadLine();
            return 0;
        }

    }

}
