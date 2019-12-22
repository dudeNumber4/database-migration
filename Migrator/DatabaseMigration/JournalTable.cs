using System;
using System.Linq;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Transactions;
using Migrator.DatabaseMigration.Utils;
using IsolationLevel = System.Data.IsolationLevel;

namespace Migrator.DatabaseMigration
{

    /// <summary>
    /// Handles interaction with the journal table used by database migrations.
    /// </summary>
    [SuppressMessage("Security Category", "CA2100", Justification = "SQL Statements are generated within")]
    public class JournalTable : DirectDatabaseConnection
    {

        private readonly string _journalTableCreationScript;

        internal JournalTable(string connectionString, IStartupLogger log, string journalTableCreationScript, Dictionary<string, string> failedScripts)
            : base(log)
        {
            _connectionString = connectionString;
            _journalTableCreationScript = journalTableCreationScript;
            _failedScripts = failedScripts; // share failed scripts with DatabaseMigrator
        }

        internal bool EnsureTableExists()
        {
            var result = OpenConnection();
            if (result)
            {
                result = TableExists();
                if (!result)
                {
                    if (!string.IsNullOrEmpty(_journalTableCreationScript) && _journalTableCreationScript.Contains("create table", StringComparison.CurrentCultureIgnoreCase))
                    {
                        // We can't lock for this script since the locking mechanism is the table itself.  If another script tries to run this at about the same time and fails; so be it.
                        using (var cmd = new SqlCommand(_journalTableCreationScript, _connection))
                        {
                            try
                            {
                                cmd.ExecuteNonQuery();
                                result = true;
                            }
                            catch (SqlException ex)
                            {
                                _log.LogInfo($"Error creating table {_journalTableStructure.TableName}: {ex.Message}");
                            }
                        }
                    }
                }
            }
            return result;
        }

        /// <summary>
        /// Determine whether we can execute the current script by checking the migration journal table.
        /// If a lock is able to be acquired, a record is added to the journal table (unless an old one was already present).
        /// The lock is at the table level so no other records my be queried during the time we're adding our "begin script" record.
        /// The lock is actually released before the method finishes, so the name is a bit off, but follows a familiar naming pattern.
        /// Additionally, we're actually doing more than just "locking," we're potentially adding a record to the journal table.
        /// </summary>
        /// <param name="resource">script resource: name and actual script</param>
        /// <returns>True if the current script hasn't already been executed or is assumed to have failed in a prior run (<see cref="ScriptFailedInPriorRun"/>) or the journal table just doesn't exist</returns>
        /// <remarks>Assumption: we are running in a security context that has access to the database.</remarks>
        internal bool TryAcquireLockFor((string name, string value) resource)
        {
            var result = false;
            AssertOpenConnection();

            // We need to ensure that we check for the presence of the record and (if good) add the record in one transaction
            // otherwise another instance may check in the meantime and we both start the script.
            try
            {
                using (SqlTransaction transaction = _connection.BeginTransaction(IsolationLevel.Serializable))
                {
                    // Explicit table lock hint.  Not often used, maybe I'm re-inventing a queue here, so be it.
                    // The timeout here is 30 seconds.  I couldn't find any way to modify that (not related to connection timeout which is just timeout to initial connection to server).
                    using (var cmd = new SqlCommand($"select * from {_journalTableStructure.TableName} (TABLOCKX) where {_journalTableStructure.NameColumn} = '{resource.name}'", _connection, transaction))
                    {
                        try
                        {
                            using (var reader = cmd.ExecuteReader(CommandBehavior.SingleResult))
                            {
                                if (!reader.HasRows || ScriptFailedInPriorRun(reader))
                                {
                                    reader.Close(); // must close before write.
                                    result = RecordScriptInJournal(resource, true, transaction);
                                }
                            }
                            transaction.Commit();
                        }
                        catch (SqlException ex)
                        {
                            transaction.Rollback();
                            _log.LogInfo($"Error checking database to determine whether script has already run or obtaining a table lock: {ex.Message}");
                        }
                    }
                }
            }
            catch (TransactionAbortedException ex)
            {
                _log.LogInfo($"{nameof(TransactionAbortedException)} attempting to record a database migration script: {ex.Message}");
            }

            return result;
        }

        /// <summary>
        /// Add a record that a script is being (begin true) or has completed (begin false) executed.
        /// </summary>
        /// <param name="resource">Resource content: name and actual script</param>
        /// <param name="begin">Whether we're recording the begin or end of script execution.</param>
        /// <param name="transaction">A SQL transaction is passed upon the initial write of the record for asynchronously running clients.</param>
        /// <returns>Pass/fail</returns>
        [SuppressMessage("Unk Category", "CA1307", Justification = "string replace won't ever care about culture")]
        internal bool RecordScriptInJournal((string name, string value) resource, bool begin, SqlTransaction transaction = null)
        {
            Debug.Assert(_failedScripts != null, "HashSet of failed scripts is null.");
            var result = false;
            var escapedScript = resource.value.Replace("'", "''");
            char completed = '1';
            var msg = string.Empty;

            if (begin)
            {
                DeletePriorEntry(resource.name, transaction);
            }
            else if (_failedScripts.ContainsKey(resource.name))
            {
                completed = '0';
                msg = _failedScripts[resource.name].Replace("'", "''"); // value is err msg
            }

            var commandText = begin ? 
                $"insert {_journalTableStructure.TableName}({_journalTableStructure.NameColumn}, {_journalTableStructure.BegunColumn}) values ('{resource.name}', GetUtcDate())" 
                : $"update {_journalTableStructure.TableName} set {_journalTableStructure.CompletedColumn} = {completed}, {_journalTableStructure.ScriptColumn} = '{escapedScript}', {_journalTableStructure.MessageColumn} = '{msg}' where {_journalTableStructure.NameColumn} = '{resource.name}'";
            using (var cmd = new SqlCommand(commandText, _connection, transaction))
            {
                try
                {
                    cmd.ExecuteNonQuery();
                    result = true;
                }
                catch (SqlException ex)
                {
                    result = false;
                    _log.LogInfo($"Error adding or updating migration journal record: {ex.Message}");
                }
            }

            return result;
        }

        private bool TableExists()
        {
            AssertOpenConnection();
            using (var cmd = new SqlCommand($"select top 1 * from {_journalTableStructure.TableName}", _connection))
            {
                try
                {
                    using (var reader = cmd.ExecuteReader(CommandBehavior.SingleResult))
                    {
                        if (reader.FieldCount != _journalTableStructure.Columns.Count)
                        {
                            EnsureTableColumnsPresent(reader);
                        }
                        return true;
                    }
                }
                catch (SqlException)
                {
                    return false;
                }
            }
        }
        
        private void EnsureTableColumnsPresent(SqlDataReader reader)
        {
            Debug.Assert(!reader.IsClosed, "Expected journal reader to be open");
            var columnSchema = reader.GetColumnSchema();
            var tableChangeScripts = new List<string>();
            _journalTableStructure.Columns.ForEach(journalColumn =>
            {
                if (!columnSchema.Any(c => c.ColumnName == journalColumn.name))
                {
                    // Assumption: any column we have to _add_ must be nullable.
                    tableChangeScripts.Add($"alter table {_journalTableStructure.TableName} add {journalColumn.name} {journalColumn.type} null");
                }
            });
            reader.Close();
            ExecuteTableChangeScripts(tableChangeScripts);
        }
        
        private void ExecuteTableChangeScripts(List<string> tableChangeScripts)
        {
            Debug.Assert(tableChangeScripts != null, "expected non null list");
            tableChangeScripts.ForEach(s =>
            {
                using (var cmd = new SqlCommand(s, _connection))
                {
                    cmd.ExecuteNonQuery(); // caller catches error
                }
            });
        }

        /// <summary>
        /// Remove any prior record for this script (for a script that began but didn't finish).
        /// </summary>
        /// <param name="scriptName">The file name portion (including extension) of the script (the key of the script in the resource file).  Case insensitive.</param>
        [SuppressMessage("StyleCop.CSharp.ReadabilityRules", "SA1106:CodeMustNotContainEmptyStatements", Justification = "I want to continue.")]
        private void DeletePriorEntry(string scriptName, SqlTransaction transaction)
        {
            using (var cmd = new SqlCommand($"delete from {_journalTableStructure.TableName} where {_journalTableStructure.NameColumn} = '{scriptName}'", _connection, transaction))
            {
                try
                {
                    cmd.ExecuteNonQuery();
                }
                catch (SqlException)
                {
                    ; // continue anyway
                }
            }
        }

        private bool ScriptFailedInPriorRun(SqlDataReader reader)
        {
            var result = false;
            reader.Read();
            if (bool.TryParse(reader[_journalTableStructure.CompletedColumn].ToString(), out var scriptCompleted))
            {
                if (!scriptCompleted)
                {
                    if (DateTime.TryParse(reader[_journalTableStructure.BegunColumn].ToString(), out var dateAttempted))
                    {
                        // Multiple clients can start up and begin executing scripts.
                        // We're going to assume that if a row exists that indicated a start to the script, but scriptCompleted is false and the date of the attempt is
                        // more than an hour ago, we have a failed execution.
                        // Otherwise, another client may be normally executing the script.
                        return (DateTime.Now - dateAttempted) > TimeSpan.FromHours(1);
                    }
                }
            }
            return result;
        }

    }

}
