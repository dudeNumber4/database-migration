using FluentAssertions;
using Microsoft.Extensions.Configuration;
using DatabaseMigration;
using NSubstitute;
using System;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using Xunit;
using System.Collections.Generic;
using DatabaseMigration.Utils;

namespace MigratorUnitTests
{

    public class DatabaseMigratorTests: IDisposable
    {

        private DatabaseMigrator _databaseMigrator;
        private IConfigurationRoot _config;
        private string _connectionString;
        private string _tempScriptPath;
        readonly string _env = Environment.GetEnvironmentVariable("CI") ?? "DEV";

        public DatabaseMigratorTests()
        {
            var builder = new ConfigurationBuilder().SetBasePath(Directory.GetCurrentDirectory()).AddJsonFile("appsettings.json", optional: true, reloadOnChange: true);
            _config = builder.Build();
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void PerformMigration(bool normalExecution)
        {
            _connectionString = _config.GetConnectionString(_env);
            //TableExists(DatabaseMigratorTestScripts.JournalTableExistsScript).Should().BeTrue("Journal table expected to be present");
            ExecutePreScripts(normalExecution);
            SetMigratorSubstitute();

            _connectionString.Should().NotBeNullOrEmpty("Connection string should've been configured.");

            _databaseMigrator.PerformMigrations(_connectionString);
            // normalExecution executes the script, "abnormal" means the migrator discovered another service instance and didn't execute it.
            TableExists(DatabaseMigratorTestScripts.TableExistsScript).Should().Be(normalExecution, $"{nameof(_databaseMigrator)}, expected {(normalExecution ? "" : "not ")}to execute script.");
        }

        [Fact]
        public void PerformMigrationWhileSkippingAlreadyRunScripts()
        {
            _connectionString = _config.GetConnectionString(_env);
            _connectionString.Should().NotBeNullOrEmpty("Connection string should've been configured.");
            const int notYetRunScriptNumber = 4444;
            const int alreadyRanScriptNumber = 999911;

            // Use the migrator without any scripts to ensure migrations journal is created correctly.
            var emptyMigrator = GetDatabaseMigratorSubstitute(Enumerable.Empty<(int, string)>(), Substitute.For<IStartupLogger>());
            emptyMigrator.PerformMigrations(_connectionString);
            emptyMigrator.Dispose();

            ExecuteScript(DatabaseMigratorTestScripts.InsertAppliedScript(alreadyRanScriptNumber));
            ExecuteScript(DatabaseMigratorTestScripts.InsertAppliedScript(999922));
            ExecuteScript(DatabaseMigratorTestScripts.InsertAppliedScript(999933));

            var scripts = new List<(int scriptNumber, string scriptPath)>
            {
                CreateScript(alreadyRanScriptNumber, Path.GetTempFileName()),
                CreateScript(notYetRunScriptNumber, Path.GetTempFileName())
            };

            var infoLogMessages = new List<string>();

            try
            {
                var logger = Substitute.For<IStartupLogger>();
                logger.LogInfo(Arg.Do<string>(s => { infoLogMessages.Add(s); }));
                var databaseMigrator = GetDatabaseMigratorSubstitute(scripts, logger);
                databaseMigrator.PerformMigrations(_connectionString);
            }
            finally
            {
                ExecuteScript(DatabaseMigratorTestScripts.DeleteScript(alreadyRanScriptNumber));
                ExecuteScript(DatabaseMigratorTestScripts.DeleteScript(notYetRunScriptNumber));
                ExecuteScript(DatabaseMigratorTestScripts.DeleteScript(999922));
                ExecuteScript(DatabaseMigratorTestScripts.DeleteScript(999933));

                foreach (var valueTuple in scripts)
                {
                    File.Delete(valueTuple.scriptPath);
                }
            }

            Assert.Contains("Skipping script [999911]; already executed or may be in process from another client.", infoLogMessages);
            Assert.Contains("Script [4444] successfully ran.", infoLogMessages);
            Assert.Contains("Script [4444] successfully recorded in migration table.", infoLogMessages);
        }

        private void SetMigratorSubstitute()
        {
            _tempScriptPath = Path.GetTempFileName();
            _databaseMigrator = GetDatabaseMigratorSubstitute(
                new List<(int scriptNumber, string scriptPath)>
                {
                    CreateScript(
                        DatabaseMigratorTestScripts.TestScriptNumber,
                        _tempScriptPath,
                        DatabaseMigratorTestScripts.CreateTableScript)
                },
                TestLogger.Instance());
        }

        private DatabaseMigrator GetDatabaseMigratorSubstitute(IEnumerable<(int scriptNumber, string scriptPath)> scripts, IStartupLogger logger)
        {
            var migrator = Substitute.For<DatabaseMigrator>(logger);

            var journalTableScript = GetJournalTableCreationScript();
            // Return a script that simply creates a table.  Give it a high number/key so as to not clash with any existing scripts.  Yes, the test has way too much knowledge of the innards.
            migrator.GetScripts().Returns(scripts);
            migrator.GetJournalTableCreationScript().Returns(journalTableScript);
            return migrator;
        }

        private (int scriptNumber, string scriptPath) CreateScript(int scriptNumber, string scriptPath, string scriptContents = null)
        {
            File.WriteAllText(scriptPath, scriptContents ?? "");
            return (scriptNumber, scriptPath);
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

        private bool TableExists(string tableExistsScript)
        {
            var result = false;
            try
            {
                using (var con = new SqlConnection(_connectionString))
                {
                    using (var cmd = new SqlCommand(tableExistsScript, con))
                    {
                        con.Open();
                        using (var reader = cmd.ExecuteReader())
                        if (reader.Read())
                        {
                            result = reader.HasRows;
                        }
                    }
                }
            }
            finally
            {
                CleanupDatabase();
            }
            return result;
        }

        void ExecutePreScripts(bool normalExecution)
        {
            if (!normalExecution)
            {
                // Non-happy path: another service has already started our script.
                ExecuteScript(DatabaseMigratorTestScripts.SimulateOtherServiceScript);
            }
        }

        private void CleanupDatabase()
        {
            ExecuteScript(DatabaseMigratorTestScripts.DropTableScript);
            ExecuteScript(DatabaseMigratorTestScripts.DeleteJournalRecordScript);
        }

        private void ExecuteScript(string script)
        {
            using (var con = new SqlConnection(_connectionString))
            {
                con.Open();
                using (var cmd = new SqlCommand(script, con))
                {
                    cmd.ExecuteNonQuery();
                }
            }
        }

        public void Dispose()
        {
            _databaseMigrator?.Dispose();
            if (File.Exists(_tempScriptPath))
            {
                File.Delete(_tempScriptPath);
            }
        }

    }

}
