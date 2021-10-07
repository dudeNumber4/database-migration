using DatabaseMigration.Utils;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DatabaseMigration.DatabaseMigration.SchemaChangeDetection
{

    internal static class SchemaChangeDetector
    {

        private static ImmutableList<string> _ddlStatements = ImmutableList.Create("alter", "create", "drop");

        // This option returns a resultset of metadata about the query.
        const string SQL_SERVER_SHOWPLAN = "set showplan_all on";
        const string SQL_SERVER_SHOWPLAN_OFF = "set showplan_all off";

        /// <summary>
        /// At time of writing, Smo has a bug with the utility command 'go'.  It blows up on some proper queries containing go.
        /// Not sure what the heck, but in DatabaseMigrator.cs we call server.ConnectionContext.ExecuteNonQuery and go works.  Here we call ExecuteReader and it doesn't.
        /// And this thread indicates it should never work.
        /// In any case, here we are splitting the scripts apart on go.
        /// https://github.com/microsoft/sqlmanagementobjects/issues/53
        /// </summary>
        internal static bool SchemaChanged(Server server, string sql, IStartupLogger log)
        {
            SplitOnGo splitter = new();
            foreach (var script in splitter.Split(sql))
                if (SchemaChanged_Inner(server, script, log))
                    return true;
            return false;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="server"></param>
        /// <param name="script">A script that doesn't contain the go keyword.</param>
        /// <param name="log"></param>
        /// <returns></returns>
        private static bool SchemaChanged_Inner(Server server, string script, IStartupLogger log)
        {
            var result = false;
            server.ConnectionContext.ExecuteNonQuery(SQL_SERVER_SHOWPLAN);

            try
            {
                using SqlDataReader readerResult = server.ConnectionContext.ExecuteReader(script);
                var schema = readerResult.GetSchemaTable();
                var statementTypeIndex = GetStatementTypeColIndex(schema);
                while (readerResult.Read())
                {
                    if (_ddlStatements.Any(s => readerResult[statementTypeIndex].ToString().ToLower().Contains(s)))
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
                server.ConnectionContext.ExecuteNonQuery(SQL_SERVER_SHOWPLAN_OFF);
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
