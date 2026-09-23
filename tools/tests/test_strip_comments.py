import ast
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest


TOOL_PATH = Path(__file__).resolve().parents[1] / "strip_comments.py"
SPEC = importlib.util.spec_from_file_location("strip_comments", TOOL_PATH)
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


class LuauComments(unittest.TestCase):
    def test_nested_interpolation_only_strips_expression_comments(self):
        source = '`text -- literal {`nested {({ value = 4 -- remove\n }).value}`} end`\n'
        result = tool.strip_luau(source)
        self.assertIn("text -- literal", result)
        self.assertNotIn("remove", result)
        self.assertEqual(result, '`text -- literal {`nested {({ value = 4\n }).value}`} end`\n')

    def test_strings_long_brackets_and_escapes_are_unchanged(self):
        source = 'local a = "a\\\"--b"\nlocal b = [==[--[[ ]]\n-- text\n]==]\nlocal c = `\\{--literal\\}`\n'
        self.assertEqual(tool.strip_luau(source), source)

    def test_long_comments_do_not_join_tokens(self):
        source = 'return foo--[====[ ignored ]] ]=] ]====]bar\n'
        self.assertEqual(tool.strip_luau(source), 'return foo bar\n')

    def test_directives_and_legal_blocks_survive(self):
        source = '--!strict\n--!native\n-- stylua: ignore\n-- theme_sync:begin metrics\n-- Copyright (c) 2026 Example\n-- All rights reserved.\n\n-- remove\nreturn {}\n'
        result = tool.strip_luau(source)
        self.assertIn('--!strict\n--!native\n-- stylua: ignore', result)
        self.assertIn('-- All rights reserved.', result)
        self.assertIn('-- theme_sync:begin metrics', result)
        self.assertNotIn('-- remove', result)

    def test_unclosed_lexical_construct_fails_closed(self):
        for source in ('--[=[oops', '[[oops', '`a { b', '"oops'):
            with self.subTest(source=source), self.assertRaises(ValueError):
                tool.strip_luau(source)

    def test_crlf_and_string_whitespace_are_preserved(self):
        source = 'local x = [[first   \r\nlast   ]] -- gone\r\n'
        self.assertEqual(tool.strip_luau(source), 'local x = [[first   \r\nlast   ]]\r\n')


class PythonComments(unittest.TestCase):
    def test_comments_strings_and_encoding_directives(self):
        source = '#!/usr/bin/env python3\n# coding: utf-8\nvalue = "#keep" # remove\nvalue += "#"  # noqa: E501\n'
        result = tool.strip_python(source)
        self.assertIn('# coding: utf-8', result)
        self.assertIn('# noqa: E501', result)
        self.assertIn('"#keep"', result)
        self.assertNotIn('# remove', result)

    def test_module_cli_doc_becomes_explicit_string_after_future_import(self):
        source = '"""usage: thing\n\nhelp text"""\nfrom __future__ import annotations\nanswer = __doc__.strip()\n'
        result = tool.strip_python(source)
        namespace = {}
        exec(result, namespace)
        self.assertEqual(namespace['answer'], 'usage: thing\n\nhelp text')
        self.assertNotIn('__doc__', result)
        self.assertIn('CLI_HELP = ', result)
        self.assertIsNone(ast.get_docstring(ast.parse(result)))

    def test_docstring_only_bodies_remain_valid(self):
        source = '"""module prose"""\nclass Thing:\n    """class prose"""\n\ndef work():\n    """function prose"""\n'
        result = tool.strip_python(source)
        self.assertNotIn('prose', result)
        self.assertEqual(result.count('pass'), 2)
        ast.parse(result)

    def test_inline_docstrings_do_not_leave_empty_statements(self):
        source = '"""module prose"""; answer = 1\ndef work(): """function prose"""; return 2\n'
        result = tool.strip_python(source)
        namespace = {}
        exec(result, namespace)
        self.assertEqual(namespace['answer'], 1)
        self.assertEqual(namespace['work'](), 2)

    def test_unicode_positions_do_not_damage_code(self):
        source = 'label = "hé"; value = 2 # remove\n\ndef work():\n    """é prose"""\n    return "é # literal"\n'
        result = tool.strip_python(source)
        namespace = {}
        exec(result, namespace)
        self.assertEqual(namespace['work'](), 'é # literal')

    def test_mutation_of_fixture_literals_is_forbidden(self):
        source = 'fixture = """--!strict\n-- this is test data\nreturn {}\n"""\n'
        self.assertEqual(tool.transform(source, Path('tools/test_example.py')), source)

    def test_removed_comments_and_docstrings_leave_no_trailing_whitespace(self):
        source = 'value = 1  # remove\ndef work():\n    """prose"""\n    return value  \n'
        result = tool.strip_python(source)
        self.assertEqual(result, 'value = 1\ndef work():\n\n    return value\n')
        self.assertEqual(tool.strip_python(result), result)

    def test_whitespace_cleanup_preserves_all_literal_data_and_ast(self):
        source = 'name = "é"  \nfixture = """first   \r\nlast\t \r\n"""  \r\nvalue = f"""{name}   \nend  """  \nraw = br"""bytes   \nend"""  \n'
        result = tool.trim_python_whitespace(source)
        self.assertEqual(ast.dump(ast.parse(source)), ast.dump(ast.parse(result)))
        self.assertIn('first   \r\nlast\t \r\n', result)
        self.assertIn('{name}   \nend  ', result)
        self.assertIn('bytes   \nend', result)
        self.assertNotIn('name = "é"  \n', result)


class ShellComments(unittest.TestCase):
    def test_literals_expansions_arithmetic_and_shebang(self):
        source = '#!/usr/bin/env bash\n# remove\nx="a#b"\necho "${x#prefix}" ${#x} foo#bar $((16#ff)) # gone\n'
        result = tool.strip_shell(source)
        self.assertNotIn('# remove', result)
        self.assertNotIn('# gone', result)
        self.assertIn('${x#prefix}', result)
        self.assertIn('${#x} foo#bar $((16#ff))', result)
        self.assertTrue(result.startswith('#!/usr/bin/env bash\n'))

    def test_heredoc_bodies_and_multiple_delimiters_are_unchanged(self):
        source = "cat <<'ONE' <<-TWO # remove\n# body\n$(echo '#literal')\nONE\n\t# body two\n\tTWO\n# after\n"
        result = tool.strip_shell(source)
        self.assertIn("# body\n$(echo '#literal')", result)
        self.assertIn('\t# body two', result)
        self.assertNotIn('# remove', result)
        self.assertNotIn('# after', result)

    def test_command_substitution_and_nested_quotes(self):
        source = 'value="$(echo "$(echo \'#keep\')" # remove\n)"\necho "$value"\n'
        result = tool.strip_shell(source)
        self.assertNotIn('# remove', result)
        self.assertEqual(subprocess.check_output(['bash', '-c', source]), subprocess.check_output(['bash', '-c', result]))

    def test_heredoc_in_quoted_command_substitution(self):
        source = 'x="$(cat <<\'EOF\' # remove\n# literal\nEOF\n)"\nprintf "%s" "$x"\n'
        result = tool.strip_shell(source)
        self.assertNotIn('# remove', result)
        self.assertEqual(subprocess.check_output(['bash', '-c', source]), subprocess.check_output(['bash', '-c', result]))

    def test_continuations_and_ansi_quotes(self):
        source = "echo $'escaped \\' # literal' \\\n'# still literal' # remove\n"
        result = tool.strip_shell(source)
        self.assertNotIn('# remove', result)
        self.assertEqual(subprocess.check_output(['bash', '-c', source]), subprocess.check_output(['bash', '-c', result]))

    def test_shellcheck_directive_survives(self):
        source = '# shellcheck disable=SC2086\necho $value # remove\n'
        self.assertIn('# shellcheck disable=SC2086', tool.strip_shell(source))

    def test_removed_comments_trim_only_unescaped_code_whitespace(self):
        source = 'printf "%s\\n" "a  "  # remove\nprintf "%s\\n" escaped\\  # remove\n'
        result = tool.strip_shell(source)
        self.assertIn('"a  "\n', result)
        self.assertEqual(subprocess.check_output(['bash', '-c', source]), subprocess.check_output(['bash', '-c', result]))


class TemplatesAndCli(unittest.TestCase):
    def test_named_luau_templates_are_stripped_but_markdown_and_fixtures_are_not(self):
        source = 'local CONTROL_TEMPLATE = [=[--!strict\n-- remove\nreturn {}\n]=]\nlocal API_STUB_TEMPLATE = [=[-- preserved Markdown]=]\nlocal fixture = [[-- literal]]\n'
        result = tool.transform(source, Path('tools/lune/scaffold.luau'))
        self.assertNotIn('-- remove', result)
        self.assertIn('--!strict', result)
        self.assertIn('-- preserved Markdown', result)
        self.assertIn('[[-- literal]]', result)

    def test_python_generator_string_comments_are_stripped_intentionally(self):
        source = 'LUAU_HEADER = "--!strict\\n-- remove\\nreturn {}\\n"\n'
        result = tool.transform(source, Path('tools/build_word_lists.py'))
        self.assertNotIn('-- remove', result)
        self.assertEqual(ast.literal_eval(ast.parse(result).body[0].value), '--!strict\n\nreturn {}\n')

    def test_check_dry_run_write_idempotence_and_vendor_exclusion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'src' / 'vendor').mkdir(parents=True)
            source = root / 'src' / 'main.luau'
            source.write_text('--!strict\n-- remove\nreturn "-- keep"\n')
            vendor = root / 'src' / 'vendor' / 'keep.luau'
            vendor.write_text('-- do not touch\nreturn {}\n')
            command = ['python3', str(TOOL_PATH), '--root', str(root)]
            dry = subprocess.run(command + ['--dry-run'], capture_output=True, text=True)
            self.assertEqual(dry.returncode, 0, dry.stderr)
            self.assertIn('-- remove', source.read_text())
            self.assertEqual(subprocess.run(command + ['--check'], capture_output=True).returncode, 1)
            written = subprocess.run(command + ['--write'], capture_output=True, text=True)
            self.assertEqual(written.returncode, 0, written.stderr)
            self.assertNotIn('-- remove', source.read_text())
            self.assertEqual(vendor.read_text(), '-- do not touch\nreturn {}\n')
            self.assertEqual(subprocess.run(command + ['--check'], capture_output=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()
