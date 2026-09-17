---
name: nushell
description: Provides nushell v0.112 coding style, best practices, and critical gotchas. ALWAYS invoke before reading or writing .nu files to ensure idiomatic code and avoid common mistakes.
user-invocable: false
extensions: [nu]
---

# Nushell v0.112 Style & Best Practices

## Naming Conventions

- **Commands**: `kebab-case` (`fetch-data`, `process-items`)
- **Variables/Parameters**: `snake_case` (`user_name`, `file_count`)
- **Environment Variables**: `SCREAMING_SNAKE_CASE` (`$env.APP_MODE`)
- **Flags**: `kebab-case` (`--output-format`)

## Formatting

- 2-space indentation
- One space around `|` pipes
- No trailing spaces
- Max 2 positional params per command; use flags beyond that
- Closures on one line if short; multi-line with `}` on its own line if long
- ~80 char line target; break long pipelines across lines
- Run `treefmt <file>.nu` on changed `.nu` files after edits

## Idiomatic Patterns

### Think in pipelines, not imperative loops

```nushell
# BAD
mut total = 0
for x in [1 2 3] { $total += $x }

# GOOD
let total = [1 2 3] | math sum

# Or use reduce for custom accumulation
let total = [1 2 3] | reduce {|it, acc| $acc + $it}
```

Prefer `each`, `where`, `reduce`, `select`, `reject` over mutable accumulators.

### Immutability first

Use `let` by default, `mut` only when truly needed. Closures cannot capture `mut` variables.

### Prefer pipelines over single-use variables

```nushell
# BAD
let content = open data.csv
let filtered = $content | where size > 1kb
$filtered | first 10

# GOOD
open data.csv | where size > 1kb | first 10
```

Named variables are fine when used more than once or when a name adds clarity.

### No unnecessary parentheses in `let`

```nushell
# BAD
let files = (ls | where type == "file")

# GOOD
let files = ls | where type == "file"
```

Parentheses only needed for subexpressions inside a larger expression: `(ls | length) > 0`.

### Type-annotate exported commands

```nushell
@example "double an int" { 5 | double } --result 10
def double []: [number -> number] {
  $in * 2
}
```

Use `def command-name [param: type]: input -> output { }` with type signatures for public APIs.

### Use `$in` for pipeline input in closures

```nushell
[1 2 3] | each { $in * 2 }
```

`$in` refers to pipeline input. Explicit params `{|x| $x * 2}` also work.

### Error handling: never swallow errors silently

```nushell
# BAD
try { ^cmd o+e> /dev/null } catch {}
try { ^cmd } catch { null }

# GOOD -- deliberate handling
try { ^cmd } catch {|e| error make {msg: $"cmd failed: ($e.msg)"}}

# GOOD -- let it crash if you can't handle it
^cmd
```

Only use `?` optional access when absence is a legitimate expected state.

### Use `where` not `filter` (which accepts closures directly)

### Small, testable functions over monolithic scripts

Extract logic into small named functions that can be tested independently. Avoid deeply nested, run-on pipelines that do too many things at once.

```nushell
# BAD -- monolithic, untestable
def main [] {
  open config.json | get servers | each {|s|
    if ($s.enabled) {
      http get $"($s.url)/health" | get status | if $in != "ok" {
        # 20 more lines of nested logic...
      }
    }
  }
}

# GOOD -- decomposed, each piece testable
def check-health [url: string]: nothing -> record {
  http get $"($url)/health"
}

def active-servers []: table -> table {
  where enabled
}

def main [] {
  open config.json | get servers | active-servers | each {|s|
    check-health $s.url
  }
}
```

### Test-drive logical parts

Write tests for non-trivial logic. Never fix a test to make broken code pass -- fix the code to pass valid tests. Use `nu -c` or a test runner to validate functions in isolation.

### Use built-in commands over externals

- `http get`/`http post` instead of `curl`
- `open file.json` auto-parses (don't add `| from json`)
- Use `open --raw` for raw string content
- `^cmd` prefix to force external when shadowed by a Nu builtin
- `%cmd` prefix to force built-in when shadowed by a custom command

## Scripts

- Shebang: `#!/usr/bin/env nu`
- For stdin: `#!/usr/bin/env -S nu --stdin` and `$in` MUST be inside `def main`, not top-level
- Subcommands require a parent `def main` stub or `$in` silently fails
- Scripts with `--stdin` hang if nothing is piped (no way to detect)

## Critical Gotchas

1. **No `&` for background** -- use `job spawn { ... }`
2. **`const` is parse-time only** -- cannot use commands, env vars, or runtime values
3. **Closures can't capture `mut`** -- use `reduce` or `for` loops
4. **`>` is comparison, not redirect** -- use `| save` or `o>`
5. **Env changes are scoped** -- use `def --env` or `do --env` to persist
6. **Pipefail is default** -- non-zero exit codes propagate as errors; use `try/catch`
7. **`| complete` only works on success** -- non-zero exits error before reaching `complete`
8. **`do -i` only ignores exit codes, not stderr** -- add `o+e>| ignore` to suppress output
9. **`do -i` fails inside `each`** -- use `try` instead
10. **Escape parens in interpolated strings** -- `$"($n) apple\(s\)"` not `$"($n) apple(s)"`
11. **`match` returns closures, doesn't execute them** -- use `do` on the result
12. **`$in` at script top-level causes IR error** -- must be inside `def main`
13. **Long redirect forms don't work for pipes** -- use `o+e>|` not `out+err>|`
14. **`get` extracts values (list), `select` keeps structure (table)**
15. **`is-empty` beats `== null`** -- also catches empty strings, lists, records
16. **`each` passes `null` through** -- null values skip the closure, not filtered out
17. **`find` is case-sensitive by default** -- use `-i` for case-insensitive
18. **`date from-human` for natural dates** -- `into datetime` no longer parses "next Friday"
19. **`split column` is 0-based** -- columns are `column0`, `column1`
20. **Use `--optional` not `--ignore-errors`** -- on `get`, `select`, `reject`
21. **`$nu.temp-dir` / `$nu.home-dir`** -- old `*-path` names removed

## Renamed/Removed Commands

| Old | New |
|-----|-----|
| `filter` | `where` |
| `range` | `slice` |
| `fmt` | `format number` |
| `into bits` | `format bits` |
| `--ignore-errors` | `--optional` |
| `job tag` | `job describe` |
| `job spawn --tag` | `job spawn --description` |
| `into value` (type inference) | `detect type` |
| `open *.md` (raw text) | returns structured AST; use `open --raw` for text |
