using System;
using System.Collections;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Resources;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using Migrator.DatabaseMigration.Utils;

namespace Migrator.DatabaseMigration
{

    public interface IDatabaseMigrator
    {
        void PerformMigrations(string connectionString);
    }

    /// <summary>
    /// Manages migration script execution.
    /// <see cref="SqlCmdResources"/><see cref="_resourceFilePath"/> is the resource containing migration scripts.
    /// Using basic ADO to connect to database to keep simple; only one table and a few columns to interact with, and we are doing this in a context where DI isn't even up and running.
    /// </summary>
    [SuppressMessage("Globalization", "CA1305", Justification="I don'need provider here")]
    [SuppressMessage("Globalization", "CA1304", Justification="I don'tneed provider here")]
    [SuppressMessage("Security Category", "CA2100", Justification = "SQL Statements are generated within")]
    public class DatabaseMigrator : DirectDatabaseConnection, IDatabaseMigrator
    {

        /// <summary>
        /// Resource file copied to output.
        /// This could be the more readable .resx file, but .Net core has made dealing with those a flat-out nightmare.  See ReadMe in database project for more.
        /// </summary>
        private string _resourceFilePath = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), nameof(DatabaseMigration), "DatabaseMigrationScripts.resources");
        private Server _serverConnection;

        public DatabaseMigrator(IStartupLogger log)
            : base(log)
        {
        }

        /// <summary>
        /// Used to execute scripts in our DatabaseScripts resource
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
        /// Get scripts from the script resource file.
        /// </summary>
        /// <returns>key name, resource value</returns>
        public virtual IEnumerable<(string name, string value)> GetResources()
        {
            IEnumerable<DictionaryEntry> GetResources()
            {
                foreach (var entry in GetOrderedScripts())
                {
                    yield return entry;
                }
            }

            foreach (DictionaryEntry item in GetResources())
            {
                yield return ((string)item.Key, (string)item.Value);
            }
        }

        /// <summary>
        /// virtual for testing
        /// </summary>
        /// <returns>x</returns>
        public virtual string GetJournalTableCreationScript()
        {
            var firstResource = GetOrderedScripts(false).FirstOrDefault();
            return firstResource.Key == null ? string.Empty : (string)firstResource.Value;
        }

        private void RunMigrations()
        {
            using (var journalTable = new JournalTable(_connectionString, _log, GetJournalTableCreationScript(), _failedScripts))
            {
                if (journalTable.EnsureTableExists())
                {
                    try
                    {
                        foreach ((string name, string value) resource in GetResources())
                        {
                            if (journalTable.TryAcquireLockFor(resource))
                            {
                                ExecuteScript(resource.name, resource.value);
                                journalTable.RecordScriptInJournal(resource, false);
                            }
                            else
                            {
                                _log.LogInfo($"Skipping script [{resource.name}]; already executed or may be in process from another client.");
                            }
                        }
                    }
                    catch (FormatException ex)
                    {
                        _log.LogInfo($"Error encountered during processing of script resources.  Resource file may be corrupted: {ex.Message}");
                    }
                }
                else
                {
                    _log.LogInfo($"Unable to create/ensure presence of table {_journalTableStructure.TableName}");
                }
            }
        }

        private bool ExecuteScript(string scriptName, string script)
        {
            AssertOpenConnection();
            void LogError() => _log.LogInfo($"Error executing script {scriptName}, see table {_journalTableStructure.TableName}");
            try
            {
                _serverConnection.ConnectionContext.ExecuteNonQuery(script);
                return true;
            }
            catch (ExecutionFailureException ex)
            {
                LogError();
                _failedScripts.Add(scriptName, $"{ex.Message} {ex.InnerException.Message}");
                return false;
            }
            catch (SqlException e)
            {
                LogError();
                _failedScripts.Add(scriptName, e.Message);
                return false;
            }
        }

        /// <summary>
        /// Not all keys will be represented as numbers.
        /// </summary>
        private IEnumerable<DictionaryEntry> GetNumericResources()
        {
            using (var reader = new ResourceReader(_resourceFilePath))
            {
                foreach (DictionaryEntry entry in reader)
                {
                    if (int.TryParse((string)entry.Key, out var number))
                    {
                        yield return entry;
                    }
                }
            }
        }

        /// <summary>
        /// Get resource keys in order.
        /// </summary>
        /// <returns>Materialized list because it must be ordered.</returns>
        private List<DictionaryEntry> GetOrderedScripts(bool skipFirstScript = true)
        {
            // The first script should always be the journal table creation script.  CommitDatabaseScripts.ps1 back in the database project should've enforced that.
            var result = GetNumericResources().OrderBy(de => Convert.ToInt32(de.Key)).ToList();
            if (skipFirstScript)
            {
                if (result.Count >= 2)
                {
                    return result.Skip(1).ToList();
                }
                else
                {
                    return new List<DictionaryEntry>();
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
