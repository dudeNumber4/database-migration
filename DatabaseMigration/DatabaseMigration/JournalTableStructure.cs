using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Text;

namespace DatabaseMigration
{

    [SuppressMessage("Unk Category", "SA1502: Element should not be on a single line", Justification = "nope")]
    public class JournalTableStructure
    {
        public string TableName { get; } = "MigrationsJournal";
        public string NumberColumn { get { return Columns[1].name; } }
        public string BegunColumn { get { return Columns[2].name; } }
        public string CompletedColumn { get { return Columns[3].name; } }
        public string ScriptColumn { get { return Columns[4].name; } }
        public string MessageColumn { get { return Columns[5].name; } }

        /// <summary>
        /// These mirror object names back in MigrationsJournal.sql in the database project.
        /// </summary>
        public List<(string name, string type)> Columns { get; } = new List<(string name, string type)>
        {
            ("Id", "int"),
            ("ScriptNumber", "int"),
            ("AppliedAttempted", "DATETIME"),
            ("AppliedCompleted", "bit"),
            ("ScriptApplied", "VARCHAR(MAX)"),
            ("Msg", "VARCHAR(MAX)"),
        };
    }

}
