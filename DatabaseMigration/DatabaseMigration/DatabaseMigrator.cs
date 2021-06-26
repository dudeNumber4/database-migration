using DatabaseMigration.Utils;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using System;
using System.Collections.Generic;
using Microsoft.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Reflection;

namespace DatabaseMigration
{

    public interface IDatabaseMigrator
    {
        MigrationResult PerformMigrations(string connectionString);
    }

    /// <summary>
    /// Manages migration script execution.
    /// <see cref="_scriptFolderPath"/> is the folder containing migration scripts.
    /// Using basic ADO to connect to database to keep simple; only one table and a few columns to interact with, and we are doing this in a context where DI isn't even up and running.
    /// </summary>
    public class DatabaseMigrator : DirectDatabaseConnection, IDatabaseMigrator
    {

        /// <summary>
        /// Folder where scripts live.
        /// </summary>
        private string _scriptFolderPath = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), nameof(DatabaseMigration), "RuntimeScripts");
        private readonly List<string> _schemaChangingScripts = new();

        public DatabaseMigrator(IStartupLogger log)
            : base(log) { }

        /// <summary>
        /// Used to execute scripts from our known location
        /// </summary>
        /// <param name="connectionStr">Connection String.</param>
        public MigrationResult PerformMigrations(string connectionStr)
        {
            _schemaChangingScripts.Clear();
            ConfigureConnections(connectionStr);
            if (_connection.State == System.Data.ConnectionState.Open)
            {
                RunMigrations();
                return new MigrationResult(_schemaChangingScripts);
            }
            else
            {
                _log.LogInfo($"{nameof(PerformMigrations)}: Expected open connection.");
                return null;
            }
        }

        /// <summary>
        /// Get file names from known folder.
        /// </summary>
        /// <returns>fileNumber, filePath</returns>
        public virtual IEnumerable<(int fileNumber, string filePath)> GetScripts()
        {
            foreach (var tuple in GetOrderedScripts())
            {
                yield return tuple;
            }
        }

        /// <summary>
        /// virtual for testing
        /// </summary>
        /// <returns>x</returns>
        public virtual string GetJournalTableCreationScript()
        {
            var firstScript = GetOrderedScripts(false).FirstOrDefault();
            return firstScript.filePath == null ? string.Empty : File.ReadAllText(firstScript.filePath);
        }

        private void RunMigrations()
        {
            using var journalTable = new JournalTable(_connectionString, _log, GetJournalTableCreationScript(), _serverConnection, _failedScripts);
            if (journalTable.EnsureTableExists())
            {
                try
                {
                    var completedScriptNumbers = journalTable.GetCompletedScriptNumbers();
                    foreach (var script in GetScripts())
                    {
                        if (completedScriptNumbers.Contains(script.fileNumber))
                        {
                            LogScriptAlreadyRan(script.fileNumber);
                            continue;
                        }

                        string scriptText = File.ReadAllText(script.filePath);
                        if (string.IsNullOrEmpty(scriptText))
                        {
                            _log.LogInfo($"Encountered empty script during {nameof(DatabaseMigrator.RunMigrations)}.  Script number: {script.fileNumber}");
                            continue;
                        }
                        var scriptDetails = new ScriptDetails(script.fileNumber, script.filePath, SchemaChangeDetection.SchemaChanged(_serverConnection, scriptText, _log));

                        if (journalTable.TryAcquireLockFor(scriptDetails))
                        {
                            if (ExecuteScript(script.fileNumber, scriptText))
                            {
                                _log.LogInfo($"Script [{script.fileNumber}] successfully ran.");
                            }
                            if (journalTable.RecordScriptInJournal(scriptDetails, false))
                            {
                                _log.LogInfo($"Script [{script.fileNumber}] successfully recorded in migration table.");
                                if (scriptDetails.SchemaChanging && (_schemaChangingScripts != null))
                                    _schemaChangingScripts.Add(scriptText);
                            }
                        }
                        else
                        {
                            LogScriptAlreadyRan(script.fileNumber);
                        }
                    }
                }
                catch (FormatException ex)
                {
                    _log.LogInfo($"Error encountered during processing of script: {ex.Message}");
                }
            }
            else
            {
                _log.LogInfo($"Unable to create/ensure presence of table {_journalTableStructure.TableName}");
            }
        }

        private void LogScriptAlreadyRan(int fileNumber)
        {
            _log.LogInfo($"Skipping script [{fileNumber}]; already executed or may be in process from another client.");
        }

        private bool ExecuteScript(int scriptNumber, string script)
        {
            AssertOpenConnection();
            // The overload with `ExecutionTypes.ContinueOnError` is straight-up wrong.  Doc says it should return rows affected, but it returns decreasing negative numbers... at times.
            void LogError() => _log.LogInfo($"Error executing script {scriptNumber}, see table {_journalTableStructure.TableName}");
            try
            {
                _serverConnection.ConnectionContext.ExecuteNonQuery(script);
                return true;
            }
            catch (ExecutionFailureException ex)
            {
                LogError();
                _failedScripts.Add(scriptNumber, $"{ex.Message} {ex.InnerException.Message}");
                return false;
            }
            catch (SqlException e)
            {
                LogError();
                _failedScripts.Add(scriptNumber, e.Message);
                return false;
            }
        }

        /// <summary>
        /// Not all file names will be represented as numbers.
        /// Correction; they should all be, but this code can remain.
        /// </summary>
        private IEnumerable<(int fileNumber, string filePath)> GetNumericScripts()
        {
            foreach (string file in Directory.EnumerateFiles(_scriptFolderPath))
            {
                var fileName = Path.GetFileNameWithoutExtension(file);
                if (int.TryParse(fileName, out var number))
                {
                    yield return (number, file);
                }
            }
        }

        /// <summary>
        /// Get file names in order.
        /// </summary>
        /// <returns>Materialized list because it must be ordered.</returns>
        private IEnumerable<(int fileNumber, string filePath)> GetOrderedScripts(bool skipFirstScript = true) =>
            // The first script should always be the journal table creation script.  CommitDatabaseScripts.ps1 back in the database project should've enforced that.
            GetNumericScripts().OrderBy(tuple => tuple.fileNumber).Skip(skipFirstScript ? 1 : 0);

        private void ConfigureConnections(string connectionStr)
        {
            _connectionString = connectionStr;
            if (OpenConnection())
            {
                _serverConnection = new Server(new ServerConnection(_connection));
            }
            else
            {
                _log.LogInfo($"{nameof(ConfigureConnections)}: unable to open database connection.");
            }
        }

    }

}
