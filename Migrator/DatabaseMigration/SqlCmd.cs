using Migrator.Utils;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Resources;
using System.Text;

namespace Migrator.DatabaseMigration
{

    /// <summary>
    /// Manages migration script execution.
    /// <see cref="SqlCmdResources"/> contains sqlcmd.exe and it's 2 dependencies.  They could be moved to a better place; this works for now.  I got them from an SSMS 2018 install.
    /// <see cref="SCRIPT_RESOURCE_FILE_NAME"/> is the resource containing migration scripts.
    /// Using basic ADO to connect to database to keep simple; only one table and a few columns to interact with, and we are doing this in a context where DI isn't even up and running.
    /// </summary>
    public sealed class SqlCmd : IDisposable
    {

        /// <summary>
        /// Embedded resource file
        /// </summary>
        private const string SCRIPT_RESOURCE_FILE_NAME = "DatabaseMigrationScripts.resources";

        private readonly HashSet<string> _failedScripts = new HashSet<string>();
        private readonly SqlConnection _connection = new SqlConnection();

        // :Configure: Your service namespace names here.  This is how the embedded resource will be named.
        private string _fullyQualifiedScriptResourceName = $"{nameof(Migrator)}.{nameof(DatabaseMigration)}.{SCRIPT_RESOURCE_FILE_NAME}";
        private string _sqlCmdDir;
        private string _scriptResourceFilePath;
        private string _server;
        private string _connectionString;

        public void Dispose()
        {
            if (Directory.Exists(_sqlCmdDir))
            {
                DirectoryUtils.FlushDirectory(_sqlCmdDir, true);
            }
            if (_connection.State == ConnectionState.Open)
            {
                _connection.Close();
            }
        }

        /// <summary>
        /// Used to execute scripts in our DatabaseScripts resource
        /// </summary>
        /// <param name="connectionStr">Connection String.</param>
        public void RunMigrations(string connectionStr)
        {
            SetConnectionStrings(connectionStr);
            CreateSqlCmdDir();
            var sqlCmdPath = Path.Combine(_sqlCmdDir, $"{nameof(SqlCmd)}.exe");
            if (ExtractScriptResourceFile())
            {
                if (OpenConnection())
                {
                    var journalTable = new JournalTable(_connection, _failedScripts, GetJournalTableCreationScript());
                    if (journalTable.EnsureJournalTableExists())
                    {
                        try
                        {
                            foreach ((string name, object value) resource in GetResources(true))
                            {
                                var filePath = WriteResourceToFile(resource);
                                if (journalTable.TryAcquireLockFor(resource.name))
                                {
                                    CreateProcessFor(sqlCmdPath, filePath);
                                    if (!journalTable.RecordScriptInJournal(resource.name, false))
                                    {
                                        break; // logged
                                    }
                                }
                                else
                                {
                                    // :Configure: log
                                    Console.WriteLine($"Skipping script [{resource.name}]; already executed or may be in process from another client.");
                                }
                            }
                        }
                        catch (FormatException ex)
                        {
                            // :Configure: log
                            Console.WriteLine($"Error encountered during processing of script resources.  Resource file may be corrupted: {ex.Message}");
                        }
                    }
                    else
                    {
                        // :Configure: log
                        Console.WriteLine($"Unable to create/ensure presence of table {JournalTable.TABLE_NAME}");
                    }
                }
            }
        }

        private bool OpenConnection()
        {
            _connection.ConnectionString = _connectionString;
            try
            {
                _connection.Open();
                return true;
            }
            catch (Exception ex) when (ex is ArgumentException || ex is SqlException)
            {
                // :Configure: log
                Console.WriteLine($"Connection failed; unable to apply migrations. {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Start up sqlcmd.exe and execute the script
        /// </summary>
        /// <remarks>Process start inherits the security context of the parent process.
        /// It certainly seems heavy to create a new process for every script but 1) this is the only reliable pattern for running a process (passing in args, starting, etc) and 2) SqlCmd is actually very fast.</remarks>
        private void CreateProcessFor(string sqlcmdPath, string scriptPath)
        {
            var scriptFileName = Path.GetFileName(scriptPath);
            // :Configure: log
            Console.WriteLine($"Executing script {scriptFileName}");

            var psi = new ProcessStartInfo
            {
                CreateNoWindow = true,
                ErrorDialog = false,
                FileName = sqlcmdPath,  // If sqlcmd were installed proper, it would be on path and we could simply pass "SQLCMD"
                UseShellExecute = false,
                Arguments = $"-i {scriptPath} -S {_server}",
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                StandardErrorEncoding = Encoding.UTF8,
                StandardOutputEncoding = Encoding.UTF8,
            };

            try
            {
                using (var process = new Process { StartInfo = psi })
                {
                    process.Start();
                    process.ErrorDataReceived += (sender, e) =>
                    {
                        // Unfortunately this seems to fire with null data for passing and failing scripts.
                        // Doesn't hurt; it's possible it will pass valid error content.
                        if (e.Data != null)
                        {
                            // :Configure: log
                            Console.WriteLine(e.Data);
                            _failedScripts.Add(scriptFileName);
                        }
                    };
                    // :Configure: log
                    process.OutputDataReceived += (sender, e) => Console.WriteLine(e.Data);
                    process.BeginErrorReadLine();
                    process.BeginOutputReadLine();
                    process.WaitForExit(20000); // this doesn't halt.
                }
            }
            catch (Exception ex)
            {
                // :Configure: log
                Console.WriteLine($"Unable to create process for updating database: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Write out the resource file to the same directory we're using for sqlcmd.exe and set the field holding it's path.
        /// We have to write out the resource file so we can read it using the standard library object (and we're already managing files anyway).
        /// </summary>
        /// <returns>pass/fail</returns>
        private bool ExtractScriptResourceFile()
        {
            var result = false;
            using (Stream scriptResourceStream = Assembly.GetExecutingAssembly().GetManifestResourceStream(_fullyQualifiedScriptResourceName))
            {
                if (scriptResourceStream == null)
                {
                    // :Configure: log
                    Console.WriteLine(new FileNotFoundException($"Expected resource stream {_fullyQualifiedScriptResourceName} in assembly {Assembly.GetExecutingAssembly().FullName}"));
                }
                else
                {
                    _scriptResourceFilePath = Path.Combine(_sqlCmdDir, SCRIPT_RESOURCE_FILE_NAME);
                    result = FileUtils.StreamToFile(scriptResourceStream, _scriptResourceFilePath);
                }
            }
            return result;
        }

        /// <summary>
        /// Streams out sqlcmd and it's 2 dependencies.
        /// </summary>
        /// <remarks>Sets class var that is path to temp dir.</remarks>
        private void CreateSqlCmdDir()
        {
            _sqlCmdDir = Path.Combine(Path.GetTempPath(), nameof(SqlCmd));
            DirectoryUtils.FlushDirectory(_sqlCmdDir, true); // in case left over from previous run.
            Directory.CreateDirectory(_sqlCmdDir);
            foreach (var resource in GetResources(false))
            {
                WriteResourceToFile(resource);
            }
        }

        /// <summary>
        /// Write out the actual content (a binary or a script) that has been extracted from the resource.
        /// </summary>
        /// <param name="resource">Result of call to <see cref="GetResources"/> </param>
        private string WriteResourceToFile((string name, object value) resource)
        {
            var filePath = Path.Combine(_sqlCmdDir, resource.name);  // expected that the key is the file name.
            if (resource.value is string)
            {
                File.WriteAllText(filePath, (string)resource.value, Encoding.UTF8);
            }
            else
            {
                File.WriteAllBytes(filePath, (byte[])resource.value);
            }
            return filePath;
        }

        /// <summary>
        /// Get either the executable resource for sqlcmd or actual scripts from the script resource file.
        /// </summary>
        /// <param name="scripts">True if you're asking for script resources; false if you want the actual sqlcmd.exe resources.</param>
        /// <returns>key name, resource value (either a string or a byte array)</returns>
        private IEnumerable<(string name, object value)> GetResources(bool scripts)
        {
            // We get different resources a bit differently.  The script file is a plain resource; the binaries are in a standard .resx.
            IEnumerable<DictionaryEntry> GetResources()
            {
                if (scripts)
                {
                    foreach (var entry in GetOrderedScripts())
                    {
                        yield return entry;
                    }
                }
                else
                {
                    foreach (DictionaryEntry item in SqlCmdResources.ResourceManager.GetResourceSet(CultureInfo.InvariantCulture, true, true))
                    {
                        yield return item;
                    }
                }
            }

            foreach (DictionaryEntry item in GetResources())
            {
                yield return ((string)item.Key, item.Value);
            }
        }

        /// <summary>
        /// Not all keys will be represented as numbers.
        /// </summary>
        /// <returns></returns>
        private IEnumerable<DictionaryEntry> GetNumericResources()
        {
            using (var reader = new ResourceReader(_scriptResourceFilePath))
            {
                foreach (DictionaryEntry entry in reader)
                {
                    if (int.TryParse((string)entry.Key, out var number))
                    {
                        yield return entry;
                    }
                }
            }
        }

        /// <summary>
        /// Get resource keys in order.
        /// </summary>
        /// <returns>Materialized list because it must be ordered.</returns>
        private List<DictionaryEntry> GetOrderedScripts(bool skipFirstScript = true)
        {
            // The first script should always be the journal table creation script.
            var result = GetNumericResources().OrderBy(de => Convert.ToInt32(de.Key)).ToList();
            if (skipFirstScript)
            {
                if (result.Count >= 2)
                {
                    return result.Skip(1).ToList();
                }
                else
                {
                    return new List<DictionaryEntry>();
                }
            }
            else
            {
                return result;
            }
        }

        private string GetJournalTableCreationScript()
        {
            var firstResource = GetOrderedScripts(false).FirstOrDefault();
            Debug.Assert(firstResource.Key != null);
            Debug.Assert(firstResource.Value is string);
            return (string)firstResource.Value;
        }

        private void SetConnectionStrings(string connectionStr)
        {
            var connectionStringBuilder = new SqlConnectionStringBuilder(connectionStr);
            _connectionString = connectionStr;
            _server = connectionStringBuilder.DataSource;
        }

    }

}
