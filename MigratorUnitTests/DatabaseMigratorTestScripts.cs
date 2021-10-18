using DatabaseMigration;
using System;

namespace MigratorUnitTests
{

    public static class DatabaseMigratorTestScripts
    {
        private static JournalTableStructure _journalTableStructure = new JournalTableStructure();

        private const string CREATE_TABLE = "create table [{0}](id int)";
        private const string ALTER_TABLE = "alter table {0} add id2 int";
        private const string ALTER_FAILING = "Alter table {0} alter column x nvarchar(max)";
        private const string INSERT_INTO_TABLE = "insert {0} values(1, 1)";
        private const string CHECK_FOR_TABLE_ROWS = "select 1 from {0}";
        private const string DROP_TABLE = "drop table if exists {0}";
        private const string TABLE_EXISTS = "select 1 from sys.tables where name = '{0}'";
        private const string SIMULATE_OTHER_SERVICE = "insert [{0}]({1}, {2}, {3}) values ({4}, DATEADD(minute, -1, GETUTCDATE()), 0)";
        private const string DELETE_JOURNAL_RECORD = "delete from {0} where {1} = '{2}'";
        public const string DO_NOTHING_SCRIPT = "select 1";

        public static string CreateTableScript => string.Format(CREATE_TABLE, nameof(DatabaseMigratorTests));
        public static string AlterTableScript => string.Format(ALTER_TABLE, nameof(DatabaseMigratorTests));
        public static string AlterTableFailing => string.Format(ALTER_FAILING, nameof(DatabaseMigratorTests));
        public static string InsertIntoTableScript => string.Format(INSERT_INTO_TABLE, nameof(DatabaseMigratorTests));
        public static string CheckForTableRows => string.Format(CHECK_FOR_TABLE_ROWS, nameof(DatabaseMigratorTests));

        // cleanup scripts
        public static string DropTableScript => string.Format(DROP_TABLE, nameof(DatabaseMigratorTests));
        // script to check that test script ran
        public static string TableExistsScript => string.Format(TABLE_EXISTS, nameof(DatabaseMigratorTests));
        // script that simulates another service instance already started/running our script.
        public static string SimulateOtherServiceScript(int scriptNumber) => string.Format(SIMULATE_OTHER_SERVICE, _journalTableStructure.TableName, _journalTableStructure.NumberColumn, _journalTableStructure.BegunColumn, _journalTableStructure.CompletedColumn, scriptNumber);

        public static string InsertAppliedScript(int scriptNumber) => $"insert [{_journalTableStructure.TableName}]({_journalTableStructure.NumberColumn}, {_journalTableStructure.BegunColumn}, {_journalTableStructure.CompletedColumn}, {_journalTableStructure.ScriptColumn}, {_journalTableStructure.MessageColumn}) values ({scriptNumber}, DATEADD(minute, -1, GETUTCDATE()), 1, '{scriptNumber}.sql', 'Auto Created Test Data' )";
        public static string DeleteScript(int scriptNumber) => string.Format(DELETE_JOURNAL_RECORD, _journalTableStructure.TableName, _journalTableStructure.NumberColumn, scriptNumber);
        public static string DeleteJournalScript => string.Format(DROP_TABLE, _journalTableStructure.TableName);
    }

}
