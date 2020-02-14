using DatabaseMigrator.Utils;
using FluentAssertions;
using System;
using System.IO;
using System.Text;
using Xunit;

namespace MigratorUnitTests
{

    public class DirectoryUtilsTests : IDisposable
    {

        private const string TEST_DIR = "/DirectoryUtils";
        private const string TEST_FILE_NAME = "x";

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void FlushDirectory(bool deleteContainingDir)
        {
            Dispose();
            Directory.CreateDirectory(TEST_DIR);
            Directory.CreateDirectory(NestedDir());
            File.CreateText(FilePath()).Close();
            File.CreateText(NestedFilePath()).Close();

            Directory.Exists(TEST_DIR).Should().BeTrue();
            Directory.Exists(NestedDir()).Should().BeTrue();
            File.Exists(FilePath()).Should().BeTrue();
            File.Exists(NestedFilePath()).Should().BeTrue();

            DirectoryUtils.FlushDirectory(NestedDir(), TestLogger.Instance(), deleteContainingDir);

            File.Exists(FilePath()).Should().BeFalse();
            File.Exists(NestedFilePath()).Should().BeFalse();
            if (deleteContainingDir)
            {
                Directory.Exists(TEST_DIR).Should().BeFalse();
            }
        }

        public void Dispose()
        {
            if (Directory.Exists(NestedDir()))
            {
                Directory.Delete(NestedDir());
            }
            if (Directory.Exists(TEST_DIR))
            {
                Directory.Delete(TEST_DIR);
            }
        }

        private static string FilePath() => Path.Combine(TEST_DIR, TEST_FILE_NAME);
        private static string NestedFilePath() => Path.Combine(NestedDir(), TEST_FILE_NAME);
        private static string NestedDir() => Path.Combine(TEST_DIR, TEST_DIR);

    }

}
