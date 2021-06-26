using DatabaseMigration;
using DatabaseMigration.Utils;
using FluentAssertions;
using NSubstitute;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Xunit;

namespace MigratorUnitTests
{

    public class DatabaseMigratorTests: IDisposable
    {

        private readonly DatabaseMigratorTestDriver _driver = new();
        private readonly List<string> _tempFilePaths = new List<string>();

        /// <summary>
        /// Unfortunately, these both have to run together, in sequence.
        /// </summary>
        /// <param name="normalExecution"></param>
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void PerformMigration(bool normalExecution)
        {
            const int SCRIPT_NUMBER = 2;
            _driver.EnsureMigrationTableCreated();
            _driver.SetDatabaseMigratorSubstitute(
                // create table script
                Enumerable.Repeat(CreateScript(SCRIPT_NUMBER, DatabaseMigratorTestScripts.CreateTableScript), 1),
                Substitute.For<IStartupLogger>());
            _driver.ExecutePreScripts(normalExecution, SCRIPT_NUMBER);

            _driver.MigratorSubstitute.PerformMigrations(_driver.ConnectionString);
            // normalExecution executes the script, "abnormal" means the migrator discovered another service instance and didn't execute it.
            // Normal execution means that a table creation script ran; check for that now.
            _driver.ScriptReturnsRows(DatabaseMigratorTestScripts.TableExistsScript).Should().Be(normalExecution, $"{nameof(DatabaseMigrator)}, expected {(normalExecution ? "" : "not ")}to execute script.");
        }

        [Fact]
        public void PerformMigrationWhileSkippingAlreadyRunScripts()
        {
            _driver.EnsureMigrationTableCreated();

            const int notYetRunScriptNumber = 4444;
            const int alreadyRanScriptNumber = 999911;

            _driver.ExecuteScript(DatabaseMigratorTestScripts.InsertAppliedScript(alreadyRanScriptNumber));
            _driver.ExecuteScript(DatabaseMigratorTestScripts.InsertAppliedScript(999922));
            _driver.ExecuteScript(DatabaseMigratorTestScripts.InsertAppliedScript(999933));

            var scripts = new List<(int scriptNumber, string scriptPath)>
            {
                CreateScript(alreadyRanScriptNumber, DatabaseMigratorTestScripts.DO_NOTHING_SCRIPT),
                CreateScript(notYetRunScriptNumber, DatabaseMigratorTestScripts.DO_NOTHING_SCRIPT)
            };

            var infoLogMessages = new List<string>();

            try
            {
                var logger = Substitute.For<IStartupLogger>();
                logger.LogInfo(Arg.Do<string>(s => { infoLogMessages.Add(s); }));
                _driver.SetDatabaseMigratorSubstitute(scripts, logger);
                _driver.MigratorSubstitute.PerformMigrations(_driver.ConnectionString);
            }
            finally
            {
                _driver.ExecuteScript(DatabaseMigratorTestScripts.DeleteScript(alreadyRanScriptNumber));
                _driver.ExecuteScript(DatabaseMigratorTestScripts.DeleteScript(notYetRunScriptNumber));
                _driver.ExecuteScript(DatabaseMigratorTestScripts.DeleteScript(999922));
                _driver.ExecuteScript(DatabaseMigratorTestScripts.DeleteScript(999933));
            }

            Assert.Contains($"Skipping script [{alreadyRanScriptNumber}]; already executed or may be in process from another client.", infoLogMessages);
            Assert.Contains($"Script [{notYetRunScriptNumber}] successfully ran.", infoLogMessages);
            Assert.Contains($"Script [{notYetRunScriptNumber}] successfully recorded in migration table.", infoLogMessages);
        }

        [Fact]
        public void DetectSchemaChangeScript()
        {
            var scripts = new List<(int scriptNumber, string scriptPath)>
            {
                CreateScript(2, DatabaseMigratorTestScripts.CreateTableScript),
                CreateScript(3, DatabaseMigratorTestScripts.InsertIntoTableScript),
                CreateScript(4, DatabaseMigratorTestScripts.AlterTableScript)
            };
            _driver.SetDatabaseMigratorSubstitute(scripts, Substitute.For<IStartupLogger>());
            var schemaChangingScripts = _driver.MigratorSubstitute.PerformMigrations(_driver.ConnectionString);
            schemaChangingScripts.SchemaChangingScripts.Should().NotBeNull();
            schemaChangingScripts.SchemaChangingScripts.Should().HaveCount(2);
            schemaChangingScripts.SchemaChangingScripts[0].Should().BeEquivalentTo(DatabaseMigratorTestScripts.CreateTableScript);
            schemaChangingScripts.SchemaChangingScripts[1].Should().BeEquivalentTo(DatabaseMigratorTestScripts.AlterTableScript);
            // Ensure the insert between the 2 schema checks ran
            _driver.ScriptReturnsRows(DatabaseMigratorTestScripts.CheckForTableRows);
        }

        public void Dispose()
        {
            _tempFilePaths.ForEach(p => File.Delete(p));
            _driver.Dispose();
        }

        private (int scriptNumber, string scriptPath) CreateScript(int scriptNumber, string scriptContents)
        {
            var tempScriptPath = Path.GetTempFileName();
            _tempFilePaths.Add(tempScriptPath);
            File.WriteAllText(tempScriptPath, scriptContents ?? "");
            return (scriptNumber, tempScriptPath);
        }

    }

}
