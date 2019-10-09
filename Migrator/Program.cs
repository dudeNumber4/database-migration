using Migrator.DatabaseMigration;
using System;
using System.Collections;
using System.Linq;
using System.Resources;

namespace Migrator
{

    class Program
    {

        static int Main(string[] args)
        {
            // :Configure: Put this somewhere in your service startup passing your connection string.
            using (var sqlcmd = new SqlCmd())
            {
                sqlcmd.PerformMigrations(@"Server=.\SQLExpress;Trusted_Connection=Yes;Database=MigrationDatabase");
            }
            Console.WriteLine("Done with migrations.");
            Console.ReadLine();
            return 0;
        }

    }

}
