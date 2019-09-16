using System;
using System.IO;
using System.Linq;

namespace Migrator.Utils
{

    /// <summary>
    /// This belongs in a shared library.
    /// </summary>
    public static class FileUtils
    {

        /// <summary>
        /// :Configure: accept log provider?
        /// </summary>
        /// <param name="s">Stream.</param>
        /// <param name="path">Path of file to create.</param>
        /// <returns>pass/fail</returns>
        public static bool StreamToFile(Stream s, string path)
        {
            try
            {
                using (var f = File.Create(path))
                {
                    s.Seek(0, SeekOrigin.Begin);
                    s.CopyTo(f);
                }
                return true;
            }
            catch (UnauthorizedAccessException)
            {
                UnauthorizedAccessMsg(path);
            }
            catch (ArgumentException)
            {
                ArgumentMsg();
            }
            catch (PathTooLongException)
            {
                PathTooLongMsg(path);
            }
            catch (DirectoryNotFoundException)
            {
                DirectoryNotFoundMsg(path);
            }
            catch (IOException)
            {
                IOMsg(path);
            }
            catch (NotSupportedException)
            {
                NotSupportedMsg(path);
            }

            return false;
        }

        /// <summary>Safely deletes a file - no exception if operation fails</summary>
        /// <param name="path">File to delete</param>
        /// <param name="forceDelete">Try to alter flags (if necessary) to accomplish delete</param>
        public static void SafeDeleteFile(string path, bool forceDelete)
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
            catch (UnauthorizedAccessException)
            {
                UnauthorizedAccessMsg(path);
            }
            catch (ArgumentException)
            {
                ArgumentMsg();
            }
            catch (PathTooLongException)
            {
                PathTooLongMsg(path);
            }
            catch (DirectoryNotFoundException)
            {
                DirectoryNotFoundMsg(path);
            }
            catch (IOException)
            {
                IOMsg(path);
            }
            catch (NotSupportedException)
            {
                NotSupportedMsg(path);
            }
        }

        // :configure: Log
        static void UnauthorizedAccessMsg(string path) => Console.WriteLine($"Unauthorized to write file: {path}");
        static void ArgumentMsg() => Console.WriteLine("Null path passed, unable to write file.");
        static void PathTooLongMsg(string path) => Console.WriteLine($"Unable to write file, path too long: {path}");
        static void DirectoryNotFoundMsg(string path) => Console.WriteLine($"Unable to write file, invalid directory: {path}");
        static void IOMsg(string path) => Console.WriteLine($"Unable to write file, I/O error: {path}");
        static void NotSupportedMsg(string path) => Console.WriteLine($"Unable to write file, invalid path: {path}");

    }

}
