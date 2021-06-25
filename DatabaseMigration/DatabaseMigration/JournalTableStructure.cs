using System;
using System.Collections.Generic;
using System.Text;

namespace DatabaseMigration
{

    public class JournalTableStructure
    {
        public string TableName => "MigrationsJournal";
        public string NumberColumn => Columns[1].name;
        public string BegunColumn => Columns[2].name;
        public string CompletedColumn => Columns[3].name;
        public string ScriptColumn => Columns[4].name;
        public string MessageColumn => Columns[5].name;
        public string SchemaChangedColumn => Columns[6].name;

        /// <summary>
        /// These mirror object names back in MigrationsJournal.sql in the database project.
        /// Note also that 1.sql in runtime scripts contains the same table DDL.
        /// </summary>
        public List<(string name, string type)> Columns { get; } = new List<(string name, string type)>
        {
            ("Id", "int"),
            ("ScriptNumber", "int"),
            ("AppliedAttempted", "DATETIME"),
            ("AppliedCompleted", "bit"),
            ("ScriptApplied", "VARCHAR(MAX)"),
            ("Msg", "VARCHAR(MAX)"),
            ("SchemaChanged", "bit"),
        };
    }

}
