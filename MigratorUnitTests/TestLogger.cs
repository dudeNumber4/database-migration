using NSubstitute;
using System;
using System.Linq;
using System.Diagnostics;
using System.Text;
using DatabaseMigration.Utils;

namespace MigratorUnitTests
{

    /// <summary>
    /// Get a logger that simply prints to debug/console
    /// </summary>
    public static class TestLogger
    {

        public static IStartupLogger Instance()
        {
            void PrintDebug(string s) => Debug.Print(s);

            IStartupLogger result = Substitute.For<IStartupLogger>();
            result.When(l => l.LogException(Arg.Any<Exception>())).Do(ex =>
            {
                if (ex.Args().Any())
                {
                    PrintDebug(((Exception)ex.Args()[0]).Message);
                }
            });
            result.When(l => l.LogInfo(Arg.Any<string>())).Do(ex =>
            {
                if (ex.Args().Any() && (ex.Args()[0] != null))
                {
                    PrintDebug(ex.Args()[0].ToString());
                }
            });
            return result;
        }

    }

}
