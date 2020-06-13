using System;
using System.Collections;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using System.Reflection;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using DatabaseMigration.Utils;

namespace DatabaseMigration
{

    public interface IDatabaseMigrator
    {
        void PerformMigrations(string connectionString);
    }

    /// <summary>
    /// Manages migration script execution.
    /// <see cref="_scriptFolderPath"/> is the folder containing migration scripts.
    /// Using basic ADO to connect to database to keep simple; only one table and a few columns to interact with, and we are doing this in a context where DI isn't even up and running.
    /// </summary>
    [SuppressMessage("Globalization", "CA1305", Justification="I don't need provider here")]
    [SuppressMessage("Globalization", "CA1304", Justification="I don't need provider here")]
    [SuppressMessage("Security Category", "CA2100", Justification = "SQL Statements are generated within")]
    public class DatabaseMigrator : DirectDatabaseConnection, IDatabaseMigrator
    {

        /// <summary>
        /// Folder where scripts live.
        /// </summary>
        private string _scriptFolderPath = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), "RuntimeScripts");

        public DatabaseMigrator(IStartupLogger log)
            : base(log)
        {
        }

        /// <summary>
        /// Used to execute scripts from our known location
        /// </summary>
        /// <param name="connectionStr">Connection String.</param>
        public void PerformMigrations(string connectionStr)
        {
            ConfigureConnections(connectionStr);
            if (_connection.State == System.Data.ConnectionState.Open)
            {
                RunMigrations();
            }
            else
            {
                _log.LogInfo($"{nameof(PerformMigrations)}: Expected open connection.");
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
                    foreach ((int fileNumber, string filePath) script in GetScripts())
                    {
                        if (journalTable.TryAcquireLockFor((script.fileNumber, script.filePath)))
                        {
                            ExecuteScript(script.fileNumber, File.ReadAllText(script.filePath));
                            journalTable.RecordScriptInJournal(script, false);
                        }
                        else
                        {
                            _log.LogInfo($"Skipping script [{script.fileNumber}]; already executed or may be in process from another client.");
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

        private bool ExecuteScript(int scriptNumber, string script)
        {
            AssertOpenConnection();
            // We need ContinueOnError so we can continue after failed 'go' segments.  But the price we pay is no error message.
            int result = _serverConnection.ConnectionContext.ExecuteNonQuery(script, ExecutionTypes.ContinueOnError);
            if (result == 0)
            {
                _failedScripts.Add(scriptNumber, "Script execution failure");
                return false;
            }
            return true;
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
        private IEnumerable<(int fileNumber, string filePath)> GetOrderedScripts(bool skipFirstScript = true)
        {
            // The first script should always be the journal table creation script.  CommitDatabaseScripts.ps1 back in the database project should've enforced that.
            var result = GetNumericScripts().OrderBy(tuple => Convert.ToInt32(tuple.fileNumber)).ToList();
            if (skipFirstScript)
            {
                if (result.Count >= 2)
                {
                    return result.Skip(1);
                }
                else
                {
                    return Enumerable.Empty<(int fileNumber, string filePath)>();
                }
            }
            else
            {
                return result;
            }
        }

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
