using Migrator.DatabaseMigration;
using System;
using System.Collections.Generic;
using System.Text;

namespace MigratorUnitTests
{

    public static class DatabaseMigratorTestScripts
    {
        private static JournalTableStructure _journalTableStructure = new JournalTableStructure();

        private const string CREATE_TABLE = "create table [{0}](id int)";
        private const string DROP_TABLE = "if exists(select 1 from sys.tables where name = '{0}') drop table [{0}]";
        private const string TABLE_EXISTS = "select 1 from sys.tables where name = '{0}'";
        private const string DELETE_JOURNAL_RECORD = "delete from {0} where {1} = '{2}'";
        private const string SIMULATE_OTHER_SERVICE = "insert [{0}]({1}, {2}, {3}) values ({4}, DATEADD(minute, -1, GETUTCDATE()), 0)";

        // The script we'll actually execute
        public static string CreateTableScript => string.Format(CREATE_TABLE, nameof(DatabaseMigratorTests));
        // cleanup scripts
        public static string DropTableScript => string.Format(DROP_TABLE, nameof(DatabaseMigratorTests));
        public static string DeleteJournalRecordScript => string.Format(DELETE_JOURNAL_RECORD, _journalTableStructure.TableName, _journalTableStructure.NameColumn, TestScriptName);
        // script to check that test script ran
        public static string TableExistsScript => string.Format(TABLE_EXISTS, nameof(DatabaseMigratorTests));
        // script that simulates another service instance already started/running our script.
        public static string SimulateOtherServiceScript => string.Format(SIMULATE_OTHER_SERVICE, _journalTableStructure.TableName, _journalTableStructure.NameColumn, _journalTableStructure.BegunColumn, _journalTableStructure.CompletedColumn, TestScriptName);

        public static string TestScriptName => Int32.MaxValue.ToString();
        public static string JournalTableExistsScript => string.Format(TABLE_EXISTS, _journalTableStructure.TableName);
    }

}