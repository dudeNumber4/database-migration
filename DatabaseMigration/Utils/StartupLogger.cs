using System;
using System.Collections.Generic;
using System.Text;

namespace DatabaseMigration.Utils
{

    public interface IStartupLogger
    {
        void LogException(Exception exception);
        void LogInfo(string s);
    }

    /// <summary>
    /// :Configure: plug in your logger / implement this interface.  It's passed into <see cref="DatabaseMigrator"/>
    /// </summary>
    public class ConsoleStartupLogger : IStartupLogger
    {
        public void LogException(Exception exception)
        {
            Console.WriteLine($"Error: {exception?.Message}");
        }

        public void LogInfo(string s)
        {
            Console.WriteLine(s);
        }
    }

}
