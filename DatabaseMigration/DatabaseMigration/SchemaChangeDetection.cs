using DatabaseMigration.Utils;
using Microsoft.SqlServer.Management.Smo;
using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Linq;

namespace DatabaseMigration
{

    /// <summary>
    /// At time of writing, Smo has a bug with the utility command 'go'.  It blows up on some proper queries containing go.
    /// In that case, it will always return false.
    /// https://github.com/microsoft/sqlmanagementobjects/issues/53
    /// </summary>
    internal static class SchemaChangeDetection
    {

        // This option returns a resultset of metadata about the query.
        const string SQL_SERVER_SHOWPLAN = "set showplan_all on";
        
        internal static bool SchemaChanged(Server server, string sql, IStartupLogger log)
        {
            var result = false;
            server.ConnectionContext.ExecuteNonQuery(SQL_SERVER_SHOWPLAN);

            try
            {
                using SqlDataReader readerResult = server.ConnectionContext.ExecuteReader(sql);
                var schema = readerResult.GetSchemaTable();
                var statementTypeIndex = GetStatementTypeColIndex(schema);
                var ddlStatements = new List<string> { "alter", "create", "drop" };
                while (readerResult.Read())
                {
                    if (ddlStatements.Any(s => readerResult[statementTypeIndex].ToString().ToLower().Contains(s)))
                    {
                        result = true;
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                log.LogInfo("Following error attempting to detect schema changing script.");
                log.LogException(ex);
            }
            finally
            {
                server.ConnectionContext.ExecuteNonQuery("set showplan_all off");
            }
            return result;
        }

        static int GetStatementTypeColIndex(DataTable schemaTable)
        {
            for (int i = 0; i < schemaTable.Rows.Count; i++)
            {
                var row = schemaTable.Rows[i];
                if (row[0].ToString() == "Type")
                    return i;
            }
            return -1;
        }

    }

}
