using DatabaseMigration;
using DatabaseMigration.Utils;
using System;

namespace Service
{

    class Program
    {

        static int Main(string[] args)
        {
            // :Configure: Put this somewhere in your service startup passing your connection string.
            using var migrator = new DatabaseMigrator(new ConsoleStartupLogger());
            migrator.PerformMigrations(@"Server=.\SQLExpress;Trusted_Connection=Yes;Database=MigrationDatabase");
            Console.WriteLine("Done with migrations.");
            Console.ReadLine();
            return 0;
        }

    }

}
