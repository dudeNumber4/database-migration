using System;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;

namespace DatabaseMigration.Utils
{

    /// <summary>
    /// This belongs in a shared library.
    /// </summary>
    [SuppressMessage("Naming", "CA1707: no underscores", Justification="nope")]
    public static class DirectoryUtils
    {

        /// <summary>
        /// Search pattern for all files.
        /// </summary>
        public const string SEARCH_ALL_FILES = "*.*";

        /// <summary>
        /// Warning!  Will *really* flush the directory or throw exception.
        /// Can't just call the overload to Directory.Delete that is recursive because we need to call ClearAttributes on every file.
        /// </summary>
        /// <param name="dir">Directory to flush.</param>
        /// <param name="logger">Startup logger because we have no DI.</param>
        /// <param name="deleteDirAfterFlush">Whether to delete the actual directory after flushing it.</param>
        /// <returns>If failure, it probably can't flush an existing directory due to a locked file.</returns>
        public static bool FlushDirectory(string dir, IStartupLogger logger, bool deleteDirAfterFlush = false)
        {
            if (Directory.Exists(dir))
            {
                FlushFilesFromDirectory(dir, logger);

                if (Directory.EnumerateFiles(dir, SEARCH_ALL_FILES).Any())
                {
                    return false;  // a file was locked
                }
                else
                {
                    foreach (var d in Directory.EnumerateDirectories(dir))
                    {
                        if (!FlushDirectory(d, logger, deleteDirAfterFlush))
                        {
                            return false;
                        }
                    }
                    if (deleteDirAfterFlush)
                    {
                        DeleteDirectory(dir);
                    }
                    return true;
                }
            }
            else
            {
                return true;
            }
        }

        /// <summary>
        /// Here's the story:
        /// If you've just deleted the files from a directory, many times (usually) you can't delete the directory immediately afterwards; windows
        /// will report that the directory isn't empty.  Thus, here we try for up to 2 seconds and if it's still failing after that we stop trying.
        /// </summary>
        /// <param name="dir">Dir to delete.</param>
        private static void DeleteDirectory(string dir)
        {
            int ticks = Environment.TickCount;
            while ((Environment.TickCount - ticks) < 3000)
            {
                try
                {
                    Directory.Delete(dir);
                    return;
                }
                catch (Exception)
                {
                    if ((Environment.TickCount - ticks) > 2000)
                    {
                        throw;
                    }
                }
            }
        }

        private static void FlushFilesFromDirectory(string currentDir, IStartupLogger logger)
        {
            if (Directory.Exists(currentDir))
            {
                foreach (var file in Directory.EnumerateFiles(currentDir))
                {
                    FileUtils.SafeDeleteFile(file, true, logger);
                }
            }
        }

    }

}
