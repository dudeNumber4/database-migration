using Migrator.DatabaseMigration.Utils;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Migrator.DatabaseMigration.Utils
{

    /// <summary>
    /// This belongs in a shared library.  Except I'm passing in a logger because we have no DI yet.
    /// </summary>
    public static class FileUtils
    {

        /// <summary>
        /// xx
        /// </summary>
        /// <param name="s">Stream.</param>
        /// <param name="path">Path of file to create.</param>
        /// <returns>pass/fail</returns>
        /// <param name="logger">Startup logger because we have no DI.</param>
        public static bool StreamToFile(Stream s, string path, IStartupLogger logger)
        {
            if (s == null)
            {
                return false;
            }

            try
            {
                using (var f = File.Create(path))
                {
                    s.Seek(0, SeekOrigin.Begin);
                    s.CopyTo(f);
                }
                return true;
            }
            catch (UnauthorizedAccessException e)
            {
                logger?.LogException(e);
            }
            catch (ArgumentException e)
            {
                logger?.LogException(e);
            }
            catch (PathTooLongException e)
            {
                logger?.LogException(e);
            }
            catch (DirectoryNotFoundException e)
            {
                logger?.LogException(e);
            }
            catch (IOException e)
            {
                logger?.LogException(e);
            }
            catch (NotSupportedException e)
            {
                logger?.LogException(e);
            }

            return false;
        }

        public static IEnumerable<string> GetFilesWithNoExtension(string dir)
        {
            if (Directory.Exists(dir))
            {
                return Directory.EnumerateFiles(dir, "*.");
            }
            else
            {
                return Enumerable.Empty<string>();
            }
        }

        /// <summary>Safely deletes a file - no exception if operation fails</summary>
        /// <param name="path">File to delete</param>
        /// <param name="forceDelete">Try to alter flags (if necessary) to accomplish delete</param>
        /// <param name="logger">Startup logger because we have no DI.</param>
        public static void SafeDeleteFile(string path, bool forceDelete, IStartupLogger logger)
        {
            if (string.IsNullOrEmpty(path))
                return;

            try
            {
                if (File.Exists(path))
                {
                    if (forceDelete)
                    {
                        // Not wrapping SetAttributes() with try/catch since Delete() will fail if SetAttributes() fails.
                        if (File.GetAttributes(path) == FileAttributes.ReadOnly)
                            File.SetAttributes(path, FileAttributes.Normal);
                    }
                    File.Delete(path);
                }
            }
            catch (UnauthorizedAccessException e)
            {
                logger?.LogException(e);
            }
            catch (ArgumentException e)
            {
                logger?.LogException(e);
            }
            catch (PathTooLongException e)
            {
                logger?.LogException(e);
            }
            catch (DirectoryNotFoundException e)
            {
                logger?.LogException(e);
            }
            catch (IOException e)
            {
                logger?.LogException(e);
            }
            catch (NotSupportedException e)
            {
                logger?.LogException(e);
            }
        }

    }

}
