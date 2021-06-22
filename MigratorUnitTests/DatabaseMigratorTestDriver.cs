using DatabaseMigration;
using DatabaseMigration.Utils;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using NSubstitute;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.IO;
using System.Linq;

namespace MigratorUnitTests
{
    
    internal class DatabaseMigratorTestDriver
    {

        readonly string _env = Environment.GetEnvironmentVariable("CI") ?? "DEV";
        private IConfigurationRoot _config;
        
        internal string ConnectionString { get; private set; }
        internal DatabaseMigrator MigratorSubstitute { get; private set; }

        internal DatabaseMigratorTestDriver()
        {
            var builder = new ConfigurationBuilder().SetBasePath(Directory.GetCurrentDirectory()).AddJsonFile("appsettings.json", optional: true, reloadOnChange: true);
            _config = builder.Build();
            ConnectionString = _config.GetConnectionString(_env);
            CleanupDatabase();
        }

        internal void EnsureMigrationTableCreated()
        {
            SetDatabaseMigratorSubstitute(Enumerable.Empty<(int, string)>(), Substitute.For<IStartupLogger>());
            try
            {
                MigratorSubstitute.PerformMigrations(ConnectionString, null);
            }
            finally
            {
                MigratorSubstitute.Dispose();
            }
        }

        internal void SetDatabaseMigratorSubstitute(IEnumerable<(int scriptNumber, string scriptPath)> scripts, IStartupLogger logger)
        {
            MigratorSubstitute = Substitute.For<DatabaseMigrator>(logger);

            var journalTableScript = GetJournalTableCreationScript();
            // Return a script that simply creates a table.  Give it a high number/key so as to not clash with any existing scripts.  Yes, the test has way too much knowledge of the innards.
            MigratorSubstitute.GetScripts().Returns(scripts);
            MigratorSubstitute.GetJournalTableCreationScript().Returns(journalTableScript);
        }

        internal void Dispose() => MigratorSubstitute?.Dispose();

        internal bool ScriptReturnsRows(string s)
        {
            var result = false;
            using var con = new SqlConnection(ConnectionString);
            using var cmd = new SqlCommand(s, con);
            con.Open();
            using var reader = cmd.ExecuteReader(System.Data.CommandBehavior.CloseConnection);
            if (reader.Read())
                result = reader.HasRows;
            return result;
        }

        internal void ExecutePreScripts(bool normalExecution, int scriptNumber)
        {
            if (!normalExecution)
            {
                // Non-happy path: another service has already started our script.
                ExecuteScript(DatabaseMigratorTestScripts.SimulateOtherServiceScript(scriptNumber));
            }
        }

        internal void ExecuteScript(string script)
        {
            using var con = new SqlConnection(ConnectionString);
            con.Open();
            using var cmd = new SqlCommand(script, con);
            cmd.ExecuteNonQuery();
        }

        private void CleanupDatabase()
        {
            ExecuteScript(DatabaseMigratorTestScripts.DropTableScript);
            ExecuteScript(DatabaseMigratorTestScripts.DeleteJournalScript);
        }

        /// <summary>
        /// 1.sql is journal table creation script.
        /// </summary>
        /// <returns></returns>
        private string GetJournalTableCreationScript()
        {
            // should exist in bin
            var scriptPath = $"./{nameof(DatabaseMigration)}/RuntimeScripts/1.sql";
            File.Exists(scriptPath).Should().BeTrue("Journal creation script should be present.");
            return File.ReadAllText(scriptPath);
        }


    }

}
