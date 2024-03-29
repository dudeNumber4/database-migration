using DatabaseMigration.Utils;
using Microsoft.SqlServer.Management.Smo;
using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Transactions;
using IsolationLevel = System.Data.IsolationLevel;

namespace DatabaseMigration
{

    /// <summary>
    /// Handles interaction with the journal table used by database migrations.
    /// </summary>
    public class JournalTable : DirectDatabaseConnection
    {

        private static string SQL_SERVER_TABLE_LOCK_HINT = "TABLOCKX";
        private readonly string _journalTableCreationScript;

        internal JournalTable(string connectionString, 
                              IStartupLogger log, 
                              string journalTableCreationScript,
                              Server serverConnection,
                              Dictionary<int, string> failedScripts)
            : base(log)
        {
            _connectionString = connectionString;
            _journalTableCreationScript = journalTableCreationScript;
            _failedScripts = failedScripts; // share failed scripts with DatabaseMigrator
            _serverConnection = serverConnection;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <remarks>_journalTableCreationScript is expected to be idempotent</remarks>
        internal bool EnsureTableExists()
        {
            var result = OpenConnection();
            if (result)
            {
                // We can't lock for this script since the locking mechanism is the table itself.  If another script tries to run this at about the same time and fails; so be it.
                // The creation script is idempotent.
                if (!string.IsNullOrEmpty(_journalTableCreationScript) && _journalTableCreationScript.Contains("create table", StringComparison.CurrentCultureIgnoreCase))
                {
                    try
                    {
                        _serverConnection.ConnectionContext.ExecuteNonQuery(_journalTableCreationScript);
                        result = true;
                    }
                    catch (SqlException ex)
                    {
                        _log.LogInfo($"Error executing table creation script (in case table not present) for table {_journalTableStructure.TableName}: {ex.Message}");
                    }
                }
            }
            return result;
        }

        /// <summary>
        /// Determine whether we can execute the current script by checking the migration journal table.
        /// If a lock is able to be acquired, a record is added to the journal table (unless an old one was already present).
        /// The lock is at the table level so no other records may be queried during the time we're adding our "begin script" record.
        /// The lock is actually released before the method finishes, so the name is a bit off, but follows a familiar naming pattern.
        /// Additionally, we're actually doing more than just "locking," we're potentially adding a record to the journal table.
        /// </summary>
        /// <param name="script"></param>
        /// <returns>True if the current script hasn't already been executed or is assumed to have failed in a prior run (<see cref="ScriptFailedInPriorRun"/>) or the journal table just doesn't exist</returns>
        /// <remarks>Assumption: we are running in a security context that has access to the database.</remarks>
        internal bool TryAcquireLockFor(ScriptDetails script)
        {
            var result = false;
            AssertOpenConnection();

            // We need to ensure that we check for the presence of the record and (if good) add the record in one transaction
            // otherwise another instance may check in the meantime and we both start the script.
            try
            {
                using SqlTransaction transaction = _connection.BeginTransaction(IsolationLevel.Serializable);
                // Explicit table lock hint.  Not often used, maybe I'm re-inventing a queue here, so be it.
                // The timeout here is 30 seconds.  I couldn't find any way to modify that (not related to connection timeout which is just timeout to initial connection to server).
                using var cmd = new SqlCommand($"select {_journalTableStructure.CompletedColumn}, {_journalTableStructure.BegunColumn} " +
                                               $"from {_journalTableStructure.TableName} ({SQL_SERVER_TABLE_LOCK_HINT}) where {_journalTableStructure.NumberColumn} = '{script.FileNumber}'", _connection, transaction);
                try
                {
                    using var reader = cmd.ExecuteReader(CommandBehavior.SingleResult);
                    if (!reader.HasRows || ScriptFailedInPriorRun(reader))
                    {
                        reader.Close(); // must close before write.
                        result = RecordScriptInJournal(script, true, transaction);
                        transaction.Commit();
                    }
                    else
                    {
                        reader.Close();
                        transaction.Rollback(); // should mean another instance already added a row, lock not acquired.
                    }
                }
                catch (SqlException ex)
                {
                    transaction.Rollback();
                    _log.LogInfo($"Error checking database to determine whether script has already run or obtaining a table lock: {ex.Message}");
                }
            }
            catch (TransactionAbortedException ex)
            {
                _log.LogInfo($"{nameof(TransactionAbortedException)} attempting to record a database migration script: {ex.Message}");
            }

            return result;
        }

        internal HashSet<int> GetCompletedScriptNumbers()
        {
            var numberColumnName = _journalTableStructure.NumberColumn;
            var scriptsRun = new HashSet<int>();

            using var cmd = new SqlCommand($"select {numberColumnName} from {_journalTableStructure.TableName} where {_journalTableStructure.CompletedColumn} = 1", _connection);
            try
            {
                using var reader = cmd.ExecuteReader(CommandBehavior.SingleResult);
                while (reader.Read())
                {
                    scriptsRun.Add(reader.GetInt32(numberColumnName));
                }
            }
            catch (SqlException ex)
            {
                _log.LogInfo($"Error checking database to get list of applied scripts: {ex.Message}");
            }

            return scriptsRun;
        }

        /// <summary>
        /// Add a record that a script is being (begin true) or has completed (begin false) executed.
        /// </summary>
        /// <param name="scriptDetails">number and script path</param>
        /// <param name="begin">Whether we're recording the begin or end of script execution.</param>
        /// <param name="transaction">A SQL transaction is passed upon the initial write of the record for asynchronously running clients.</param>
        /// <returns>Pass/fail</returns>
        internal bool RecordScriptInJournal(ScriptDetails scriptDetails, bool begin, SqlTransaction transaction = null)
        {
            Debug.Assert(_failedScripts != null, "HashSet of failed scripts is null.");
            var result = false;
            var scriptFileName = Path.GetFileName(scriptDetails.FilePath);

            if (begin)
                DeletePriorEntry(scriptDetails.FileNumber, transaction);

            var commandText = GetCommandText(scriptDetails, begin, scriptFileName);
            using var cmd = new SqlCommand(commandText, _connection, transaction);
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

            return result;
        }

        private string GetCommandText(ScriptDetails scriptDetails, bool begin, string scriptFileName)
        {
            var msg = string.Empty;
            char completed = '1';
            if (!begin)
            {
                if (_failedScripts.ContainsKey(scriptDetails.FileNumber))
                {
                    completed = '0';
                    msg = _failedScripts[scriptDetails.FileNumber].Replace("'", "''"); // value is err msg
                }
            }
            // Note: table has some defaults.
            return begin ?
                   $"insert {_journalTableStructure.TableName}({_journalTableStructure.NumberColumn}, {_journalTableStructure.BegunColumn}) values ('{scriptDetails.FileNumber}', GetUtcDate())"
                   : $"update {_journalTableStructure.TableName} set " +
                     $"{_journalTableStructure.CompletedColumn} = {completed}, " +
                     $"{_journalTableStructure.ScriptColumn} = '{scriptFileName}', " +
                     $"{_journalTableStructure.MessageColumn} = '{msg}', " +
                     $"{_journalTableStructure.SchemaChangedColumn} = {(scriptDetails.SchemaChanging ? '1' : '0')}" +
                     $" where {_journalTableStructure.NumberColumn} = '{scriptDetails.FileNumber}'";
        }

        /// <summary>
        /// Remove any prior record for this script (for a script that began but didn't finish).
        /// </summary>
        private void DeletePriorEntry(int scriptNumber, SqlTransaction transaction)
        {
            using var cmd = new SqlCommand($"delete from {_journalTableStructure.TableName} where {_journalTableStructure.NumberColumn} = '{scriptNumber}'", _connection, transaction);
            try
            {
                cmd.ExecuteNonQuery();
            }
            catch (SqlException)
            {
                ; // continue anyway
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
