using Migrator.Utils;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Text;
using System.Transactions;
using IsolationLevel = System.Data.IsolationLevel;

namespace Migrator.DatabaseMigration
{

    internal class JournalTable
    {

        /// <summary>
        /// These mirror object names back in MigrationsJournal.sql in the database project.
        /// </summary>
        internal const string TABLE_NAME = "MigrationsJournal";
        internal const string SCRIPT_NAME_COLUMN = "ScriptName";
        internal const string SCRIPT_BEGUN_COLUMN = "AppliedAttempted";
        internal const string SCRIPT_COMPLETED_COLUMN = "AppliedCompleted";

        private readonly HashSet<string> _failedScripts;
        private readonly SqlConnection _connection;
        private readonly string _journalTableCreationScript;

        internal JournalTable(SqlConnection connection, HashSet<string> failedScripts, string journalTableCreationScript)
        {
            _connection = connection;
            _failedScripts = failedScripts;
            _journalTableCreationScript = journalTableCreationScript;
        }

        internal bool EnsureJournalTableExists()
        {
            AssertOpenConnection();
            var result = JournalTableExists();
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
                            // :Configure: log
                            Console.WriteLine($"Error creating table {TABLE_NAME}: {ex.Message}");
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
        /// <param name="scriptName">The key to the script in the script resource.</param>
        /// <returns>True if the current script hasn't already been executed or is assumed to have failed in a prior run (<see cref="ScriptFailedInPriorRun"/>) or the journal table just doesn't exist</returns>
        /// <remarks>Assumption: we are running in a security context that has access to the database.</remarks>
        internal bool TryAcquireLockFor(string scriptName)
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
                    using (var cmd = new SqlCommand($"select * from {TABLE_NAME} (TABLOCKX) where {SCRIPT_NAME_COLUMN} = '{scriptName}'", _connection, transaction))
                    {
                        try
                        {
                            using (var reader = cmd.ExecuteReader(CommandBehavior.SingleResult))
                            {
                                if (!reader.HasRows || ScriptFailedInPriorRun(reader))
                                {
                                    reader.Close(); // must close before write.
                                    result = RecordScriptInJournal(scriptName, true, transaction);
                                }
                            }
                            transaction.Commit();
                        }
                        catch (SqlException ex)
                        {
                            transaction.Rollback();
                            // :Configure: log
                            Console.WriteLine($"Error checking database to determine whether script has already run or obtaining a table lock: {ex.Message}");
                        }
                    }
                }
            }
            catch (TransactionAbortedException ex)
            {
                // :Configure: log
                Console.WriteLine($"{nameof(TransactionAbortedException)} attempting to record a database migration script: {ex.Message}");
            }

            return result;
        }

        /// <summary>
        /// Add a record that a script is being (begin true) or has completed (begin false) executed.
        /// </summary>
        /// <param name="scriptName">The file name portion (including extension) of the script (the key of the script in the resource file).  Case insensitive.</param>
        /// <param name="begin">Whether we're recording the begin or end of script execution.</param>
        /// <param name="transaction">A SQL transaction is passed upon the initial write of the record for asynchronously running clients.</param>
        /// <returns>Pass/fail</returns>
        internal bool RecordScriptInJournal(string scriptName, bool begin, SqlTransaction transaction = null)
        {
            Debug.Assert(_failedScripts != null, "HashSet of failed scripts is null.");
            var result = false;

            if (begin)
            {
                DeletePriorEntry(scriptName, transaction);
            }
            else if (_failedScripts.Contains(scriptName))
            {
                return result; // Don't update as passed because we captured failure.
            }

            var commandText = begin ? $"insert {TABLE_NAME}({SCRIPT_NAME_COLUMN}, {SCRIPT_BEGUN_COLUMN}) values ('{scriptName}', GetDate())" : $"update {TABLE_NAME} set {SCRIPT_COMPLETED_COLUMN} = 1 where {SCRIPT_NAME_COLUMN} = '{scriptName}'";
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
                    // :Configure: log
                    Console.WriteLine($"Error adding or updating migration journal record: {ex.Message}");
                }
            }

            return result;
        }

        private bool JournalTableExists()
        {
            AssertOpenConnection();
            using (var cmd = new SqlCommand($"select 1 from sys.tables where name = '{TABLE_NAME}'", _connection))
            {
                try
                {
                    using (var reader = cmd.ExecuteReader(CommandBehavior.SingleResult))
                    {
                        return reader.HasRows;
                    }
                }
                catch (SqlException)
                {
                    return false;
                }
            }
        }

        /// <summary>
        /// Remove any prior record for this script (for a script that began but didn't finish).
        /// </summary>
        /// <param name="scriptName">The file name portion (including extension) of the script (the key of the script in the resource file).  Case insensitive.</param>
        private void DeletePriorEntry(string scriptName, SqlTransaction transaction)
        {
            using (var cmd = new SqlCommand($"delete from {TABLE_NAME} where {SCRIPT_NAME_COLUMN} = '{scriptName}'", _connection, transaction))
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

        private static bool ScriptFailedInPriorRun(SqlDataReader reader)
        {
            var result = false;
            reader.Read();
            if (bool.TryParse(reader[SCRIPT_COMPLETED_COLUMN].ToString(), out var scriptCompleted))
            {
                if (!scriptCompleted)
                {
                    if (DateTime.TryParse(reader[SCRIPT_BEGUN_COLUMN].ToString(), out var dateAttempted))
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

        private void AssertOpenConnection() => Debug.Assert(_connection.State == ConnectionState.Open, "Expected open connection");


    }

}
