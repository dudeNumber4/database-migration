using System;
using System.Linq;

namespace DatabaseMigration
{
    internal record ScriptDetails(int FileNumber, string FilePath, bool SchemaChanging)
    {
    }
}
