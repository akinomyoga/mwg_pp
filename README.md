[ Languages: **English** | [日本語](README.ja_JP.md) (Japanese) ]

# mwg_pp

`mwg_pp` is a line-oriented preprocessor written in AWK.

# 1. Language definition

`mwg_pp` is composed of multiple independent features:

- `mwg_pp:directives`: Basic preprocessor directives.  The other features are
  indirectly invoked through directives.
- `mwg_pp:modifiers`: Transformation of texts
- `mwg_pp:params`: Evaluation of parameter expansions embedded in texts
- `mwg_pp:eval_expr`: Evaluation of expressions of a syntax similar to C/C++

## 1.1 mwg_pp:directives

### define / m

Abbreviation `m` can be used instead of `define`.

```c
#%define ID
...
#%end MODIFIERS
```

This transforms the contents `...` using `MODIFIERS` and stores the result in
the variable `ID`.

```c
#%define ID1 ID2 MODIFIERS
```

This transforms the value of the variable `ID2` using `MODIFIERS` and stores
the result in the variable `ID1`.


### expand / x

Abbreviation `x` can be used instead of `expand`.

```c
#%expand
...
#%end MODIFIERS
```

This transforms the contents `...` using `MODIFIERS` and output the result.

```c
#%expand ID MODIFIERS
```

This transforms the value of the variable `ID` using `MODIFIERS` and output
the result.

### begin / (

```c
#%begin
...
#%end
```

```c
#%(
...
#%)
```

Process directives in `...`, but the result is discarded.

### \# (comment)

```c
#%# COMMENT
```

This is a comment. `COMMENT` is ignored.

### exec / $

This executes a shell command or changes the output/input stream.  The short
form `$` can be used instead of keyword `exec`.

```
#%exec COMMAND
```

The command `COMMAND` is executed in the shell, and its standard output is used
as the output.  Despite its name being shell's `exec`, preprocessing continues
after the execution of the command.

```
#%exec> FILENAME
```

The current output target is switched to `FILENAME`.  The existing contents of
`FILENAME`, if any, will be cleared.

```
#%exec>> FILENAME
```

The current output target is switched to `FILENAME`.  The output is appended to
the existing contents of `FILENAME`, if any.

```c
#%exec>
```

The current output target is reset to the standard output of the current
process.

### eval / [expr]

```c
#%eval EXPR
```
```c
#%[EXPR]
```

Evaluates the expression `EXPR`.


### include / <

Process the contents of the specified file.  The short form `<` can be used
instead of `include`.

```c
#%include FILENAME
```
```c
#%include "FILENAME"
```

If the `FILENAME` starts with `/`, it is interpreted as an absolute path.
Otherwise, it is considered the path relative to the current file.  When the
current file is the standard input, the relative path is considered to be the
path relative to the current working directory.

```c
#%include <FILENAME>
```

The `FILENAME` is searched under `$HOME/.mwg/mwgpp/include`.

### if

```c
#%if EXPR1
...
#%elif EXPR2
...
#%else
...
#%end
```

Perform conditional branching based on the value of `EXPR1`, `EXPR2`, and so
on.  This processes the contents `...` of the selected branch and ignore the
others.

### Deprecated directives

These are deprecated directives.

```c
#%define id ( ... #%) <modifiers>
#%m      id ( ... #%) <modifiers>
#%define id ... #%define end

  use #%m id ... #%end <modifiers>

#%expand ( ... #%) <modifiers>
#%x      ( ... #%) <modifiers>

  use #%x ... #%end <modifiers>

#%if expr1 ( ... #%elif expr2 ... #%else ... #%)

  use #%if expr1 ... #%elif expr2 ... #%else ... #%end

#%data name value
#%data(SEP) datanameSEPvalue

  use #%[name="value"]

#%print name
  use #%x name

#%modify id <modifiers>
  use #%m id id <modifiers>
```

Not implemented:

```c
#%add id ( ... #%) <modifiers>
```

### Removed directives

So far, no constructs were removed.  Some directives were removed at some
point, but I decided to revert them for the backward compatibility.

## 1.2 mwg_pp:modifiers

*modifiers* are a sequence of any of the following elements. *modifiers* can be
an empty sequence.

```
.r|REGEX|STRING|
```

This replaces all the occurrences of substring matching the regular expression
`REGEX` with `STRING`.

```
.R|REGEX|REPLACEMENT|
```

This replaces all the occurrences of substring matching the regular expression
`REGEX` with `REPLACEMENT`.  The backward references of the form `$n` (where
`n` is a number) in `REPLACEMENT` are expanded to the corresponding captures by
`REGEX`.

```
.f|REGEX|EXPR_BEGIN|EXPR_END|
```

This repeats the target text with `REGEX` replaced with an integer in the range
`EXPR_BEGIN` to `EXPR_END`.

```
.i
```

This applies `mwg_pp:param` to the target text.

## 1.3 mwg_pp:param

This processes the following pattern embedded in the target text:

```
$ DELIM PARAM_SPEC DELIM
```

### `DELIM`

There are two types of parameter expansions:

```
${...}
  The expansion "mwg_pp:param" is again applied to the result of the expansion.
$"..."
  The recursive parameter expansion is disabled.
```

When one wants to include a literal character matching `DELIM`, one can escape
it with a backslash `\`.

### `PARAM_SPEC`

```
KEY
  Returns the value of the variable KEY

KEY:-ALTER
  Returns the value of the variable KEY.  When the value is empty, returns
  ALTER instead.

KEY:+VALUE
  Returns VALUE if the variable KEY is not empty.  Otherwise, returns an empty
  string.

KEY:?WARN
  Returns the value of the variable KEY.  When the value is empty, outputs WARN
  to the standard error output.

KEY:START:LENGTH
  Returns a substring the value of the variable KEY.  START specifies the
  0-based index of the beginning of the substring.  LENGTH specifies the length
  of the substring.

#KEY
  Returns the length of the value of the variable KEY.

KEY/REX_BEFORE/TXT_AFTER
  Replace the first substring in the value of the variable KEY, that matches
  the regular expression REX_BEFORE, with TXT_AFTER and returns the result.

KEY//REX_BEFORE/TXT_AFTER
  Replace all substrings in the value of the variable KEY, that match the
  regular expression REX_BEFORE, with TXT_AFTER and returns the result.

KEY.MODIFIERS
  Transform the value of the variable KEY using .MODIFIERS as mwg_pp:modifiers
  and returns the result.

.for:VAR:EXPR_BEGIN:EXPR_END:CONTENT:SEPARATOR
  Repeat CONTENT with the separator SEPARATOR.  Subtring matching VAR are
  replaced with the loop index ranging in [EXPR_BEGIN, EXPR_END].

.for_sep:VAR:EXPR_BEGIN:EXPR_END:CONTENT:SEPARATOR
  The same as .for but SEPARATOR is appended to the last CONTENT if any.

.sep_for:var:expr_begin:expr_end:content:separator
  The same as .for but SEPARATOR is prepended to the first CONTENT if any.

.eval:EXPRESSION
  EXPRESSION is evaluated using "mwg_pp:eval_expr" and returns the result.
```

## 1.4 mwg_pp:eval_expr

### Tokens

- Number: `/[.0-9]+/`
- Variable: `/[_a-zA-Z][_a-zA-Z0-9]*/`
  - Variable namespace is shared with the ones defined by `#%define`.
- Operator
  - Prefix operator: `+ - !`
  - Binary operator: `+ - * / %   == != < <= > >= & ^ | && || = ,`
- Brackets: `/[[({]/` ... `/[])}]/`
  - `[ ... ]` rounds the value to an integer.

### Functions

- Arithmetic/mathematical functions
  - `int(value)`
  - `float(value)`
  - `floor(value)`
  - `ceil(value)`
  - `sqrt(value)`
  - `sin(value)`
  - `cos(value)`
  - `tan(value)`
  - `atan(value)`
  - `atan2(y, x)`
  - `exp(value)`
  - `log(value)`
  - `sinh(value)`
  - `cosh(value)`
  - `tanh(value)`
- Random numbers
  - `rand()`
  - `srand()`
- String manipulations
  - `trim(text)`
  - `sprintf(fmt, ...)` (up to nine variadic arguments are supported)
  - `length(text)`
  - `slice(text, start, end)`
  - `text.length`
  - `text.replace(reg_before, txt_after)`
  - `text.Replace(reg_before, txt_after)`
  - `text.slice(start, end)`
  - `text.tolower()`
  - `text.toupper()`
- System functions
  - `getenv(var)` Retrieve the value of the environment variable.
  - `system(cmd)` Executes the command and take the standard output.

# 2. Environment variables

```
PPC_C=1
```

The lines of the form `/*% ... */` are interpreted as directives.

```
PPC_CPP=1
```

The lines of the form `//% ...` are interpreted as directives.

```
PPC_PRAGMA=1
```

The lines of the form `#pragma% ...` are interpreted as directives.

```
PPLINENO=1
```

Line numbers are output in the form `#line LINENO "FILENAME"`

```
PPLINENO_FILE=filename
```

Specify the filename used by `PPLINENO=1`.

```
DEPENDENCIES_OUTPUT=dependency_filename
```

Saves the dependencies in the file `dependency_filename` in a format that can
be included from `Makefile`.

```
DEPENDENCIES_TARGET=target
```

Specifies the target (i.e., the name on the left-hand side of `:`) in the
dependency file.

```
DEPENDENCIES_PHONY=1
```

Generates empty rules for the files the target depends on so that `make`
ignores the files when they do not exist.
