                                                           -*- coding:utf-8 -*-
-------------------------------------------------------------------------------
  mwg_pp 機能解説
-------------------------------------------------------------------------------

mwg_pp は複数の機能から成ります。
- mwg_pp:directives
  基本的なプリプロセッサディレクティブです。
  他の機能はこの機能を用いて間接的に呼び出されます。
- mwg_pp:modifiers
  テキストに対する変換を実行します。
- mwg_pp:params
  テキスト中に埋め込まれたパラメータ展開式を評価します。
- mwg_pp:eval_expr
  C言語に似た構文の式を評価します。

■mwg_pp:directives
define
  #%define id ( ... #%) <modifiers>
  #%m      id ( ... #%) <modifiers>
    ... の内容を modifiers で変換し、変数 id に格納します。
  #%define id1 id2 <modifiers>
  #%m      id1 id2 <modifiers>
    変数 id2 の内容を modifiers で変換し、変数 id1 に格納します。

expand
  #%expand ( ... #%) <modifiers>
  #%x      ( ... #%) <modifiers>
    ... の内容を modifiers で変換し、出力します。
  #%expand id <modifiers>
  #%x      id <modifiers>
    変数 ... の内容を modifiers で変換し、出力します。

comment
  #%( ... #%)
    ... を無視します。
  #%# text
    text を無視します。

exec
  コマンドの実行、または出力先の変更を行います。

  #%exec command
  #%$    command
    command を shell で実行し、その標準出力を読み取って出力します。
    (exec という名前ですが、command 実行後は復帰して処理を継続します。)

  #%exec> filename
  #%$   > filename
    現在の最終出力先を filename に変更します。
    始めに filename の中身をクリアします。

  #%exec>> filename
  #%$   >> filename
    現在の最終出力先を filename に変更します。
    filename の末尾に追記します。

  #%exec>
  #%$   >
    現在の最終出力先を標準出力 (既定の出力先) に変更します。

eval
  #%eval expr
  #%[expr]
    式 expr を評価します。

include
  指定したファイルの内容を読み取り、出力します。

  #%include filename
  #%include "filename"
  #%<       filename
  #%<       "filename"
    filename が / で始まる場合は絶対パスと解釈します。
    それ以外の場合は、入力ファイルからの相対パスと解釈します。
    標準入力からの場合は、カレントディレクトリからの相対パスです。

  #%include <filename>
  #%<       <filename>
    ファイルは $HOME/.mwg/mwgpp/include 以下のパスで指定します。

if
  #%if expr1 ( ... #%elif expr2 ... #%else ... #%)
    式 expr の値で条件分岐を実施します。
    条件に合致する ... を出力し、他は無視します。

OBSOLETE:
  #%define id ... #%define end
    use #%define id ( ... #%) <modifiers>

  #%data name value
  #%data(SEP) datanameSEPvalue
    use #%[name="value"]

  #%print name
    use #%x name

  #%modify id <modifiers>
    use #%m id id <modifiers>

未実装
  #%add id ( ... #%) <modifiers>

DEPRECATED:

■mwg_pp:modifiers
.r|reg_before|txt_after|
  置換を実行します。

.R|reg_before|txt_after|
  置換を実行します。全ての一致を置換します。
  txt_after に前方参照 $n を指定できます。

.f|reg_var|expr_begin|expr_end|
  繰り返し

.i
  mwg_pp:param を実行

■mwg_pp:param

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

■mwg_pp:eval_expr
Tokens
  数値
    /[.0-9]+/
  変数
    /[_a-zA-Z][_a-zA-Z0-9]*/
    変数は #%data で定義される物である
  演算子
    前置演算子: + -       !
    二項演算子: + - * / %   == != < <= > >= & ^ | && || = ,
  括弧
    /[[({] ... [])}]/
    [ ... ] の時中身を整数に丸め

Functions
  算術演算
    int(value)
    float(value)
    floor(value)
    ceil(value)
    sqrt(value)
    sin(value)
    cos(value)
    tan(value)
    atan(value)
    atan2(value)
    exp(value)
    log(value)
    sinh(value)
    cosh(value)
    tanh(value)

  乱数
    rand()
    srand()

  文字列操作
    trim(text)
    sprintf(fmt,v1,v2,v3,v4,v5,v6,v7,v8,v9)
    length(text)
    slice(text,start,end)

    text.length
    text.replace(reg_before,txt_after)
    text.Replace(reg_before,txt_after)
    text.slice(start,end)
    text.tolower()
    text.toupper()

■環境変数

PPC_C=1
  /*% ... */ をディレクティブとして解釈します。
PPC_CPP=1
  //% ... をディレクティブとして解釈します。
PPC_PRAGMA=1
  #pragma% ... をディレクティブとして解釈します。

PPLINENO=1
  行番号を出力します
  例: #line <行番号> "<ファイル名>"



-------------------------------------------------------------------------------
  ChangeLog (mwg_pp.awk の歴史)
-------------------------------------------------------------------------------
[mwg_pp.awk v2.2]

2015-07-06
  * mwgpp v2.2 分岐

------------------------------------------------------------------------------
[mwg_pp.awk v2.1]

2015-07-06
  * mwg_pp.awk (function replace): bugfix
  * mwg_pp.awk (dependency の出力機能)
  * git repository 作成
  * v2.1 stable とする。

2015-06-14
  * (process_line): 行末の ^M (\r) を除去してから directive 行を解釈する。

2015-05-15
  * #%error: ディレクティブ追加
  * expr (string#toupper, string#tolower): 関数追加

2015-04-28
  * #%expand: 引数がない場合は #%expand ( と同じ解釈に。#%end との対称性の為。

2015-01-24
  * #%include: bugfix, include path が
    前回 include したファイルのディレクトリになっている。
    include し終わった後に m_lineno_cfile を復元する様に。
  * END: エラーがあった場合は正常終了ではなく exit(1) をする様に変更。
    
2014-12-14
  * #%begin, #%end: 追加。それぞれ #%( #%) と同じ意味。
    #%( #%) の様な中途半端な括弧を使うとエディタによってインデントがおかしくなるので。
    "#%if ... (" や "#%m ... (" の括弧は元々省略可能なので問題ない。
  * #%exec: 出力先を変更した際に flush をする様に変更。

2014-09-29
  * %else,elif: bugfix, if 文の状態遷移が不完全だった。ちゃんと実装し直し。

2014-05-02
  * modify_text(r,R): flag m を実装。行毎の変換。

2013-08-17
  * パラメータ展開: #bugfix 変数の内容が 0 の時に、null と解釈され結果が空白になる。
    どうやら空文字列と null の区別は全くない様なので、その様に変更した。

2012-10-11
  * 一部のマシンで gawk を呼び出せなかった。
    gawk は本来 /bin/gawk ではなくて /usr/bin/gawk にある様子?
    /usr/bin/gawk に修正する事にした。

    ※/usr/local/bin/gawk を参照する様に説明している頁もあったが、
      実際に見てみた所 cygwin でも ubuntu でも /usr/local/bin には殆ど何も置かれていなかった。
      /usr/local/bin はそもそもユーザが勝手にインストールする先の筈である。

2012-09-24
  * #bugfix 空の行番の出力を抑制する様に修正

2012-07-26
  * 行番号の出力機能 (PPLINENO)
  * mwg_pp.awk が肥大化してきたが、初めはこんなに多機能にする気はなかった筈と思
    いを巡らす内に、今迄の経緯を纏めたくなった。この mwg_pp.awk の歴史をこの日
    の分まで書く。

2012-03-11
  eval 拡張
  * 演算子データベースの整理。
  * 代入演算子の実装 = *= += etc
  * メンバ関数の増強
  
2011-12-05
  * 出力先の切り替え機能。
  * ディレクティブ形式の拡張 (PPC_C, PPC_CPP 等)

2011-09-13
  eval 増強。メンバ関数と破壊的操作。その他。

2011-07-14
  eval のリファクタリング。ev2 の実装。

  これ以降に version を mwgpp v2.1 と割り当てる。

------------------------------------------------------------------------------
[mwg_pp.awk v2.0]

2011-04-07
  tkyntn に移動してきたのは 2011-04-07 である。tkyntn を使い始めて直ぐである。

  [murase@tkyntn 1 src]$ stat mwg_pp.awk
    File: `mwg_pp.awk'
    Size: 43812           Blocks: 44         IO Block: 65536  通常ファイル
  Device: 9c61c85ch/2623653980d   Inode: 1970324837089985  Links: 1
  Access: (0755/-rwxr-xr-x)  Uid: ( 1000/  murase)   Gid: (  513/    None)
  Access: 2012-07-26 17:51:42.223654700 +0900
  Modify: 2012-07-26 18:14:22.717644300 +0900
  Change: 2012-07-26 18:14:22.717644300 +0900
   Birth: 2011-04-07 10:35:37.476955000 +0900

2011-03-28
  * .R/// の実装

2011-01-15
  eval の拡張。この時点で何処まで拡張したかは覚えていない。恐らく簡単な関数が使
  えるぐらいまで?

2011-01-07 ~ 2011-01-09
  この時期に集中的に書換が行われた様子である。沢山のテストファイルが作られてい
  る (test1 ~ test6)。
  * もしかすると .r/// はこの時点で実装されたのかも知れない。
  * 繰り返し展開 .f/// 及び ${.for} の類
  * 四則演算の評価 ${.eval} (この時点では eval は未だ簡単な物だったはず)

2010-10-19
  テストディレクトリを作ったのがこの時。test.pp を見ると、少なくとも 2010-10-19
  昼の時点で #%exec 機能が実装されていた様子。記憶が正しければ初めに実装したの
  は define と expand と .r/// 置換だったので、この時点でこれらは完成していたの
  ではないかと思う。また、aaa.data を見れば遅くとも 2010-10-19 夜中の時点で
  #%define, #%expand, #%data, modify_text, パラメータ展開 等の機能が実装されて
  いた。
  
    File: `/home/koichi/test/mwg_pp'
   Birth: 2010-10-19 07:27:38.640625000 +0900
    File: `/home/koichi/test/mwg_pp/test.pp'
  Modify: 2010-10-19 11:49:11.671875000 +0900
   Birth: 2010-10-19 07:28:10.750000000 +0900
    File: `/home/koichi/test/mwg_pp/aaa.data'
  Modify: 2010-10-20 00:01:12.781250000 +0900
   Birth: 2010-10-19 07:30:15.296875000 +0900
  [koichi@gauge 1 test]$ cat /home/koichi/test/mwg_pp/test.pp 
  
  ##%exec ls -l
  #%exec cat ???.data
  #%exec echo "current working directory is $PWD"
  
  
  [koichi@gauge 1 test]$ cat /home/koichi/test/mwg_pp/aaa.data 
  #%data(:::) hoge:::hello
  #%define 1
  aaa
  bbb
  ${hoge}
  ${hage:-(null)}
  ${hoge:1:3}
  ${#hoge}
  ccc
  ddd
  #%define end
  #%expand 1.i

2010-10-18
  一番初めに awk で作り始めたのが何時かは覚えていないが…
  恐らく 2010-10-18 の朝であろう。

  [koichi@gauge 1 bin]$ stat mwg_pp.awk
    File: `mwg_pp.awk'
    Size: 43812           Blocks: 44         IO Block: 65536  通常ファイル
  Device: 18f01ae5h/418388709d    Inode: 110619665847288160  Links: 1
  Access: (0755/-rwxr-xr-x)  Uid: ( 1005/  koichi)   Gid: (  513/  なし)
  Access: 2012-07-26 18:15:36.875000000 +0900
  Modify: 2012-07-26 18:14:22.000000000 +0900
  Change: 2012-07-26 18:14:32.171875000 +0900
   Birth: 2010-10-18 08:44:28.359625000 +0900

  これ以降に version を mwgpp v2.0 と割り当てる事にする。

------------------------------------------------------------------------------
[mwg.pp.cs 時代]

2009-11-23 ~ 2010-07-29

  libstring (現在の mwg-string, cpp) に転用する為に afh.Design から一つのバイナ
  リとして独立 (mwg.pp.cs mwg.pp.exe)。この期間はこの .cs ファイルを書き換える
  事によって機能を増やしたりしていた。

  しかし、段々と管理が面倒になってくる。このコードでは行単位に処理するのではな
  くて、テキスト全体に対して正規表現を次から次へと適用していく方式にしていた為、
  途中状態などが存在しなかった。より柔軟な機能を持たせる為に行指向の処理に変更
  したかった。一方で、.cs で書かれている為に Windows 以外の環境で使えないという
  問題点もあり、より広い環境で使える言語を用いて書き直したいとも考えていた。

  この時には version については考えていなかったが仮に mwgpp v1 と考える事にする。

------------------------------------------------------------------------------
[afh/afh.Design/TemplateProcessor.cs 時代]

2008-12-04

  原型は Visual Studio の Addin として作ってみた物が最初。元々は afh.HTML を実
  装する為に、同じ様な関数定義の連続を自動生成する為に作成。丁度、この頃構文解
  析のコードを楽に記述する為の Addin を作っていたのでそれを少し弄って作成した
  筈。現在の define と expand 及び .r/// の機能は元々この時点で導入した物 (文法
  は今とは異なるが)。define された物を template と呼んでいた。
