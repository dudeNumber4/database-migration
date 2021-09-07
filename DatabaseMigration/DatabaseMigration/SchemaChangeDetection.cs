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
    /// Not sure what the heck, but in DatabaseMigrator.cs we call server.ConnectionContext.ExecuteNonQuery and go works.  Here we call ExecuteReader and it doesn't.
    /// And this thread indicates it should never work.
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
                log.LogInfo($"Error attempting to detect schema changing script: {ex.Message}");
                var inner = ex.InnerException;
                while (inner != null)
                {
                    log.LogInfo($"Schema changing error cont: {inner.Message}");
                    inner = inner.InnerException;
                }
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
