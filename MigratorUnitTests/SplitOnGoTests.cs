using System;
using DatabaseMigration.DatabaseMigration.SchemaChangeDetection;
using FluentAssertions;
using System.Linq;
using Xunit;

namespace MigratorUnitTests
{

    public class SplitOnGoTests
    {

        [Fact]
        public void FirstCase()
        {
            var input = TestResource.FirstCase;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(2);
            result[0].Should().Be(TestResource.FirstCaseFirstResult);
            result[1].Should().Be(TestResource.FirstCaseSecondResult);
        }

        [Fact]
        public void SecondCase()
        {
            var input = TestResource.SecondCase;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(2);
            result[0].Should().Be(TestResource.SecondCaseFirstResult);
            result[1].Should().Be(TestResource.SecondCaseSecondResult);
        }

        [Fact]
        public void ThirdCase()
        {
            var input = TestResource.ThirdCase;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(2);
            result[0].Should().Be(TestResource.ThirdCaseFirstResult);
            result[1].Should().Be(TestResource.ThirdCaseSecondResult);
        }

        [Fact]
        public void DoesNotContainGo()
        {
            var input = TestResource.DoesNotContainGo;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(1);
            result[0].Should().Be(TestResource.DoesNotContainGo);
        }

        [Fact]
        public void ContainsGoInComment()
        {
            var input = TestResource.ContainsGoInComment;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(1);
            result[0].Should().Be(TestResource.ContainsGoInComment);
        }

        [Fact]
        public void ContainsGoInAlternativeCommentStyle()
        {
            var input = TestResource.ContainsGoInAlternativeCommentStyle;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(1);
            result[0].Should().Be(TestResource.ContainsGoInAlternativeCommentStyle);
        }

        [Fact]
        public void ColumnNameContainsGo()
        {
            var input = TestResource.ColumnNameContainsGo;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(1);
            result[0].Should().Be(TestResource.ColumnNameContainsGo);
        }

        [Fact]
        public void GoIsLastWordNoNewline()
        {
            var input = TestResource.GoIsLastWordNoNewline;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(1);
            result[0].Should().Be(TestResource.GoIsLastWordNoNewlineResult);
        }

        [Fact]
        public void GoIsLastWordWithNewline()
        {
            var input = TestResource.GoIsLastWordWithNewline;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(1);
            result[0].Should().Be(TestResource.GoIsLastWordWithNewlineResult);
        }

        [Fact]
        public void UnixLineEnding()
        {
            var input = TestResource.UnixLineEnding;
            SplitOnGo splitter = new();
            var result = splitter.Split(input);
            result.Count().Should().Be(2);
            result[0].Should().Be(TestResource.UnixLineEndingFirstResult);
            result[1].Should().Be(TestResource.UnixLineEndingSecondResult);
        }

    }

}
