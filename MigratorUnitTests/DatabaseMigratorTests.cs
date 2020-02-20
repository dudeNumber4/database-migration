using FluentAssertions;
using Microsoft.Extensions.Configuration;
using DatabaseMigration;
using NSubstitute;
using System;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using Xunit;

namespace MigratorUnitTests
{

    public class DatabaseMigratorTests: IDisposable
    {

        private DatabaseMigrator _databaseMigrator;
        private IConfigurationRoot _config;
        private string _connectionString;

        public DatabaseMigratorTests()
        {
            var builder = new ConfigurationBuilder().SetBasePath(Directory.GetCurrentDirectory()).AddJsonFile("appsettings.json", optional: true, reloadOnChange: true);
            _config = builder.Build();  // ServiceStack's config thing seems to need to be part normal app startup; can't use in isolation.
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void PerformMigration(bool normalExecution)
        {
            _connectionString = _config.GetConnectionString("migration");
            TableExists(DatabaseMigratorTestScripts.JournalTableExistsScript).Should().BeTrue("Journal table expected to be present");
            ExecutePreScripts(normalExecution);
            SetMigratorSubstitute();

            _connectionString.Should().NotBeNullOrEmpty("Connection string should've been configured.");

            _databaseMigrator.PerformMigrations(_connectionString);
            // normalExecution executes the script, "abnormal" means the migrator discovered another service instance and didn't execute it.
            TableExists(DatabaseMigratorTestScripts.TableExistsScript).Should().Be(normalExecution, $"{nameof(_databaseMigrator)}, expected {(normalExecution ? "" : "not ")}to execute script.");
        }

        private void SetMigratorSubstitute()
        {
            _databaseMigrator = Substitute.For<DatabaseMigrator>(TestLogger.Instance());

            // Return a script that simply creates a table.  Give it a high number/key so as to not clash with any existing scripts.  Yes, the test has way too much knowledge of the innards.
            _databaseMigrator.GetResources().Returns(Enumerable.Repeat((DatabaseMigratorTestScripts.TestScriptName, DatabaseMigratorTestScripts.CreateTableScript), 1));
            _databaseMigrator.GetJournalTableCreationScript().Returns(string.Empty);
        }

        private bool TableExists(string tableExistsScript)
        {
            var result = false;
            SqlConnection con = null;
            try
            {
                using (con = new SqlConnection(_connectionString))
                {
                    using (var cmd = new SqlCommand(tableExistsScript, con))
                    {
                        con.Open();
                        using (var reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                result = reader.HasRows;
                            }
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
        }

    }

}
