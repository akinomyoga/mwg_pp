# mwg_pp

mwg_pp は awk で書かれた行指向のプリプロセッサである。
mwg_pp は複数の機能の組み合わせになっている。

- `mwg_pp:directives`: 基本的なプリプロセッサディレクティブの指定。他の機能はこの機能を用いて間接的に呼び出される。
- `mwg_pp:modifiers`: テキストに対する変換を実行する。
- `mwg_pp:params`: テキスト中に埋め込まれたパラメータ展開式を評価する。
- `mwg_pp:eval_expr`: C言語に似た構文の式を評価する。

## mwg_pp:directives

### define

```c
#%define id
...
#%end <modifiers>
```

... の内容を modifiers で変換し、変数 `id` に格納する。省略形として `define` の代わりに `m` を使える。

```c
#%define id1 id2 <modifiers>
```

変数 id2 の内容を modifiers で変換し、変数 `id1` に格納する。省略形として `define` の代わりに `m` を使える。


### expand

```c
#%expand
...
#%end <modifiers>
```

`...` の内容を modifiers で変換して出力する。省略形として `expand` の代わりに `x` を使える。

```c
#%expand id <modifiers>
```

変数 `id` の内容を modifiers で変換し、出力する。省略形として `expand` の代わりに `x` を使える。


### comment

```c
#%begin ... #%end
```

```c
#%( ... #%)
```

... を無視する。

```c
#%# text
```

text を無視する。


### exec

コマンドの実行、または出力先の変更を行う。キーワード `exec` の代わりに省略形として `$` を使える。

```
#%exec command
```

command を shell で実行し、その標準出力を読み取って出力する。名前は exec だが command 実行後は復帰して処理を継続する。

```
#%exec> filename
```

現在の最終出力先を filename に変更する。始めにファイル filename の中身をクリアする。

```
#%exec>> filename
```

現在の最終出力先を filename に変更する。ファイル filename の末尾に追記する。

```c
#%exec>
```

現在の最終出力先を標準出力 (既定の出力先) に変更する。

### eval

```c
#%eval expr
```
```c
#%[expr]
```

式 expr を評価する。


### include

指定したファイルの内容を読み取って出力する。`include` の省略形として `<` が使える。

```c
#%include filename
```
```c
#%include "filename"
```

filename が / で始まる場合は絶対パスと解釈する。
それ以外の場合は、入力ファイルからの相対パスと解釈する。
現在の入力が標準入力からの場合は、カレントディレクトリからの相対パスでファイルを読み取る。

```
#%include <filename>
```

ファイルは `$HOME/.mwg/mwgpp/include` 以下のパスで指定する。

### if

```c
#%if expr1
...
#%elif expr2
...
#%else
...
#%end
```

式 expr の値で条件分岐を実施する。
条件に合致する ... を出力し、他は無視する。

```
DEPRECATED:

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

未実装

  #%add id ( ... #%) <modifiers>

REMOVED:

```

## mwg_pp:modifiers

```
.r|reg_before|txt_after|
  置換を実行します。

.R|reg_before|txt_after|
  置換を実行します。全ての一致を置換します。
  txt_after に前方参照 $n を指定できます。

.f|reg_var|expr_begin|expr_end|
  繰り返し

.i
  mwg_pp:param を実行
```

## mwg_pp:param

```
構成: $ <括弧> <中身> <括弧>

<括弧>:
  ${...}
    展開結果への再帰的適用を有効に
  $"..."
    展開結果への再帰的適用を無効に
  中身自体に括弧の構成文字を含めたい時は \ でエスケープ可能

<中身>:
  key
    変数 key の中身を出力
  key:-alter
    変数 key の中身を出力
    変数 key の中身が空の時は alter を出力
  key:+value
    変数 key の中身が空かどうかを判定し、
    空でなければ value を出力
  key:?warn
    変数 key の中身を出力
    変数 key の中身が空の時は warn を警告として stderr に出力
  key:start:length
    変数 key の中身の部分文字列を出力
    start は部分文字列の開始位置 (zero based) を指定
    length は部分文字列の長さを指定
  #key
    変数 key の中身の文字数を出力します。
  key/rex_before/txt_after
    変数 key の中身を変換した結果を出力します。
    正規表現による置換を実行します。初めの一致だけを置換します。
  key//rex_before/txt_after
    変数 key の中身を変換した結果を出力します。
    正規表現による置換を実行します。全ての一致に対して置換を行います。
  key.modifiers
    変数 key の中身を変換した結果を出力します。
    ".modifiers" によって mwg_pp:modifiers 変換を行います。
  .for:var:expr_begin:expr_end:content:separator
    content を separator で区切って繰り返し出力
  .for_sep:var:expr_begin:expr_end:content:separator
    content を separator で区切って繰り返し出力
    一回以上の出力の際、separator を末端に追加
  .sep_for:var:expr_begin:expr_end:content:separator
    content を separator で区切って繰り返し出力
    一回以上の出力の際、separator を先頭に追加
  .eval:expression
    expression を mwg_pp:eval_expr で評価した結果を出力
```

## mwg_pp:eval_expr

### Tokens

- 数値: `/[.0-9]+/`
- 変数: `/[_a-zA-Z][_a-zA-Z0-9]*/`
  - 変数は `#%define` で定義される物と共有される。
- 演算子
  - 前置演算子: `+ - !`
  - 二項演算子: `+ - * / %   == != < <= > >= & ^ | && || = ,`
- 括弧: `/[[({]/` ... `/[])}]/`
  - `[ ... ]` の時、中身は整数に丸められる。

### Functions

- 算術演算
  - `int(value)`
  - `float(value)`
  - `floor(value)`
  - `ceil(value)`
  - `sqrt(value)`
  - `sin(value)`
  - `cos(value)`
  - `tan(value)`
  - `atan(value)`
  - `atan2(value)`
  - `exp(value)`
  - `log(value)`
  - `sinh(value)`
  - `cosh(value)`
  - `tanh(value)`
- 乱数
  - `rand()`
  - `srand()`
- 文字列操作
  - `trim(text)`
  - `sprintf(fmt,v1,v2,v3,v4,v5,v6,v7,v8,v9)`
  - `length(text)`
  - `slice(text,start,end)`
  - `text.length`
  - `text.replace(reg_before,txt_after)`
  - `text.Replace(reg_before,txt_after)`
  - `text.slice(start,end)`
  - `text.tolower()`
  - `text.toupper()`

## 環境変数

```
PPC_C=1
  /*% ... */ をディレクティブとして解釈する。
PPC_CPP=1
  //% ... をディレクティブとして解釈する。
PPC_PRAGMA=1
  #pragma% ... をディレクティブとして解釈する。

PPLINENO=1
  行番号を出力する。
  例: #line <行番号> "<ファイル名>"

```
