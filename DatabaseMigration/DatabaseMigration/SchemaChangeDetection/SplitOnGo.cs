using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using TSQL;
using TSQL.Statements;
using TSQL.Tokens;

namespace DatabaseMigration.DatabaseMigration.SchemaChangeDetection
{

    public class SplitOnGo
    {

        private const string GO = "go";

        private List<TSQLStatement> _statements;
        private readonly List<string> _results = new List<string>();

        public ImmutableList<string> Split(string script)
        {
            _statements = null;
            _results.Clear();
            if (ContainsGo(script))
            {
                return ProcessStatements(script);
            }
            else
            {
                return ImmutableList.Create(script);
            }
        }

        private bool ContainsGo(string script)
        {
            // quick naive check to eliminate scripts that definetely don't contain go.
            if (script.Contains(GO, StringComparison.CurrentCultureIgnoreCase))
            {
                _statements = TSQLStatementReader.ParseStatements(script);
                return StatementsContainGo();
            }
            else
                return false;
        }

        private bool StatementsContainGo()
        {
            Debug.Assert(_statements != null);
            return _statements.Any(statement =>
            {
                if (statement is TSQLUnknownStatement)
                    return StatementContainsGo((TSQLUnknownStatement)statement);
                else
                    return false;
            });
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="statement"></param>
        /// <returns></returns>
        private static bool StatementContainsGo(TSQLUnknownStatement statement)
            => statement.Tokens.Any(token => TokenContainsGo(token));

        private static bool TokenContainsGo(TSQLToken token)
            => token.AsKeyword == null ? false : token.AsKeyword.Text.Equals(GO, StringComparison.CurrentCultureIgnoreCase);

        /// <summary>
        /// Go rules:
        ///  can be first word followed by comments
        /// cannot be first full word on line along with other script.
        /// cannot be multiple go on same line.
        /// may be last full word on line: remove just that word
        /// Can be last full word on line followed only by comment
        /// </summary>
        /// <param name="script">Script contains go (not just naive check, go is in _statements)</param>
        /// <returns></returns>
        private ImmutableList<string> ProcessStatements(string script)
        {
            int pos = 0;
            foreach (TSQLStatement statement in _statements)
            {
                TSQLToken goToken = statement.Tokens.FirstOrDefault(token => TokenContainsGo(token));
                if (goToken != null)
                {
                    _results.Add(script.Substring(pos, goToken.BeginPosition - pos));
                    pos = goToken.EndPosition + 1;
                }
            }
            if (pos < script.Length) // if last thing was go, this won't enter
                _results.Add(script.Substring(pos, script.Length - pos));
            return ImmutableList.Create(_results.ToArray());
        }

    }

}
