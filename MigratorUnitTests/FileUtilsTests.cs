using FluentAssertions;
using Migrator.DatabaseMigration.Utils;
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Xunit;

namespace MigratorUnitTests
{

    public class FileUtilsTests : IDisposable
    {

        private const string TEST_DIR = "/FileUtils";
        private const string TEST_FILE_NAME = "x";
        private const string TEST_FILE_CONTENTS = "x";

        [Fact]
        public void StreamToFile()
        {
            Dispose();
            Directory.CreateDirectory(TEST_DIR);
            using (var m = new MemoryStream(Encoding.UTF8.GetBytes(TEST_FILE_CONTENTS)))
            {
                FileUtils.StreamToFile(m, FilePath(), TestLogger.Instance());
            }
            File.ReadAllText(FilePath()).Should().Be(TEST_FILE_CONTENTS);
        }

        [Fact]
        public void SafeDeleteFile()
        {
            Dispose();
            Directory.CreateDirectory(TEST_DIR);
            StreamWriter sw = File.CreateText(FilePath());
            FileUtils.SafeDeleteFile(FilePath(), false, TestLogger.Instance()); // no blow-up
            sw.Close();
            FileUtils.SafeDeleteFile(FilePath(), true, TestLogger.Instance());
            File.Exists(FilePath()).Should().BeFalse();
        }

        public void Dispose()
        {
            if (Directory.Exists(TEST_DIR))
            {
                DirectoryUtils.FlushDirectory(TEST_DIR, TestLogger.Instance(), true);
            }
        }

        private static string FilePath() => Path.Combine(TEST_DIR, TEST_FILE_NAME);

    }

}
