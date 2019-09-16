using System;
using System.Linq;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Migrator.Utils
{

    /// <summary>
    /// This belongs in a shared library.
    /// </summary>
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
        /// <param name="currentDir"></param>
        /// <param name="deleteDirAfterFlush"></param>
        /// <returns>If failure, it probably can't flush an existing directory due to a locked file.</returns>
        public static bool FlushDirectory(string currentDir, bool deleteDirAfterFlush = false)
        {
            if (Directory.Exists(currentDir))
            {
                FlushFilesFromDirectory(currentDir);

                if (Directory.EnumerateFiles(currentDir, SEARCH_ALL_FILES).Any())
                {
                    return false;  // a file was locked
                }
                else
                {
                    foreach (var dir in Directory.EnumerateDirectories(currentDir))
                    {
                        if (!FlushDirectory(dir, deleteDirAfterFlush))
                        {
                            return false;
                        }
                    }
                    if (deleteDirAfterFlush)
                    {
                        DeleteDirectory(currentDir);
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
        /// <param name="currentDir"></param>
        private static void DeleteDirectory(string currentDir)
        {
            int ticks = Environment.TickCount;
            while ((Environment.TickCount - ticks) < 3000)
            {
                try
                {
                    Directory.Delete(currentDir);
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

        private static void FlushFilesFromDirectory(string currentDir)
        {
            if (Directory.Exists(currentDir))
            {
                foreach (var file in Directory.EnumerateFiles(currentDir))
                {
                    FileUtils.SafeDeleteFile(file, true);
                }
            }
        }

    }

}
