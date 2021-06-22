using DatabaseMigration.Utils;
using Microsoft.SqlServer.Management.Smo;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Text;

namespace DatabaseMigration
{

    [SuppressMessage("Dispose", "CA1816", Justification = "Dispose WILL NOT WORK any other way")]
    [SuppressMessage("Disallow protected fields", "CA1051", Justification = "OO disallowed?")]
    public class DirectDatabaseConnection: IDisposable
    {

        protected readonly SqlConnection _connection = new SqlConnection();
        protected readonly IStartupLogger _log;
        // script name, error msg
        protected Dictionary<int, string> _failedScripts = new Dictionary<int, string>();
        protected string _connectionString;
        protected JournalTableStructure _journalTableStructure = new JournalTableStructure();
        protected Server _serverConnection;

        public DirectDatabaseConnection(IStartupLogger log) => _log = log;

        public void Dispose()
        {
            if (_connection.State == ConnectionState.Open)
            {
                _connection.Close();
            }
        }

        protected bool OpenConnection()
        {
            _connection.ConnectionString = _connectionString;
            try
            {
                _connection.Open();
                return true;
            }
            catch (Exception ex) when (ex is ArgumentException || ex is SqlException)
            {
                _log.LogInfo($"Connection failed; unable to apply migrations. {ex.Message}");
                return false;
            }
        }

        protected void AssertOpenConnection() => Debug.Assert(_connection.State == ConnectionState.Open, "Expected open connection");

    }

}
