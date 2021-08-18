using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DatabaseMigration
{
    /// <summary>
    /// Could include failed scripts; for now consumer only cares about SchemaChangingScripts.
    /// </summary>
    public record MigrationResult(List<(string scriptContents, int scriptNumber)> SchemaChangingScripts)
    {
    }
}
