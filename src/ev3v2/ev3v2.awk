#!/usr/bin/gawk -f

# 実装の解説
#
#   ev3obj
#
#     awk 上にオブジェクト指向な構造を作る為の部分。
#     awk には連想配列はあるが、連想配列の要素にはスカラーしか代入できない。
#     また、型も文字列と数値しか存在せず、両者を判別する方法もない。
#     これでは、様々な型や複雑に入れ子になったオブジェクトを表現できない。
#
#     一番素直な方法として、計算機が行っているのと同じ事をすれば良い。単一の配列をメモリ空間に見立てて、
#     全てのオブジェクトの情報をその配列に格納し、参照は配列の添字を以て行うのである。
#     幸い awk では連想配列を使う事ができ、また配列要素のデータ長は任意なので、実装は幾分直観的に行う事ができる。
#     特にこの実装では「データ」と「型」のペアを格納する事にする。いわゆるタグ付きのメモリである。
#     この実装では動的型付言語を取り扱うので、この方が都合がよいし、実装も明解である。
#
#     また、参照カウント式のメモリ管理を行う。
#
#     メモリ管理の効率などを考えて、型を以下の 5 種類に分類して取り扱う。
#
#     CLASS_NULL (原始型 値型)
#       空の型。このクラスに属する型は TYPE_NULL のみである。
#
#     CLASS_SCAL (原始型 値型)
#       スカラー型。単一の数値または文字列でデータを表現できる基本型はこれになる。
#       コピーの際は値が直接コピーされる。
#
#       文字列 (TYPE_STR), 数値 (TYPE_NUM), 真偽値 (TYPE_BOOL) などの基本的な型がこれに当たる。
#       他に列挙型もこれに当たる。更に、外部関数参照など、単一の値だけで表現できる特殊な値も含む。
#
#       特に参照 (TYPE_REF) は重要な働きをし、また、特別な振る舞いをする。
#       参照型はコピーの際に参照カウントの increment/decrement も合わせて行う。
#       参照型は何れの型のオブジェクトを指す事もでき、また、複合型のメンバを指す事も出来る。
#       メンバを指している時は、参照カウントの増減はメンバの持ち主に対して行われる。
#
#     CLASS_STRUCT (複合型 値型 静的)
#       複数の構成要素 (メンバ) からなる型である。
#       それぞれのメンバは (CLASS_BYREF 以外の型を持つ) 独立した変数である。
#       また、メンバは事前に定義した物のみを使う事ができる。
#       
#       コピーの際はメンバ毎に一つずつコピーが行われる。
#       コピーを行わない、比較的軽量な型に使われる。
#
#     CLASS_BYREF (複合型 参照型 動的)
#       所謂参照型である。コピーの際には参照 (TYPE_REF) が作成され、それが代わりに代入される。
#       メンバは動的に追加・削除する事が可能である。
#       (どの様なメンバを保持しているかのリストも管理しなければならないのでその分コストは高い)。
#
#     CLASS_ARRAY (複合型 参照型 動的) (■未実装)
#       配列型である。これは配列としてしか使えない。BYREF の subclass として実装?
#       要素一覧として最大添字だけを管理するのでコストは多少小さい。
#       但し、無意味に巨大な添字を設定すると大変な事になるので注意する。
#
#     ev3obj のセクションでは以上の汎用的な部分に仕様を制限し、以下の様な物を提供する
#     - 参照カウントの管理 (ev3obj_new, ev3obj_delete, ev3obj_capture, ev3obj_release, etc) 部分
#     - データのコピー・初期化 (ev3obj_assignScal, ev3obj_assignObj, _ev3obj_destruct) を行う部分
#     - 複合型のメンバアクセス (ev3obj_setMemberObj..., ev3obj_getMember..., ev3obj_unsetMember) を行う部分
#     - デバグ用の関数 (ev3obj_dump)
#
#     ※ガベージコレクション(mark&sweep)は実装していないが、
#       追加で実装するとすればこの部分 ev3obj を変更すれば良いだけの筈である。
#
#   ev3proto
#
#     特に今回の言語実装でのオブジェクトの振る舞いなどを規定する部分である。
#     JavaScript (ECMAScript) の prototype を真似た実装を行う。
#     これはオブジェクト指向に普遍的な構造・機構ではないので ev3proto として分離した。
#
#     ユーザが設定・取得するプロパティ "propertyName" は内部的には ev3obj のメンバ "+propertyName" として扱う。
#     その他に内部的なプロパティとして演算子 "!operatorName" その他を保持できる様にする。

function _ev3_assert(condition,source,message){
  if(!condition){
    print "[1;31mEV3BUG (" source ")![m " message > "/dev/stderr"
    exit 1
  }
}

function _ev3_error(source,message){
  print "[1;31m" source "![m " message > "/dev/stderr"
}

#==============================================================================
# ev3obj

function _ev3obj_error(message){
  _ev3_error("obj",message);
}
function ev3obj_initialize(){
  TRUE=1;
  FALSE=0;
  NULL="";
  QNAN="+nan"+0;

  ev3obj_index=0;
  UKEY_REF    ="%" ; # 参照カウント
  UKEY_TYP    =":" ; # 型
  UKEY_MEM_CNT=".#"; # メンバ保持数
  UKEY_MEM_KEY=".*"; # メンバ序数 → メンバ名
  UKEY_MEM_ORD=".&"; # メンバ名   → メンバ序数
  UKEY_MEM    ="." ; # メンバ
  UKEY_PROTO  ="_" ; # __proto__

  # 用語
  #
  # 独立実体
  #   ev3obj_universe に直接登録されている物。UKEY_REF (参照カウント) を持つ。
  # 従属実体
  #   独立実体の一部・メンバに直接埋め込まれて存在している実体。
  #
  TYPE_NULL=0;
  TYPE_REF =1;   # 実体への参照 (独立実体、従属実体の両方ともOK)
  TYPE_NUM =11 ; # 値型実体 数値
  TYPE_STR =12 ; # 値型実体 文字列
  TYPE_BOOL=13 ; # 値型実体 真偽値
  TYPE_OBJ =101; # 参照型実体

  # @var ev3obj_rex_subkey
  #   従属実体の参照から、所属する独立実体の ptr を取得する為の物
  #   sub(ev3obj_rex_subkey,"",ptr);
  ev3obj_rex_subkey="[" SUBSEP "].*$";

  # ev3obj_type
  ev3obj_type_index=1000;
  EV3OBJ_TKEY_CLS="+"; # 値型/参照型などの取り扱いの種別
  EV3OBJ_TKEY_ENU_CNT="=#"; # 前回のenum値
  EV3OBJ_TKEY_ENU_NAM="=*"; # enum値   → メンバ名
  EV3OBJ_TKEY_ENU_VAL="=&"; # メンバ名 → enum値

  CLASS_NULL  =0;
  CLASS_SCAL  =1; # 単純値型
  CLASS_BYREF =2; # 参照型実体 (常に独立実体)
  CLASS_STRUCT=3; # 値型構造体 (固定メンバ、値型)

  # null
  ev3obj_type[TYPE_NULL]="null";
  ev3obj_type[TYPE_NULL,EV3OBJ_TKEY_CLS]=CLASS_NULL;

  # string
  ev3obj_type[TYPE_STR]="string";
  ev3obj_type[TYPE_STR,EV3OBJ_TKEY_CLS]=CLASS_SCAL;

  # number
  ev3obj_type[TYPE_NUM]="number";
  ev3obj_type[TYPE_NUM,EV3OBJ_TKEY_CLS]=CLASS_SCAL;

  # bool
  ev3obj_type[TYPE_BOOL]="boolean";
  ev3obj_type[TYPE_BOOL,EV3OBJ_TKEY_CLS]=CLASS_SCAL;

  # reference
  ev3obj_type[TYPE_REF]="reference";
  ev3obj_type[TYPE_REF,EV3OBJ_TKEY_CLS]=CLASS_SCAL;

  # object
  ev3obj_type[TYPE_OBJ]="object";
  ev3obj_type[TYPE_OBJ,EV3OBJ_TKEY_CLS]=CLASS_BYREF;

  #----------------------------------------------------------------------------
  # ev3proto

  TYPE_PROP=ev3obj_type_define("ev3proto_property",CLASS_STRUCT);
  ev3obj_structType_defineMember(TYPE_PROP,"getter");
  ev3obj_structType_defineMember(TYPE_PROP,"setter");

  TYPE_NFUNC=ev3obj_type_define("ev3proto_native_function",CLASS_SCAL);

  TYPE_XFUNC=ev3obj_type_define("ev3proto_lambda_function",CLASS_STRUCT);
  ev3obj_structType_defineMember(TYPE_XFUNC,"[[Expr]]");
  ev3obj_structType_defineMember(TYPE_XFUNC,"[[Scope]]");
  
  # EV3_MT_UNKNOWN  =0;
  # EV3_MT_INVALID  =1;
  # EV3_MT_UNDEFINED=2;
  # EV3_MT_DEFINED  =3
  # EV3_MT_ACCESSOR =4;
}

function ev3obj_type_define(name,cls, _typeid){
  _typeid=ev3obj_type_index++;
  ev3obj_type[_typeid]=name;
  ev3obj_type[_typeid,EV3OBJ_TKEY_CLS]=cls;
  return _typeid;
}
function ev3obj_structType_defineMember(typeid,memberName, _mindex){
  _mindex=ev3obj_type[typeid,UKEY_MEM_CNT]++;
  ev3obj_type[typeid,UKEY_MEM_KEY,_mindex]=memberName;
  ev3obj_type[typeid,UKEY_MEM_ORD,memberName]=_mindex;
}
function ev3obj_enumType_defineName(typeid,name,value){
  if(value==NULL)
    value=ev3obj_type[typeid,EV3OBJ_TKEY_ENU_CNT]+1;
  ev3obj_type[typeid,EV3OBJ_TKEY_ENU_NAM,value]=name;
  ev3obj_type[typeid,EV3OBJ_TKEY_ENU_VAL,name]=value;
  ev3obj_type[typeid,EV3OBJ_TKEY_ENU_CNT]=value;
  return value;
}
function ev3obj_enumType_getName(typeid,value,defaultValue, _key){
  _key=typeid SUBSEP EV3OBJ_TKEY_ENU_NAM SUBSEP value;
  if(_key in ev3obj_type)return ev3obj_type[_key];
  return defaultValue;
}

function ev3obj_univ_print(_i,_n,_keys, _table,_kroot,_k,_managed){
  print "ev3obj_universe = {"
  _n=asorti(ev3obj_universe,_keys);
  for(_i=1;_i<=_n;_i++){
    _k=_keys[_i];

    _kroot=_k;
    sub("[" SUBSEP "].*$","",_kroot);

    if(!(_kroot in _table)){
      _table[_kroot,UKEY_REF]=1;
      _managed=(_kroot SUBSEP UKEY_REF in ev3obj_universe);
      if(_kroot SUBSEP UKEY_TYP in ev3obj_universe){
        _line=_ev3obj_dump_impl(_kroot,_table);
        gsub(/\n/,"\n  ",_line);
        print "  " (_managed?"m":"u") " "  _kroot " = " _line ",";
      }
    }

    if(!(_k in _table)){
      # _managed=(_k==_kroot SUBSEP UKEY_REF)
      print "  [1;31md[m " _k " = " ev3obj_universe[_k] ",";
    }
  }
  print "};"
}
function ev3obj_univ(key, defaultValue){
  if(key in ev3obj_universe)
    return ev3obj_universe[key];
  else
    return defaultValue;
}
function _ev3obj_create( _ptr){
  _ptr="#" ev3obj_index++;
  while(_ptr SUBSEP UKEY_REF in ev3obj_universe)_ptr="#" ev3obj_index++;
  ev3obj_universe[_ptr,UKEY_REF]=1;
  ev3obj_universe[_ptr,UKEY_TYP]=TYPE_NULL; # unknown
  return _ptr;
}
function _ev3obj_destruct(ptr ,_type,_cls,_iN,_i,_key,_memptr){
  _type=ev3obj_univ(ptr SUBSEP UKEY_TYP);
  if(_type=="")return;

  _cls=ev3obj_type[_type,EV3OBJ_TKEY_CLS];
  if(_cls==CLASS_BYREF){
    # delete members
    _iN=ev3obj_universe[ptr,UKEY_MEM_CNT];
    delete ev3obj_universe[ptr,UKEY_MEM_CNT];
    for(_i=0;_i<_iN;_i++){
      _key=ev3obj_universe[ptr,UKEY_MEM_KEY,_i];
      delete ev3obj_universe[ptr,UKEY_MEM_KEY,_i];
      delete ev3obj_universe[ptr,UKEY_MEM_ORD,_key];
      _ev3obj_destruct(ptr SUBSEP UKEY_MEM SUBSEP _key);
    }

    # UKEY_PROTO
    _memptr=ptr SUBSEP UKEY_PROTO;
    if(_memptr in ev3obj_universe){
      _ev3obj_destruct(_memptr);
      delete ev3obj_universe[_memptr];
    }
  }else if(_cls==CLASS_SCAL){
    # remove reference
    if(ev3obj_universe[ptr,UKEY_TYP]==TYPE_REF)
      _ev3obj_dec(ev3obj_universe[ptr]);

  }else if(_cls==CLASS_STRUCT){
    # delete members
    _type=ev3obj_universe[ptr,UKEY_TYP];
    _iN=ev3obj_type[_type,UKEY_MEM_CNT];
    for(_i=0;_i<_iN;_i++){
      _key=ev3obj_type[_type,UKEY_MEM_KEY,_i];
      _ev3obj_destruct(ptr SUBSEP UKEY_MEM SUBSEP _key);
    }
  }

  delete ev3obj_universe[ptr];
  delete ev3obj_universe[ptr,UKEY_TYP];
}
function _ev3obj_dec(ptr, _kref){
  sub(ev3obj_rex_subkey,"",ptr);
  _kref=ptr SUBSEP UKEY_REF;
  if(!(_kref in ev3obj_universe)||ev3obj_universe[_kref]<=0){
    _ev3_assert(FALSE,"BUG (_ev3obj_dec)","decrementing the reference count of an invalid pointer (ptr = " ev3obj_dump(ptr) ")");
    return;
  }
  if(--ev3obj_universe[_kref]<=0){
    _ev3obj_destruct(ptr);
    delete ev3obj_universe[_kref];
  }
}
function _ev3obj_inc(ptr, _kref){
  sub(ev3obj_rex_subkey,"",ptr);
  _kref=ptr SUBSEP UKEY_REF;
  if(!(_kref in ev3obj_universe)||ev3obj_universe[_kref]<=0){
    _ev3_assert(FALSE,"BUG (_ev3obj_inc)","incrementing the reference count of an invalid pointer (ptr = " ev3obj_dump(ptr) ")");
    return;
  }
  ++ev3obj_universe[_kref];
}

# function ev3obj_checkIfRoot(obj){
#   if(ev3obj_univ(obj SUBSEP UKEY_REF)<=0){
#     _ev3obj_error("obj <" obj "> is nullptr");
#     return 0;
#   }
#   return 1;
# }
# function ev3obj_checkNonNull(obj){
#   if(ev3obj_univ(obj SUBSEP UKEY_TYP)==""){
#     _ev3obj_error("obj <" obj "> is nullptr");
#     return 0;
#   }
#   return 1;
# }
# function ev3obj_checkByRef(obj){
#   if(ev3obj_univ(obj SUBSEP UKEY_TYP)!=CLASS_BYREF){
#     _ev3obj_error("not byref object");
#     return 0;
#   }
#   return 1;
# }

# 強制代入(チェック無し)
function ev3obj_assignScal(dst,type,value, _i,_iN,_key){
  # manage reference count
  if(type==TYPE_REF)_ev3obj_inc(value);
  _ev3obj_destruct(dst);

  if(type==TYPE_NULL){
    ev3obj_universe[dst,UKEY_TYP]=TYPE_NULL;
  }else{
    ev3obj_universe[dst,UKEY_TYP]=type;
    ev3obj_universe[dst]=value;

    # # null で埋める (不要)
    # if(ev3obj_type[type,EV3OBJ_TKEY_CLS]==CLASS_STRUCT){
    #   _iN=ev3obj_type[type,UKEY_MEM_CNT];
    #   for(_i=0;_i<_iN;_i++){
    #     _key=ev3obj_type[type,UKEY_MEM_KEY,_i];
    #     ev3obj_universe[dst,UKEY_MEM,_key,UKEY_TYP]=TYPE_NULL;
    #   }
    # }
  }
}
# 強制代入(チェック無し)
function ev3obj_assignObj(dst,src, _cls,_type,_i,_iN,_key){
  _type=ev3obj_univ(src SUBSEP UKEY_TYP);
  _cls=ev3obj_type[_type,EV3OBJ_TKEY_CLS];
  if(_cls==CLASS_SCAL){
    ev3obj_assignScal(dst,ev3obj_universe[src,UKEY_TYP],ev3obj_universe[src]);
  }else if(_cls==CLASS_STRUCT){
    _ev3obj_destruct(dst);

    ev3obj_universe[dst,UKEY_TYP]=_type;
    _iN=ev3obj_type[_type,UKEY_MEM_CNT];
    for(_i=0;_i<_iN;_i++){
      _key=ev3obj_type[_type,UKEY_MEM_KEY,_i];
      ev3obj_assignObj(dst SUBSEP UKEY_MEM SUBSEP _key,src SUBSEP UKEY_MEM SUBSEP _key);
    }
  }else if(_cls==CLASS_BYREF){
    ev3obj_assignScal(dst,TYPE_REF,src);
  }else if(_cls==CLASS_NULL||_cls==NULL){
    ev3obj_assignScal(dst,TYPE_NULL);
  }else{
    _ev3_assert(FALSE,"ev3obj_assignObj(obj = " ev3obj_dump(dst) ", src = " ev3obj_dump(src) ")","invalid EV3OBJ_TKEY_CLS of src.");
  }
}

#------------------------------------------------------------------------------
# 以下は不要 or もっと別の実装にするべきかもしれない。これは考えながら。

# function ev3obj_isMemberNameValid(obj,memberName, _mt){
#   #■checkMemberType は既存メンバの有無も確認するが、ここではそこまで必要ない
#   _mt=ev3obj_checkMemberType(obj,varname);
#   return !(_mt==EV3_MT_INVALID||_mt==EV3_MT_UNKNOWN);
# }

# function ev3obj_checkMemberType(obj,memberName, _type,_cls,_mindex){
#   if(!ev3obj_checkNonNull(obj))return;

#   _type=ev3obj_universe[obj,UKEY_TYP];
#   _cls=ev3obj_type[_type,EV3OBJ_TKEY_CLS];

#   # check/create member
#   if(_cls==CLASS_BYREF){
#     if(ev3obj_univ(obj SUBSEP UKEY_MEM_ORD SUBSEP memberName)!=NULL)
#       return EV3_MT_DEFINED;
#     else
#       return EV3_MT_UNDEFINED;
#   }else if(_cls==CLASS_STRUCT){
#     _mindex=ev3obj_type[_type,UKEY_MEM_ORD,memberName];
#     if(_mindex!=NULL)
#       return EV3_MT_DEFINED;
#     else
#       return EV3_MT_INVALID;
#   }else if(_cls==CLASS_SCAL||_cls==CLASS_NULL){
#     return EV3_MT_INVALID;
#   }else{
#     _ev3_assert(FALSE,"ev3obj_checkMemberType","unknown EV3OBJ_TKEY_CLS value");
#     return EV3_MT_UNKNOWN;
#   }
# }

function ev3obj_getMemberPtr(obj,memberName,creates, _type,_cls,_memptr,_mindex){
  if(!(obj SUBSEP UKEY_TYP in ev3obj_universe)){
    _ev3_error("ev3obj","ev3obj_getMemberPtr(obj = " obj ", memberName = '" memberName "', creates = " creates "), obj is undefined");
    return;
  }

  _memptr=obj SUBSEP UKEY_MEM SUBSEP memberName;
  if(_memptr SUBSEP UKEY_TYP in ev3obj_universe)return _memptr;

  _type=ev3obj_universe[obj,UKEY_TYP];
  _cls=ev3obj_type[_type,EV3OBJ_TKEY_CLS];
  if(_cls==CLASS_BYREF){
    if(obj SUBSEP UKEY_MEM_ORD SUBSEP memberName in ev3obj_universe)return _memptr;
    if(creates){
      _mindex=ev3obj_universe[obj,UKEY_MEM_CNT]++;
      ev3obj_universe[obj,UKEY_MEM_KEY,_mindex]=memberName;
      ev3obj_universe[obj,UKEY_MEM_ORD,memberName]=_mindex;
      ev3obj_universe[_memptr,UKEY_TYP]=TYPE_NULL;
      return _memptr;
    }else{
      _ev3obj_error("specified member '" memberName "' is not assigned.");
    }
  }else if(_cls==CLASS_STRUCT){
    if(_type SUBSEP UKEY_MEM_ORD SUBSEP memberName in ev3obj_type)return _memptr;
    _ev3obj_error("specified member '" memberName "' is not defined in type '" ev3obj_type[_type] "'.");
  }else if(_cls==CLASS_SCAL){
    _ev3obj_error("scalar value (" ev3obj_dump(obj) ") cannot have a member '" memberName "'.");
  }else{
    _ev3obj_error("unknown object class obj = " ev3obj_dump(obj) ", memberName = '" memberName "'.");
  }
}
function ev3obj_setMemberScal(obj,memberName,type,value, _memptr){
  _memptr=ev3obj_getMemberPtr(obj,memberName,TRUE);
  if(_memptr=="")return;
  ev3obj_assignScal(_memptr,type,value);
  return _memptr;
}
function ev3obj_setMemberObj(obj,memberName,ptr, _memptr){
  _memptr=ev3obj_getMemberPtr(obj,memberName,TRUE);
  if(_memptr=="")return;
  ev3obj_assignObj(_memptr,ptr);
  return _memptr;
}
function ev3obj_tryGetMemberValue(obj,memberName,defaultValue, _memptr){
  _memptr=obj SUBSEP UKEY_MEM SUBSEP memberName;
  if(_memptr in ev3obj_universe)return ev3obj_universe[_memptr];
  return defaultValue;
}
function ev3obj_getMemberValue(obj,memberName,unchecked, _memptr){
  # @opti2
  _memptr=obj SUBSEP UKEY_MEM SUBSEP memberName;
  if(_memptr in ev3obj_universe)return ev3obj_universe[_memptr];
  _memptr=ev3obj_getMemberPtr(obj,memberName,FALSE);
  if(_memptr in ev3obj_universe)return ev3obj_universe[_memptr];
  return NULL;
  
  # # @opti1
  # _memptr=obj SUBSEP UKEY_MEM SUBSEP memberName;
  # if(_memptr SUBSEP UKEY_TYP in ev3obj_universe)
  #   return ev3obj_universe[_memptr];
  # ev3obj_getMemberPtr(obj,memberName,FALSE);
  # return NULL;

  # _memptr=ev3obj_getMemberPtr(obj,memberName,FALSE);
  # if(_memptr=="")return;
  # return ev3obj_univ(_memptr);
}
function ev3obj_unsetMember(obj,memberName, _type,_ord,_count,_tkey,_memptr){
  _type=ev3obj_universe[obj,UKEY_TYP];
  if(ev3obj_type[_type,EV3OBJ_TKEY_CLS]==CLASS_BYREF){
    _ord=ev3obj_univ(obj SUBSEP UKEY_MEM_ORD SUBSEP memberName);
    if(_ord!=NULL){
      _count=ev3obj_universe[obj,UKEY_MEM_CNT];
      if(_ord!=_count-1){
        _tkey=ev3obj_universe[obj,UKEY_MEM_KEY,_count-1];
        ev3obj_universe[obj,UKEY_MEM_KEY,_ord ]=_tkey;
        ev3obj_universe[obj,UKEY_MEM_ORD,_tkey]=_ord ;
      }
      _ev3obj_destruct(obj SUBSEP UKEY_MEM SUBSEP memberName);
      delete ev3obj_universe[obj,UKEY_MEM_ORD,memberName];
      delete ev3obj_universe[obj,UKEY_MEM_KEY,_count-1];
      ev3obj_universe[obj,UKEY_MEM_CNT]=_count-1;
    }
  }else{
    _memptr=ev3obj_getMemberPtr(obj,memberName,FALSE);
    if(_memptr=="")return;
    _ev3obj_destruct(_memptr);
  }
}

function ev3obj_new(obj, _ret){
  _ret=_ev3obj_create();
  if(obj!=NULL)
    ev3obj_assignObj(_ret,obj);
  else
    ev3obj_universe[_ret,UKEY_TYP]=TYPE_OBJ;
  return _ret;
}
function ev3obj_new_scal(type,value, _obj){
  _obj=_ev3obj_create();
  ev3obj_assignScal(_obj,type,value);
  return _obj;
}

function ev3obj_placementNew(obj,memberName,rhs, _memptr,_ret){
  _memptr=ev3obj_getMemberPtr(obj,memberName,TRUE);
  if(_memptr==NULL)return;

  _ret=_ev3obj_create();
  if(rhs!=NULL)
    ev3obj_assignObj(_ret,rhs);
  else
    ev3obj_universe[_ret,UKEY_TYP]=TYPE_OBJ;

  ev3obj_assignScal(_memptr,TYPE_REF,_ret);
  ev3obj_release(_ret);
  return _ret;
}

function ev3obj_delete(obj){
  _ev3obj_destruct(obj);
  _ev3obj_dec(obj);
}
function ev3obj_capture(obj){
  _ev3obj_inc(obj);
}
function ev3obj_release(obj){
  _ev3obj_dec(obj);
}

function ev3obj_toString(obj, _type,_cls,_value,_name){
  if(!(obj SUBSEP UKEY_TYP in ev3obj_universe))return "undefined";

  _type=ev3obj_universe[obj,UKEY_TYP];
  _cls=ev3obj_type[_type,EV3OBJ_TKEY_CLS];
  if(_cls==CLASS_NULL){
    #print "1," _type "," _cls "," CLASS_NULL;
    return "null";
  }else if(_cls==CLASS_SCAL){
    if(_type==TYPE_REF){
      _value=ev3obj_universe[obj];
      return "[object]"
      # if(ev3obj_univ(_value SUBSEP UKEY_TYP)==TYPE_REF){
      #   return "[reference]";
      # }else{
      #   return ev3obj_toString(_value);
      # }
    }else if(_type==TYPE_NUM||_type==TYPE_STR)
      return "" ev3obj_universe[obj];
    else if(_type==TYPE_BOOL)
      return ev3obj_universe[obj]?"true":"false";
    else{
      _value=ev3obj_universe[obj];
      _name=ev3obj_enumType_getName(_type,_value);
      return "" (_name!=NULL?_name:_value);
    }
  }else if(_cls==CLASS_STRUCT){
    return "[struct]";
  }else if(_cls==CLASS_BYREF){
    return "[object data]";
  }else{
    return "[unknown]";
  }
}
function _ev3obj_dump_impl(obj, __table,_type,_cls,_iN,_i,_key,_memptr,_ret,_value,_content,_typename,_enumName){
  __table[obj]=1;
  __table[obj,UKEY_TYP]=1;
  __table[obj,UKEY_REF]=1;
  _type=ev3obj_univ(obj SUBSEP UKEY_TYP);
  if(_type=="")return "undefined";

  _cls=ev3obj_type[_type,EV3OBJ_TKEY_CLS];
  if(_cls==CLASS_NULL)
    return "null";
  else if(_cls==CLASS_SCAL){
    if(_type==TYPE_STR)
      return "\"" ev3obj_universe[obj] "\" : string";
    else if(_type==TYPE_REF){
      _value=ev3obj_universe[obj];
      if(__table[_value])
        return _value " : reference -> ...";
      else{
        _content=_ev3obj_dump_impl(_value,__table);
        gsub(/\n/,"\n  ",_content);
        return _value " : reference -> " _content;
      }
    }else{
      # TODO: toString を使用?
      _typename=ev3obj_type[_type];
      if(_typename==NULL)_typename="unknown";

      _value=ev3obj_toString(obj);
      # _value=ev3obj_universe[obj];
      # # enum name
      # _enumName=ev3obj_enumType_getName(_type,_value);
      # if(_enumName!=NULL)
      #   _value=_enumName; # " (" _value ")";
      
      return _value " : " _typename;
    }
  }else if(_cls==CLASS_STRUCT){
    _ret="{ "
    _iN=ev3obj_type[_type,UKEY_MEM_CNT];
    for(_i=0;_i<_iN;_i++){
      _key=ev3obj_type[_type,UKEY_MEM_KEY,_i];
      _ret=_ret _key " = " _ev3obj_dump_impl(obj SUBSEP UKEY_MEM SUBSEP _key,__table) ", ";
    }
    _ret=_ret "} : " ev3obj_type[_type];
    return _ret;

  }else if(_cls==CLASS_BYREF){
    __table[obj,UKEY_MEM_CNT]=1;
    _iN=ev3obj_universe[obj,UKEY_MEM_CNT];
    if(_iN==0){
      _ret="{} : object";
    }else{
      _ret="{\n";
      for(_i=0;_i<_iN;_i++){
        _key=ev3obj_universe[obj,UKEY_MEM_KEY,_i];
        _ret=_ret "  " _key " = " _ev3obj_dump_impl(obj SUBSEP UKEY_MEM SUBSEP _key,__table) ",\n";
        __table[obj,UKEY_MEM_KEY,_i]=1;
        __table[obj,UKEY_MEM_ORD,_key]=1;
      }
      _ret=_ret "} : object";
    }

    # __proto__ (あれば)
    if(obj SUBSEP UKEY_PROTO in ev3obj_universe){
      __table[obj,UKEY_PROTO]=1;
      __table[obj,UKEY_PROTO,UKEY_TYP]=1;
      _value=ev3obj_universe[obj,UKEY_PROTO];
      if(_value!=NULL)
        _ret=_ret " @ [[proto = " _value "]] -> " (__table[_value]?"...":_ev3obj_dump_impl(_value,__table));
    }

    return _ret;
  }else
    return "<dangle> (invalid)";
}
function ev3obj_dump(obj){
  return obj " -/-> " _ev3obj_dump_impl(obj);
}

#------------------------------------------------------------------------------
# ev3obj_proto
#
# 以下を考慮に入れたプロパティを取得・設定する仕組み
# 1 prototype chain を辿った探索
# 2 (定義されていれば) getter/setter を用いた処理
#

function ev3proto_initialize(){
  ev3proto_world=ev3obj_new();

  ev3obj_default_proto=ev3obj_placementNew(ev3proto_world,"default.prototype");
  ev3obj_setMemberScal(ev3obj_default_proto,"+toString",TYPE_NFUNC,"default#toString");
}
function ev3proto_finalize(){
  ev3obj_delete(ev3proto_world);
}

# dst = obj.fun(args...) を実行する
function ev3proto_callFunction(dst,obj,fun,args, _ftype,_fapply,_args2,_ret){
  #print "dbg201411-3: dst = " ev3obj_dump(dst) " , obj = " ev3obj_dump(obj) ", fun = " ev3obj_dump(fun) ", args = " ev3obj_dump(args);

  if(!(fun SUBSEP UKEY_TYP in ev3obj_universe)){
    _ev3_error("ev3eval (funcation-call)","undefined function object.");
    return;
  }
  _ftype=ev3obj_universe[fun,UKEY_TYP];

  # fun = reference -> dereference
  if(_ftype==TYPE_REF)
    return ev3proto_callFunction(dst,obj,ev3obj_universe[fun],args);

  # fun = native function -> native call
  ev3obj_assignScal(dst,TYPE_NULL);
  if(_ftype==TYPE_NFUNC)
    return ev3eval_nativeFunction_call(dst,obj,ev3obj_universe[fun],args);

  # fun = object -> call operator()
  _fapply=ev3obj_new();
  if(ev3proto_getProperty(fun,"!()",_fapply)){
    # eval("fun.operator()(obj,args)")
    _args2=ev3obj_new();
    ev3obj_setMemberScal(_args2,"+length",TYPE_NUM,2);
    ev3obj_setMemberObj(_args2,"+0",obj);
    ev3obj_setMemberObj(_args2,"+1",args);
    _ret=ev3proto_callFunction(dst,fun,_fapply,_args2);

    ev3obj_release(_args2);
    ev3obj_release(_fapply);
    return _ret;
  }
  ev3obj_release(_fapply);

  _ev3_error("ev3eval (function-call)","the object (" ev3obj_dump(fun) ") is not a valid function");
  return;
}

#
# ev3proto_getProperty
#
BEGIN{
  EV3PROTO_ACCESS_MODE_VALUE=0;
  EV3PROTO_ACCESS_MODE_SETTER=1;
  EV3PROTO_ACCESS_MODE_OWNER=2;
}
function _ev3proto_accessProperty_apply(obj,proto,memberName,arg,memptr){
  if(local_access_mode==EV3PROTO_ACCESS_MODE_VALUE){
    # getter - get value
    #print "dbg201411: get memptr = " ev3obj_dump(memptr) ", arg = " arg;
    ev3obj_assignObj(arg,memptr);
    return TRUE;
  }else if(local_access_mode==EV3PROTO_ACCESS_MODE_SETTER){
    # setter - get setter
    if(ev3obj_universe[memptr,UKEY_TYP]==TYPE_PROP)
      return memptr SUBSEP UKEY_MEM SUBSEP "setter";
    return NULL;
  }else if(local_access_mode==EV3PROTO_ACCESS_MODE_OWNER){
    return proto;
  }

  _ev3_error("ev3proto (ev3proto_accessProperty)","BUG: unknown access mode = " local_access_mode ".");
  return NULL;
}
function _ev3proto_accessProperty_recurse(obj,proto,memberName,arg, _type,_cls,_member,_getter,_args,_proto){
  # print "dbg201411: proto = " ev3obj_dump(proto) ", memberName = " memberName;
  _type=ev3obj_univ(proto SUBSEP UKEY_TYP);
  if(_type==TYPE_REF)
    return _ev3proto_accessProperty_recurse(obj,ev3obj_universe[proto],memberName,arg);

  _cls=ev3obj_type[_type,EV3OBJ_TKEY_CLS];
  if(_cls==CLASS_STRUCT){
    if(_type SUBSEP UKEY_MEM_ORD SUBSEP memberName in ev3obj_type){
      return _ev3proto_accessProperty_apply(obj,proto,memberName,arg,proto SUBSEP UKEY_MEM SUBSEP memberName);
    }
  }else if(_cls==CLASS_BYREF){
    # if(local_access_mode==EV3PROTO_ACCESS_MODE_OWNER&&proto==ev3eval_ctx_root)return proto;

    if(proto SUBSEP UKEY_MEM_ORD SUBSEP "!." in ev3obj_universe){
      return _ev3proto_accessProperty_apply(obj,proto,memberName,arg,proto SUBSEP UKEY_MEM SUBSEP "!.");
    }

    if(proto SUBSEP UKEY_MEM_ORD SUBSEP memberName in ev3obj_universe){
      return _ev3proto_accessProperty_apply(obj,proto,memberName,arg,proto SUBSEP UKEY_MEM SUBSEP memberName);
    }

    _proto=ev3obj_universe[proto,UKEY_PROTO];
    if(_proto!=NULL)return _ev3proto_accessProperty_recurse(obj,_proto,memberName,arg);
  }

  # 型proto
  _proto=ev3obj_type[_type,UKEY_PROTO];
  if(_proto!=NULL)return _ev3proto_accessProperty_recurse(obj,_proto,memberName,arg);

  if(proto!=ev3obj_default_proto){
    _proto=ev3obj_default_proto;
    if(_proto!=NULL)return _ev3proto_accessProperty_recurse(obj,_proto,memberName,arg);
  }

  if(local_access_mode==EV3PROTO_ACCESS_MODE_VALUE){
    ev3obj_assignScal(arg,TYPE_NULL);
  }
  return NULL;
}
function ev3proto_accessProperty(access_mode,obj,memberName,arg, _old_access_mode,_ret){
  _old_access_mode=local_access_mode;
  local_access_mode=access_mode;
  _ret=_ev3proto_accessProperty_recurse(obj,obj,memberName,arg);
  local_access_mode=_old_access_mode;
  return _ret;
}
function ev3proto_getProperty(obj,memberName,dst, _type,_member,_getter,_args){
  #print "dbg201411: obj = " ev3obj_dump(obj) ", memberName = " memberName;

  _type=ev3obj_univ(obj SUBSEP UKEY_TYP);
  if(_type==NULL||_type==CLASS_NULL){
    ev3obj_assignScal(dst,TYPE_NULL);
    return FALSE;
  }

  _ev3_assert(dst!=NULL,"ev3proto_getProperty(obj,memberName,dst)","dst is NULL, which should not be NULL.");
  if(ev3proto_accessProperty(EV3PROTO_ACCESS_MODE_VALUE,obj,memberName,dst)==NULL)
    return FALSE;

  if(ev3obj_universe[dst,UKEY_TYP]==TYPE_PROP){
    if(memberName ~ /^\+/){
      _getter=dst SUBSEP UKEY_MEM SUBSEP "getter";
      if(_getter SUBSEP UKEY_TYP in ev3obj_universe){
        #■配列
        _args=ev3obj_new();
        ev3obj_setMemberScal(_args,"+length",TYPE_NUM,1);
        ev3obj_setMemberScal(_args,"+0",TYPE_STR,substr(memberName,2));
        ev3proto_callFunction(dst,obj,_getter,_args);
        ev3obj_release(_args);
        return TRUE;
      }
    }
    return FALSE;
  }

  return TRUE;
}
# プロパティまたはメンバが実際に定義されている場所を取得します。
function ev3proto_getVariableOwner(obj,memberName){
  return ev3proto_accessProperty(EV3PROTO_ACCESS_MODE_OWNER,obj,memberName);
}
#
# ev3proto_setProperty
#
function ev3proto_setProperty(obj,memberName,src, _setter,_args){
  # print "dbg201411-1: obj = " ev3obj_dump(obj) ", memberName = '" memberName "', src = " ev3obj_dump(src);
  if(ev3obj_univ(obj SUBSEP UKEY_TYP)==TYPE_REF)
    return ev3proto_setProperty(ev3obj_universe[obj],memberName,src);

  # setter が見付かれば setter を使う
  if(memberName ~ /^\+/){
    _setter=ev3proto_accessProperty(EV3PROTO_ACCESS_MODE_SETTER,obj,memberName);
    if(_setter!=NULL){
      #■配列
      _args=ev3obj_new();
      ev3obj_setMemberScal(_args,"+length",TYPE_NUM,2);
      ev3obj_setMemberScal(_args,"+0",TYPE_STR,substr(memberName,2));
      ev3obj_setMemberObj(_args,"+1",src);
      ev3proto_callFunction(dst,obj,_setter,_args);
      ev3obj_release(_args);
      return TRUE;
    }
  }
  
  # setter がなければ直接書き込む。
  ev3obj_setMemberObj(obj,memberName,src);
}
function ev3proto_setPropertyScal(obj,memberName,type,value, _setter,_args){
  if(ev3obj_univ(obj SUBSEP UKEY_TYP)==TYPE_REF)
    return ev3proto_setPropertyScal(ev3obj_universe[obj],memberName,type,value);

  # setter が見付かれば setter を使う
  if(memberName ~ /^\+/){
    _setter=ev3proto_accessProperty(EV3PROTO_ACCESS_MODE_SETTER,obj,memberName);
    if(_setter!=NULL){
      #■配列
      _args=ev3obj_new();
      ev3obj_setMemberScal(_args,"+length",TYPE_NUM,2);
      ev3obj_setMemberScal(_args,"+0",TYPE_STR,substr(memberName,2));
      ev3obj_setMemberScal(_args,"+1",type,value);
      ev3proto_callFunction(dst,obj,_setter,_args);
      ev3obj_release(_args);
      return TRUE;
    }
  }
  
  # setter がなければ直接書き込む。
  ev3obj_setMemberScal(obj,memberName,type,value);
}

#
# _ev3proto_isPropertyNameValid_recurse
#
function _ev3proto_isPropertyNameValid_recurse(obj,proto,memberName,_proto){
  _type=ev3obj_univ(proto SUBSEP UKEY_TYP);
  if(_type==NULL||_type==TYPE_NULL)return FALSE;
  if(_type==TYPE_REF)
    return _ev3proto_isPropertyNameValid_recurse(obj,ev3obj_universe[proto],memberName);

  _cls=ev3obj_type[_type,EV3OBJ_TKEY_CLS];
  if(_cls==CLASS_STRUCT){
    if(_type SUBSEP UKEY_MEM_ORD SUBSEP memberName in ev3obj_type)return TRUE;
  }else if(_cls==CLASS_BYREF){
    # 自身が BYREF ならいつでもOK。
    # この判定の為に TYPE_REF obj の間接参照が済んでいる必要がある (→ev3proto_isPropertyNameValidで処理)。
    if(obj==proto)return TRUE;

    # メンバアクセス演算子がこの __proto__ chain link で定義されていれば OK
    if(proto SUBSEP UKEY_MEM_ORD SUBSEP "![]" in ev3obj_universe)return TRUE;

    # この __proto__ chain link にメンバ値 or メンバアクセサが定義されていれば OK
    if(proto SUBSEP UKEY_MEM_ORD SUBSEP memberName in ev3obj_universe)return TRUE;

    # 次の __proto__ chain link
    _proto=ev3obj_universe[proto,UKEY_PROTO];
    if(_proto!=NULL)
      return _ev3proto_isPropertyNameValid_recurse(obj,_proto,memberName);
  }

  # 型proto
  _proto=ev3obj_type[_type,UKEY_PROTO];
  if(_proto!=NULL)
    return _ev3proto_isPropertyNameValid_recurse(obj,_proto,memberName);

  if(proto!=ev3obj_default_proto){
    _proto=ev3obj_default_proto;
    if(_proto!=NULL)
      return _ev3proto_isPropertyNameValid_recurse(obj,_proto,memberName);
  }

  # print "dbgdbg201411: memberName = " memberName;
  # print "dbgdbg201411: ev3obj_default_proto = " ev3obj_dump(ev3obj_default_proto);
  return FALSE;
}
function ev3proto_isPropertyNameValid(obj,memberName){
  if(ev3obj_univ(obj SUBSEP UKEY_TYP)==TYPE_REF)
    return ev3proto_isPropertyNameValid(ev3obj_universe[obj],memberName);

  return _ev3proto_isPropertyNameValid_recurse(obj,obj,memberName);
}

function dbg_obj1(){
  o1=ev3obj_new();
  ev3obj_setMemberScal(o1,"test1",TYPE_STR,"hello");
  ev3obj_setMemberScal(o1,"test2",TYPE_STR,"world");
  ev3obj_setMemberObj(o1,"test3",o1); # 循環参照
  ev3obj_setMemberObj(o1,"test4",o1 SUBSEP UKEY_MEM SUBSEP "test1");

  # CLASS_STRUCT の構築とコピー
  ev3obj_setMemberScal(o1,"memberAccess",TYPE_NULL);
  {
    ev3obj_universe[o1,UKEY_MEM,"memberAccess",UKEY_TYP]=EV3_TYPE_LVALUE;
    ev3obj_setMemberScal(o1 SUBSEP UKEY_MEM SUBSEP "memberAccess","obj",TYPE_REF,o1);
    ev3obj_setMemberScal(o1 SUBSEP UKEY_MEM SUBSEP "memberAccess","memberName",TYPE_STR,"test2");
  }
  ev3obj_setMemberObj(o1,"m1",o1 SUBSEP UKEY_MEM SUBSEP "memberAccess");

  # TYPE_REF 設定
  {
    o2=ev3obj_new();
    ev3obj_setMemberObj(o1,"o2",o2);
    ev3obj_setMemberScal(o2,"hoge",TYPE_STR,"hello world");
    ev3obj_setMemberScal(o2,"fuga",TYPE_STR,"good night");
    ev3obj_release(o2);
  }

  print ev3obj_dump(o1);

  print "o1.test3=" ev3obj_getMemberValue(o1,"test3");
  print "o1.test3.test1=" ev3obj_getMemberValue(ev3obj_getMemberValue(o1,"test3"),"test1");
  ev3obj_delete(o1);

  ev3obj_univ_print();
}

#==============================================================================
# Scan

function ev3scan_init_operator(opname,optype,opprec,flags){
  ev3scan_op[opname]=optype;
  ev3scan_op[opname,EV3_OPKEY_RPREC]=opprec;
  ev3scan_op[opname,EV3_OPKEY_LPREC]=opprec;
  if(index(flags,"r")>=1){
    # right associativity
    ev3scan_op[opname,EV3_OPKEY_LPREC]+=0.01;
  }
}

function ev3scan_initialize(){
  EV3_WKEY_WTYP="o";
  EV3_WKEY_WORD="w";
  EV3_WKEY_OTYP="t";
  EV3_WKEY_FLAG="f";

  # 以下は eval の最中に現れる型で rvalue の際に必ず dereference される。
  # つまり、実際のオブジェクトの値として代入・設定される事はない。
  #
  # EV3_TYPE_VREF 変数への参照 (実体: 変数名)
  # EV3_TYPE_LREF 直接の左辺値 (実体: ev3obj_universe の key)
  #   これは TYPE_REF とは異なる事に注意 (rvalue 取得時に間接参照になる)。
  # EV3_TYPE_MREF メンバ型 (参照 & メンバ名)
  #EV3_TYPE_VREF=ev3obj_type_define("ev3eval_variable",CLASS_SCAL);
  #EV3_TYPE_LREF=ev3obj_type_define("ev3eval_lvalue",CLASS_SCAL);
  # EV3_TYPE_MREF=ev3obj_type_define("ev3eval_mref",CLASS_STRUCT);
  # ev3obj_structType_defineMember(EV3_TYPE_MREF,"obj");
  # ev3obj_structType_defineMember(EV3_TYPE_MREF,"memberName");

  EV3_TYPE_LVALUE=ev3obj_type_define("ev3eval_lvalue",CLASS_STRUCT);
  ev3obj_structType_defineMember(EV3_TYPE_LVALUE,"obj");
  ev3obj_structType_defineMember(EV3_TYPE_LVALUE,"memberName");
  ev3obj_structType_defineMember(EV3_TYPE_LVALUE,"rvalue");

  # literals
  EV3_TYPE_XT=ev3obj_type_define("ev3parse_xtype",CLASS_SCAL);
  EV3_WT_BIN =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_BIN",1);
  EV3_WT_UNA =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_UNA",2); # prefix          
  EV3_WT_SGN =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_SGN",3); # prefix or binary
  EV3_WT_INC =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_INC",4); # prefix or suffix
  EV3_WT_OPN =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_OPN",5); # left bracket
  EV3_WT_CLS =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_CLS",6); # right bracket
  EV3_WT_SNT =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_SNT"); # ; semicolon
  EV3_WT_PPR =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_PPR"); # PPREF (if/for/while/switch/catch)

  EV3_WT_VAL =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_VAL");
  EV3_WT_NAME=ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_WT_NAME"); # identifier

  EV3_XT_ARR =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_XT_ARR");
  EV3_XT_TRI =ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_XT_TRI");
  EV3_XT_CALL=ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_XT_CALL");
  EV3_XT_VOID=ev3obj_enumType_defineName(EV3_TYPE_XT,"EV3_XT_VOID");

  ev3scan_escchar_table["n"]="\n";
  ev3scan_escchar_table["r"]="\r";
  ev3scan_escchar_table["t"]="\t";
  ev3scan_escchar_table["v"]="\v";
  ev3scan_escchar_table["f"]="\f";
  ev3scan_escchar_table["a"]="\a";
  ev3scan_escchar_table["e"]="\33";
  ev3scan_escchar_table["b"]="\b";

  # operators
  EV3_OPKEY_RPREC=">";
  EV3_OPKEY_LPREC="<";

  # if(cond)(); は if((cond)()) ではなく (if(cond))() と解釈されるべき
  # if().hello; は if((cond).hello) ではなく (if(cond))(.hello) (error)と解釈されるべき
  # if()::a; は if((cond)::hello) ではなく (if(cond))(::a) と解釈されるべき
  ev3scan_init_operator("if"    ,EV3_WT_PPR,14.0);
  ev3scan_init_operator("for"   ,EV3_WT_PPR,14.0);
  ev3scan_init_operator("switch",EV3_WT_PPR,14.0);
  ev3scan_init_operator("with"  ,EV3_WT_PPR,14.0);
  ev3scan_init_operator("while" ,EV3_WT_PPR,14.0); #■特殊 (doと結合)
  ev3scan_init_operator("catch" ,EV3_WT_PPR,14.0); #■特殊 (tryと結合)
  ev3scan_op["if()"    ,EV3_OPKEY_RPREC]=0.2; # ; よりは強いが他の何より弱い
  ev3scan_op["for()"   ,EV3_OPKEY_RPREC]=0.2;
  ev3scan_op["while()" ,EV3_OPKEY_RPREC]=0.2;
  ev3scan_op["switch()",EV3_OPKEY_RPREC]=0.2;
  ev3scan_init_operator("do"     ,EV3_WT_UNA,0.21);
  ev3scan_init_operator("try"    ,EV3_WT_UNA,0.21);
  ev3scan_init_operator("else"   ,EV3_WT_SNT,0.2,"r"); #■特殊 (ifと結合)
  ev3scan_init_operator("finally",EV3_WT_SNT,0.2,"r"); #■特殊 (tryと結合)

  ev3scan_init_operator("::",EV3_WT_SGN,13.0);
  ev3scan_op["u::",EV3_OPKEY_RPREC]=13.0;
  ev3scan_init_operator("." ,EV3_WT_BIN,12.0);
  ev3scan_init_operator("->",EV3_WT_BIN,12.0);

  ev3scan_init_operator("(" ,EV3_WT_OPN,12.0); # LPREC
  ev3scan_init_operator(")" ,EV3_WT_CLS);
  ev3scan_init_operator("[" ,EV3_WT_OPN,12.0); # LPREC
  ev3scan_init_operator("]" ,EV3_WT_CLS);
  ev3scan_init_operator("{" ,EV3_WT_OPN,12.0); # LPREC
  ev3scan_init_operator("}" ,EV3_WT_CLS);

  # 前置演算子
  #   ++ は右結合。つまり ++a++ は ++(a++) と解釈される。
  ev3scan_init_operator("++" ,EV3_WT_INC,11.0,"r"); # EV3_WT_INC/EV3_WT_UNA
  ev3scan_init_operator("--" ,EV3_WT_INC,11.0,"r"); # EV3_WT_INC/EV3_WT_UNA
  ev3scan_init_operator("!"  ,EV3_WT_UNA,11.0);
  ev3scan_init_operator("~"  ,EV3_WT_UNA,11.0);
  ev3scan_init_operator("new"       ,EV3_WT_UNA,11.0);
  ev3scan_init_operator("delete"    ,EV3_WT_UNA,11.0);
  ev3scan_init_operator("operator"  ,EV3_WT_UNA,11.0);
  ev3scan_op["u+",EV3_OPKEY_RPREC]=11.0;
  ev3scan_op["u-",EV3_OPKEY_RPREC]=11.0;
  ev3scan_op["u*",EV3_OPKEY_RPREC]=11.0;
  ev3scan_op["u&",EV3_OPKEY_RPREC]=11.0;

  ev3scan_init_operator(".*" ,EV3_WT_BIN,10.5);
  ev3scan_init_operator("->*",EV3_WT_BIN,10.5);

  # 算術二項演算子
  ev3scan_init_operator("*" ,EV3_WT_SGN,10.0);
  ev3scan_init_operator("/" ,EV3_WT_BIN,10.0);
  ev3scan_init_operator("%" ,EV3_WT_BIN,10.0);
  ev3scan_init_operator("+" ,EV3_WT_SGN,9.0); # 単項演算子の時は優先順位は 11.0 では?
  ev3scan_init_operator("-" ,EV3_WT_SGN,9.0); # 同上
  ev3scan_init_operator("<<",EV3_WT_BIN,8.0);
  ev3scan_init_operator(">>",EV3_WT_BIN,8.0);
  ev3scan_init_operator("*=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("/=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("%=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("+=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("-=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("<<=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator(">>=",EV3_WT_BIN,2.0,"r");

  # GCC 拡張 (最大最小演算子) の一般化
  ev3scan_init_operator("?<",EV3_WT_BIN,6.5);
  ev3scan_init_operator("<?",EV3_WT_BIN,6.5);
  ev3scan_init_operator("?>",EV3_WT_BIN,6.5);
  ev3scan_init_operator(">?",EV3_WT_BIN,6.5);
  ev3scan_init_operator("?<=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("<?=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("?>=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator(">?=",EV3_WT_BIN,2.0,"r");

  ev3scan_init_operator("instanceof",EV3_WT_BIN,6.2);
  ev3scan_init_operator("in"        ,EV3_WT_BIN,6.2);

  # 比較演算子
  ev3scan_init_operator("===",EV3_WT_BIN,6.0);
  ev3scan_init_operator("!==",EV3_WT_BIN,6.0);
  ev3scan_init_operator("==" ,EV3_WT_BIN,6.0);
  ev3scan_init_operator("!=" ,EV3_WT_BIN,6.0);
  ev3scan_init_operator("<"  ,EV3_WT_BIN,6.0);
  ev3scan_init_operator(">"  ,EV3_WT_BIN,6.0);
  ev3scan_init_operator("<=" ,EV3_WT_BIN,6.0);
  ev3scan_init_operator(">=" ,EV3_WT_BIN,6.0);

  # ビット二項演算子
  ev3scan_init_operator("&" ,EV3_WT_SGN,5.4);
  ev3scan_init_operator("^" ,EV3_WT_BIN,5.2);
  ev3scan_init_operator("|" ,EV3_WT_BIN,5.0);
  ev3scan_init_operator("|=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("^=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("&=",EV3_WT_BIN,2.0,"r");

  # 論理二項演算子
  ev3scan_init_operator("&&",EV3_WT_BIN,4.4);
  ev3scan_init_operator("||",EV3_WT_BIN,4.0);
  ev3scan_init_operator("&&=",EV3_WT_BIN,2.0,"r");
  ev3scan_init_operator("||=",EV3_WT_BIN,2.0,"r");

  # 三項演算子 "?:" の優先順位は "?" に保持する
  #   三項演算子は実は代入演算子と同じ? (代入演算子と同じ優先度かつ右結合)
  # label:hoge 等の二項演算子 ":" の優先順位は ":" に保持する
  #   ":" は、対応する "?" があれば閉じ括弧として処理→三項演算子に。
  #   "?" がなければ二項演算子として処理する。
  ev3scan_init_operator("?" ,EV3_WT_OPN,2.0,"r");
  ev3scan_init_operator(":" ,EV3_WT_CLS,1.2,"r"); #-> EV3_WT_CLS/EV3_WT_BIN
  # ※■■
  # : の優先順位は {a:b,c:d} では , よりも高いが、
  # switch(){case:;default:;} では , よりも低い。
  # また、for(i:range) でも , よりも低い方が自然である。
  # もしラベルを実装するとしたらやはり , よりも低い。

  # 代入演算子
  ev3scan_init_operator("=" ,EV3_WT_BIN,2.0,"r");
  
  # ラムダ
  ev3scan_init_operator("=>",EV3_WT_BIN,1.5);
  ev3scan_op["=>",EV3_OPKEY_LPREC]=12.01;

  ev3scan_init_operator("," ,EV3_WT_BIN,1.0);

  ev3scan_sentence_prec=0.0;
  ev3scan_init_operator(";" ,EV3_WT_SNT,0.0);

  # 制御構文の解釈について
  #   if(), switch(), try, do 等は "文" に対する prefix である。
  #   文は ; で区切られる。何もない所に ; が来たら 空文を生成する。
  #   [ 式 | ; ] -> [ 文(式文) ]
  #   [ 文 | 式 ] -> [ 文 式 ]
  #   [ '(' 文 ... | ')' ] -> [ 式(複式) ]
  #   [ '{' 文 ... | '}' ] -> [ 文(複文) ]
  #   [ 前置(for()) 式 | ';' ] -> [ 文(for文) ]
  #
  #   ',' の左優先度 > 文prefixの右優先度 > ';' の左優先度
  #   というか if(), switch() などは式を構成すると考えた方が良い?
  #   但し、else の前の ; を許す様にする必要がある。
  #   また、{} を引数に取る場合は ; で終端しなくても良い。
  #   if()式         ;
  #   if()式;else 式 ;
  #   if(){}


  EV3_TYPE_ST=ev3obj_type_define("ev3parse_stype",CLASS_SCAL);
  EV3_ST_NULL  =ev3obj_enumType_defineName(EV3_TYPE_ST,"EV3_ST_NULL" ,0);
  EV3_ST_PPREF =ev3obj_enumType_defineName(EV3_TYPE_ST,"EV3_ST_PPREF");  # prefix generating prefix
  EV3_ST_XPREF =ev3obj_enumType_defineName(EV3_TYPE_ST,"EV3_ST_XPREF");  # prefix generating expr
  EV3_ST_XPREF0=ev3obj_enumType_defineName(EV3_TYPE_ST,"EV3_ST_XPREF0"); # prefix generating expr
  EV3_ST_EXPR  =ev3obj_enumType_defineName(EV3_TYPE_ST,"EV3_ST_EXPR" );  # expression
  EV3_ST_MARK  =ev3obj_enumType_defineName(EV3_TYPE_ST,"EV3_ST_MARK" );  # mark, opening brackets
  EV3_ST_SENT  =ev3obj_enumType_defineName(EV3_TYPE_ST,"EV3_ST_SENT" );  # sentence
}
function ev3scan_finalize(){
}

function ev3scan(expression,words, _expr,_wlen,_w,_wt,_m,_value,_c,_i,_iN){
  _allow_regex=TRUE;
  _wlen=0;

  _expr=expression;
  while(length(_expr)>=1){
    if(match(_expr,/^([[:space:]]*\/\/[^\n]*($|\n)|\/\*([^*]\/?|\*)*\*\/[[:space:]]*)+[[:space:]]*|^[[:space:]]+/)>=1){
      # 空白・コメント (無視)
      _expr=substr(_expr,RLENGTH+1);
    }else if(match(_expr,/^(_|[^[:cntrl:][:blank:][:punct:][:digit:]])(_|[^[:cntrl:][:blank:][:punct:]])*/)>=1){
      # 識別子
      _w=substr(_expr,RSTART,RLENGTH);
      _expr=substr(_expr,RSTART+RLENGTH);

      if(_w=="true"||_w=="false"){
        words[_wlen,EV3_WKEY_WTYP]=EV3_WT_VAL;
        words[_wlen,EV3_WKEY_WORD]=_w=="true";
        words[_wlen,EV3_WKEY_OTYP]=TYPE_BOOL;
      }else if(_w=="null"){
        words[_wlen,EV3_WKEY_WTYP]=EV3_WT_VAL;
        words[_wlen,EV3_WKEY_WORD]=NULL;
        words[_wlen,EV3_WKEY_OTYP]=TYPE_NULL;
      }else{
        words[_wlen,EV3_WKEY_WTYP]=EV3_WT_NAME;
        words[_wlen,EV3_WKEY_WORD]=_w;
        if(_w in ev3scan_op)
          words[_wlen,EV3_WKEY_WTYP]=ev3scan_op[_w];
      }
      _wlen++;
      _allow_regex=(_w ~ /^(do|else|return|delete)$/);
      #■delete[] /aa/...; の場合は?
    }else if(match(_expr,/^0[xX][0-9a-fA-F]+|^([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][-+]?[0-9]+)?/)>=1){
      # 数値リテラル
      _w=substr(_expr,RSTART,RLENGTH);
      _expr=substr(_expr,RSTART+RLENGTH);
      words[_wlen,EV3_WKEY_WTYP]=EV3_WT_VAL;
      words[_wlen,EV3_WKEY_WORD]=strtonum(_w); #gawk
      words[_wlen,EV3_WKEY_OTYP]=TYPE_NUM;
      _wlen++;
      _allow_regex=FALSE;

      #■TODO: 末尾に変な物がついている時エラーにする or 拡張リテラル
    }else if(match(_expr,/^"(([^"\\]|\\.)*)"|^'(([^'\\]|\\.)*)'/,_m)>=1){
      # 文字列リテラル
      _w=substr(_expr,RSTART+1,RLENGTH-2);
      _expr=substr(_expr,RSTART+RLENGTH);

      _value="";
      while(length(_w)>=1){
        if(_w ~ /^\\/){
          if(match(_w,/^\\[nrtvfaeb]/)>=1){
            # \n \t
            _c=substr(_w,2,1);
            _w=substr(_w,RSTART+RLENGTH);
            if(ev3scan_escchar_table[_c]!="")
              _c=ev3scan_escchar_table[_c];
            _value=_value _c;
          }else if(match(_w,/^\\[xX][0-9a-fA-F]+|^\\[0-7]{1,3}/)>=1){
            # \xFFFF \064
            _c=substr(_w,RSTART+1,RLENGTH);
            _w=substr(_w,RSTART+RLENGTH);
            _value=_value sprintf("%c",strtonum("0" _c));
          }else if(match(_w,/^\\u[0-9a-fA-F]{1,4}|^\\U[0-9a-fA-F]{1,8}/)>=1){
            # \u1234 \U12345678
            _c=substr(_w,RSTART+2,RLENGTH);
            _w=substr(_w,RSTART+RLENGTH);
            _value=_value sprintf("%c",strtonum("0x" _c));
          }else{
            _w=substr(_w,2);
          }
        }else{
          _c=substr(_w,1,1);
          _w=substr(_w,2);
          _value=_value _c;
        }
      }
      words[_wlen,EV3_WKEY_WTYP]=EV3_WT_VAL;
      words[_wlen,EV3_WKEY_WORD]=_value;
      words[_wlen,EV3_WKEY_OTYP]=TYPE_STR;
      _wlen++;
      _allow_regex=FALSE;
    }else if(_allow_regex&&match(_expr,/^\/(([^\/\\]|\\.)+)\/([a-zA-Z]*)/,_m)>=1){ #gawk
      # 正規表現リテラル
      #   /.../ の中身は1文字以上でなければならない
      #   二項演算子 /= や / 演算子は、直前に式がある筈なので判別可能。
      _expr=substr(_expr,RSTART+RLENGTH);
      words[_wlen,EV3_WKEY_WTYP]=EV3_WT_VAL;
      words[_wlen,EV3_WKEY_WORD]=_m[1];
      words[_wlen,EV3_WKEY_FLAG]=_m[3];
      words[_wlen,EV3_WKEY_OTYP]=TYPE_STR; #TODO■ 正規表現型(byref)を作る
      _wlen++;
      _allow_regex=FALSE;
    }else{
      _w="";
      _iN=length(_expr);
      for(_i=1;_i<=_iN;_i++){
        _c=substr(_expr,_i,1);
        if(_w _c in ev3scan_op)
          _w=_w _c;
        else break;
      }

      _i=length(_w);
      if(_i>=1){
        # 演算子
        _expr=substr(_expr,1+_i);
        _wt=ev3scan_op[_w];
        words[_wlen,EV3_WKEY_WTYP]=_wt;
        words[_wlen,EV3_WKEY_WORD]=_w;
        _wlen++;
        _allow_regex=(_wt!=EV3_WT_CLS&&_wt!=EV3_WT_INC||_w ~ /^[:}]$/);
      }else{
        # その他
        _ev3_error("ev3scan","invalid character '" _c "'");
        _expr=substr(_expr,2);
      }
    }
  }
  return _wlen;
}

function dump_words(words,wc, _w,_t){
  for(_i=0;_i<wc;_i++){
    _t=words[_i,EV3_WKEY_WTYP];
    _w=words[_i,EV3_WKEY_WORD];
    print _t " (" _w ")";
  }
}

#------------------------------------------------------------------------------
# ev3parse

function ev3parse_stack_top(stack, _count,_stop){
  _count=ev3obj_getMemberValue(stack,"count");
  if(_count==0)return NULL;
  _stop=ev3obj_getMemberValue(stack,_count-1);
  return _stop;
}
# @param[in] stack
# @return stack 中の EV3_ST_MARK の内一番上にある物を取得します。
function ev3parse_stack_topMark(stack, _index,_stop){
  _index=ev3obj_getMemberValue(stack,"count");
  while(_index>0){
    _stop=ev3obj_getMemberValue(stack,--_index);
    if(_stop&&ev3obj_getMemberValue(_stop,"stype")==EV3_ST_MARK)
      return _stop;
  }
  return NULL;
}
function ev3parse_stack_size(stack, _count){
  _count=ev3obj_getMemberValue(stack,"count");
  return _count;
}
function ev3parse_stack_push(stack,s, _count,_stop){
  _count=ev3obj_getMemberValue(stack,"count");

  # check EV3_ST_EXPR on EV3_ST_EXPR
  #   例えば 1+(2 3 4) の様な式の場合 3, 4 は無視する→ 1+(2) と解釈される。
  #   本当は ,  等で繋ぎたい所だ。
  # if(_count>0&&ev3obj_getMemberValue(s,"stype")==EV3_ST_EXPR){
  #   _stop=ev3obj_getMemberValue(stack,_count-1);
  #   if(ev3obj_getMemberValue(_stop,"stype")==EV3_ST_EXPR){
  #     _ev3_error("ev3parse","an expression just after another expression, ignored.");
  #     return;
  #   }
  # }
  #■というか PREF on EXPR でもエラーの筈である。

  if(_count>=1){
    _stype=ev3obj_getMemberValue(s,"stype");
    if(_stype!=EV3_ST_MARK){
      _stop=ev3obj_getMemberValue(stack,_count-1);
      # if(_stype==EV3_ST_SENT){
      #   if(ev3obj_getMemberValue(_stop,"stype")==EV3_ST_EXPR){
      #   ■ sentence に prefix は付きうるか?
      #   }
      # }else{
      # }

      if(ev3obj_getMemberValue(_stop,"stype")==EV3_ST_EXPR){
        # PPREF で XPREF に化けるかもしれないので reduce を試す。
        _stop=ev3parse_stack_reduce(stack,ev3scan_sentence_prec);
        _count=ev3obj_getMemberValue(stack,"count");
        if(_stop!=NULL){
          ev3parse_stack_push(stack,_stop);
          ev3obj_release(_stop);
          _ev3_error("ev3parse","an expression just after another expression, ignored. (expr1 =" ev3obj_dump(_stop) ", expr2 =" ev3obj_dump(s) ")");
          return FALSE;
        }
      }
    }
  }

  ev3obj_setMemberScal(stack,_count,TYPE_REF,s);
  ev3obj_setMemberScal(stack,"count",TYPE_NUM,_count+1);
  return TRUE;
}
function ev3parse_stack_pop(stack){
  _count=ev3obj_getMemberValue(stack,"count");
  if(_count-1>=0){
    ev3obj_setMemberScal(stack,_count-1,TYPE_NULL);
    ev3obj_setMemberScal(stack,"count",TYPE_NUM,_count-1);
  }
}
function ev3parse_stack_isTopPotentialExpression(stack,prec, _count,_i,_stype,_stop,_spref,_xtype){
  _count=ev3obj_getMemberValue(stack,"count");
  if(_count==0)return FALSE;

  _i=_count-1;
  _stop=ev3obj_getMemberValue(stack,_i);
  _stype=ev3obj_getMemberValue(_stop,"stype");
  if(_stype!=EV3_ST_EXPR)return FALSE;

  #■top が XPREF0 の場合に対する対応は?... (reduce も参照)
  #  現状この関数は func() や +1 -1 等からしか呼び出されず、prec > prec(XPREF0) なので気にしなくて良いが...
  #■PPREF が XPREF0 を有む場合? isTopPotentialExpression は判定できるのか?

  for(;_i>0;_i--){
    _spref=ev3obj_getMemberValue(stack,_i-1);
    _stype=ev3obj_getMemberValue(_spref,"stype");
    if((_stype==EV3_ST_XPREF||_stype==EV3_ST_XPREF0)&&prec<=ev3obj_getMemberValue(_spref,"oprec"))continue;

    if(_stype==EV3_ST_PPREF&&prec<=ev3obj_getMemberValue(_spref,"oprec"))
      return FALSE;
    else
      return TRUE;
  }
  return TRUE;
}

function _ev3parse_stack_reducePPREF(spref,stop, _xtype,_oword,_c,_arr){
  _xtype=ev3obj_getMemberValue(spref,"xtype");
  if(_xtype==EV3_WT_SNT){
    _oword=ev3obj_getMemberValue(spref,"oword");
    if(_oword ~ /^(if|switch|while|catch|with)$/){
      ev3obj_setMemberScal(spref,"stype",EV3_TYPE_ST,EV3_ST_XPREF);
      ev3obj_setMemberScal(spref,"oprec",TYPE_NUM,ev3scan_op[_oword "()",EV3_OPKEY_RPREC]);
      ev3obj_setMemberScal(spref,"cond",TYPE_REF,stop);
      return TRUE;
    }else if(_oword=="for"){
      # 括弧 () の中に…
      if(ev3obj_getMemberValue(stop,"xtype")==EV3_WT_CLS&&ev3obj_getMemberValue(stop,"oword")=="()"){
        stop=ev3obj_getMemberValue(stop,"operand");

        # a;b;c の構造
        _c=ev3parse_unpackArgumentArray(stop,_arr,";");
        if(_c==3){
          # for(a;b;c)
          ev3obj_setMemberScal(spref,"stype",EV3_TYPE_ST,EV3_ST_XPREF);
          ev3obj_setMemberScal(spref,"oprec",TYPE_NUM,ev3scan_op[_oword "()",EV3_OPKEY_RPREC]);
          ev3obj_setMemberScal(spref,"init",TYPE_REF,_arr[0]);
          ev3obj_setMemberScal(spref,"cond",TYPE_REF,_arr[1]);
          ev3obj_setMemberScal(spref,"term",TYPE_REF,_arr[2]);

          if(ev3obj_getMemberValue(_arr[1],"xtype")==EV3_XT_VOID){
            # for(;;)
            _arr[1]=ev3obj_placementNew(spref,"cond");
            ev3obj_setMemberScal(_arr[1],"xtype",EV3_TYPE_XT,EV3_WT_VAL);
            ev3obj_setMemberScal(_arr[1],"value",TYPE_BOOL,1);
          }

          return TRUE;
        }
        
        if(_c==1){
          # a:b の構造
          if(ev3obj_getMemberValue(stop,"xtype")==EV3_WT_BIN&&ev3obj_getMemberValue(stop,"oword")==":"){
            # for(i:range)
            ev3obj_setMemberScal(spref,"stype",EV3_TYPE_ST,EV3_ST_XPREF);
            ev3obj_setMemberScal(spref,"oprec",TYPE_NUM,ev3scan_op[_oword "()",EV3_OPKEY_RPREC]);
            ev3obj_setMemberScal(spref,"oword",TYPE_STR,"foreach");
          
            ev3obj_setMemberScal(spref,"lvalue",TYPE_REF,ev3obj_getMemberValue(stop,"lhs"));
            ev3obj_setMemberScal(spref,"range",TYPE_REF,ev3obj_getMemberValue(stop,"rhs"));
            return TRUE;
          }
        }
      }

      _ev3_error("ev3parse","unexpected structure of 'for(__expr__)'. __expr__ = " ev3obj_dump(stop));
      return FALSE;
    }

  }

  _ev3_assert(FALSE,"ev3parse (ev3parse_stack_reducePPREF)","unexpected EV3_ST_PPREF/" ev3obj_enumType_getName(EV3_TYPE_XT,_xtype) "/" _oword);
  return FALSE;
}

function ev3parse_stack_reduce(stack,prec, _count,_i,_stype,_stop,_spref,_xtype,_oword,_arr,_c){
  _count=ev3obj_getMemberValue(stack,"count");
  if(_count==0)return NULL;

  _i=_count-1;
  _stop=ev3obj_getMemberValue(stack,_i);
  _stype=ev3obj_getMemberValue(_stop,"stype");
  if(_stype==EV3_ST_XPREF0){
    if(ev3obj_getMemberValue(_stop,"oprec")>=prec){
      _stop=ev3parse_stack_emplaceTop(stack,EV3_ST_EXPR,EV3_XT_VOID);
      return ev3parse_stack_reduce(stack,prec);
    }
  }
  if(_stype!=EV3_ST_EXPR)return NULL;

  for(;_i>0;_i--){
    _spref=ev3obj_getMemberValue(stack,_i-1);
    #print "_i = " _i ", _count = " _count ", stack = " ev3obj_dump(stack);
    _stype=ev3obj_getMemberValue(_spref,"stype");
    if(_stype==EV3_ST_XPREF){
      if(ev3obj_getMemberValue(_spref,"oprec")>=prec){
        _xtype=ev3obj_getMemberValue(_spref,"xtype");
        if(_xtype==EV3_WT_BIN){
          
          # 結合処理
          ev3obj_setMemberScal(_spref,"stype",EV3_TYPE_ST,EV3_ST_EXPR);
          ev3obj_setMemberScal(_spref,"rhs",TYPE_REF,_stop);
          _stop=_spref;
          continue;
        }else if(_xtype==EV3_WT_UNA){
          ev3obj_setMemberScal(_spref,"stype",EV3_TYPE_ST,EV3_ST_EXPR);
          ev3obj_setMemberScal(_spref,"operand",TYPE_REF,_stop);
          _stop=_spref;
          continue;
        }else if(_xtype==EV3_WT_SNT){
          # if() for() while() switch() の類
          ev3obj_setMemberScal(_spref,"stype",EV3_TYPE_ST,EV3_ST_EXPR);
          ev3obj_setMemberScal(_spref,"content",TYPE_REF,_stop);
          _stop=_spref;
          continue;
        }else if(_xtype==EV3_XT_TRI){
          # cond?xtrue: ... → (if(cond)xtrue else content)
          ev3obj_setMemberScal(_spref,"stype",EV3_TYPE_ST,EV3_ST_EXPR);
          ev3obj_setMemberScal(_spref,"xtype",EV3_TYPE_XT,EV3_WT_SNT);
          ev3obj_setMemberScal(_spref,"oword",TYPE_STR,"else");
          ev3obj_setMemberScal(_spref,"content",TYPE_REF,_stop);
          _stop=_spref;
          continue;
        }else{
          _ev3_error("ev3parse","not supported EV3_ST_XPREF xtype");
          break;
        }
      }
    }else if(_stype==EV3_ST_PPREF){
      if(ev3obj_getMemberValue(_spref,"oprec")>=prec){
        if(_ev3parse_stack_reducePPREF(_spref,_stop)){
          # _spref は prefix に化けるので戻り値はなし
          _stop=NULL;
        }else{
          # _spref は捨てる。_stop をそのまま使う。
          _i--;
        }
        #print "dbg: _i = " _i ", stack = " ev3obj_dump(stack);
        break;
      }
    }
    break;
  }

  if(_stop!=NULL)ev3obj_capture(_stop);
  ev3obj_setMemberScal(stack,"count",TYPE_NUM,_i);
  for(;_i<_count;_i++)ev3obj_setMemberScal(stack,_i,TYPE_NULL);

  if(_stop==NULL){
    # ここで _stop==NULL になるのは PPREF が XPREF/XPREF0 になった時。
    # XPREF0 になった場合は再度挑戦する。
    return ev3parse_stack_reduce(stack,prec);
  }else
    return _stop;
}
function ev3parse_stack_reduceSentences(stack, _x,_i,_count,_xsent,_stype,_xprev,_xnew){
  # 最後の式
  _x=ev3parse_stack_reduce(stack,ev3scan_sentence_prec);

  # 文の連続を数える
  _count=ev3obj_getMemberValue(stack,"count");
  _i=_count;
  for(;_i>0;_i--){
    _xsent=ev3obj_getMemberValue(stack,_i-1);
    _stype=ev3obj_getMemberValue(_xsent,"stype");
    #print "dbg: _stype = " _stype " (" EV3_ST_SENT "?)"
    if(_stype!=EV3_ST_SENT)break;
  }

  if(_i==_count)return _x;

  if(_x==NULL){
    _x=ev3obj_new();
    ev3obj_setMemberScal(_x,"xtype",EV3_TYPE_XT,EV3_XT_VOID);
  }
  
  # contraction
  ev3obj_setMemberScal(stack,"count",TYPE_NUM,_i);
  _xprev=NULL;
  for(;_i<_count;_i++){
    _xsent=ev3obj_getMemberValue(stack,_i);

    if(_xprev==NULL){
      _xprev=_xsent;
      ev3obj_capture(_xprev);
    }else{
      ev3obj_setMemberScal(_xprev,"rhs",TYPE_REF,_xsent);
    }

    _xnew=ev3obj_new();
    ev3obj_setMemberScal(_xnew,"xtype",EV3_TYPE_XT,EV3_WT_BIN);
    ev3obj_setMemberScal(_xnew,"oword",TYPE_STR,";");
    ev3obj_setMemberScal(_xnew,"lhs",TYPE_REF,_xprev);
    ev3obj_release(_xprev);
    _xprev=_xnew;

    ev3obj_setMemberScal(stack,_i,TYPE_NULL);
  }

  ev3obj_setMemberScal(_xprev,"rhs",TYPE_REF,_x);
  ev3obj_release(_x);
  #print "dbg: _xprev = " ev3obj_dump(_xprev);
  return _xprev;
}

function ev3parse_stack_emplaceTop(stack,stype,xtype,oword,oprec, _s,_r){
  _s=ev3obj_new();
  ev3obj_setMemberScal(_s,"stype",EV3_TYPE_ST,stype);
  ev3obj_setMemberScal(_s,"xtype",EV3_TYPE_XT,xtype);
  if(oword!=NULL)ev3obj_setMemberScal(_s,"oword",TYPE_STR,oword);
  if(oprec!=NULL)ev3obj_setMemberScal(_s,"oprec",TYPE_NUM,oprec);
  _r=ev3parse_stack_push(stack,_s);
  ev3obj_release(_s);
  return _r?_s:NULL;
}


function ev3parse_expr_toString(x, _o1,_x1,_x2,_x3,_x4,_xtype,_stype,_ret,_i,_c){
  if(x==NULL)return "??";

  _xtype=ev3obj_getMemberValue(x,"xtype");
  if(_xtype==EV3_WT_BIN){
    _o1=ev3obj_getMemberValue(x,"oword");
    _x1=ev3parse_expr_toString(ev3obj_getMemberValue(x,"lhs"));
    _x2=ev3obj_univ(x SUBSEP UKEY_MEM SUBSEP "rhs");
    _x2=ev3parse_expr_toString(_x2);
    return "(" _x1 ")" _o1 "(" _x2 ")";
  }else if(_xtype==EV3_WT_UNA){
    _o1=ev3obj_getMemberValue(x,"oword");
    _x1=ev3obj_univ(x SUBSEP UKEY_MEM SUBSEP "operand");
    _x1=ev3parse_expr_toString(_x1);
    return _o1 "(" _x1 ")";
  }else if(_xtype==EV3_WT_INC){
    _o1=ev3obj_getMemberValue(x,"oword");
    _x1=ev3obj_univ(x SUBSEP UKEY_MEM SUBSEP "operand");
    _x1=ev3parse_expr_toString(_x1);
    return "(" _x1 ")" _o1;
  }else if(_xtype==EV3_WT_VAL){
    _x1=gensub(/[\n]/,"","g",ev3obj_getMemberValue(x,"value"));
    return _x1;
  }else if(_xtype==EV3_WT_SNT){
    _o1=ev3obj_getMemberValue(x,"oword");
    _stype=ev3obj_getMemberValue(x,"stype");
    if(_o1=="for"){
      if(_stype==EV3_ST_PPREF)
        return _o1 "...";

      _x1=ev3parse_expr_toString(ev3obj_univ(x SUBSEP UKEY_MEM SUBSEP "init"));
      _x2=ev3parse_expr_toString(ev3obj_univ(x SUBSEP UKEY_MEM SUBSEP "cond"));
      _x3=ev3parse_expr_toString(ev3obj_univ(x SUBSEP UKEY_MEM SUBSEP "term"));
      if(_stype==EV3_ST_XPREF)
        return _o1 "((" _x1 ");(" _x2 ");(" _x3 "))...";

      _x4=ev3parse_expr_toString(ev3obj_univ(x SUBSEP UKEY_MEM SUBSEP "content"));
      return _o1 "((" _x1 ");(" _x2 ");(" _x3 "))(" _x4 ")";
    }
  }else if(_xtype==EV3_XT_CALL){
    _o1=ev3obj_getMemberValue(x,"oword");
    _x1=ev3parse_expr_toString(ev3obj_getMemberValue(x,"xcallee"));
    _ret="(" _x1 ")" substr(_o1,1,1);
    _c=ev3obj_getMemberValue(x,"length");
    for(_i=0;_i<_c;_i++){
      if(_i!=0)_ret=_ret ",";
      _ret=_ret "(" ev3parse_expr_toString(ev3obj_getMemberValue(x,_i)) ")"
    }
    _ret=_ret  substr(_o1,2,1);
    return _ret;
  }else if(_xtype==EV3_WT_CLS){
    _o1=ev3obj_getMemberValue(x,"oword");
    _x1=ev3parse_expr_toString(ev3obj_getMemberValue(x,"operand"));
    return substr(_o1,1,1) _x1 substr(_o1,2,1);
  }

  _o1=ev3obj_univ(x SUBSEP UKEY_MEM SUBSEP "oword");
  if(_o1!=NULL){
    return "'" _o1 "'";
  }
  
  return "?"
}

function ev3parse_stack_getStateText(stack, _ret,_i,_c,_s,_x1,_x2){#@@
  _c=ev3obj_getMemberValue(stack,"count");
  _ret=_ret "stack : ";
  for(_i=0;_i<_c;_i++){
    if(_i!=0)_ret=_ret " | ";
    _s=ev3obj_getMemberValue(stack,_i);
    _ret=_ret gensub(/^EV3_ST_/,"",NULL,ev3obj_enumType_getName(EV3_TYPE_ST,ev3obj_getMemberValue(_s,"stype")));
    _ret=_ret "[" ev3parse_expr_toString(_s) "]";
  }
  return _ret;
}

#------------------------------------------------------------------------------

# comma 区切のリスト式を読み出す
function ev3parse_unpackArgumentArray(x,arr,op, _count,_i,_j,_t){
  if(x==NULL)return 0;
  if(op==NULL)op=",";

  # push rhs
  _count=0;
  while(ev3obj_getMemberValue(x,"xtype")==EV3_WT_BIN&&ev3obj_getMemberValue(x,"oword")==op){
    arr[_count++]=ev3obj_getMemberValue(x,"rhs");
    x=ev3obj_getMemberValue(x,"lhs");
  }
  arr[_count++]=x;

  # reverse
  _i=0;_j=_count-1;
  while(_i<_j){
    _t=arr[_i];arr[_i]=arr[_j];arr[_j]=_t;
    _i++;_j--;
  }
  
  return _count;
}

function ev3parse_processClosingBracket(stack,t,w, _ww,_wo,_scont,_lprec,_stop,_s,_args,_c,_i,_scond){
  _scont=ev3parse_stack_reduceSentences(stack);

  # 始まりの括弧
  _stop=ev3parse_stack_top(stack);
  if(_stop!=NULL&&ev3obj_getMemberValue(_stop,"xtype")==EV3_WT_OPN){
    _wo=ev3obj_getMemberValue(_stop,"oword");
    ev3parse_stack_pop(stack);
  }else{
    _ev3_error("ev3parse","an opening bracket corresponding to '" w "' not found");
    _wo=".";
    ev3obj_release(_scont);
    return FALSE;
  }
  _ww=_wo w;

  _lprec=ev3scan_op[_wo,EV3_OPKEY_LPREC];
  if(ev3parse_stack_isTopPotentialExpression(stack,_lprec)){
    # func() etc
    _stop=ev3parse_stack_reduce(stack,_lprec);
    _ev3_assert(_stop!=NULL,"ev3parse_processClosingBracket","stack_top ~ EV3_ST_EXPR なので。");

    if(_ww=="?:"){
      # _stop  = condition
      # _scont = true-clause: 空の場合は null 式に置き換え

      if(_scont==NULL){
        _scont=ev3obj_new();
        ev3obj_setMemberScal(_scont,"xtype",EV3_TYPE_XT,EV3_WT_VAL);
        ev3obj_setMemberScal(_scont,"value",TYPE_NULL);
      }
      
      _s=ev3parse_stack_emplaceTop(stack,EV3_ST_XPREF,EV3_XT_TRI,"?:",ev3scan_op["?",EV3_OPKEY_RPREC]);
      ev3obj_setMemberScal(_s,"cond",TYPE_REF,_stop);
      ev3obj_setMemberScal(_s,"xtrue",TYPE_REF,_scont);
      ev3obj_release(_stop);
      ev3obj_release(_scont);
      return TRUE;
    }else if(_ww=="[]"||_ww=="()"){
      # _stop  = function/array
      # _scont = args

      _c=ev3parse_unpackArgumentArray(_scont,_args);
      _s=ev3parse_stack_emplaceTop(stack,EV3_ST_EXPR,EV3_XT_CALL,_ww);
      ev3obj_setMemberScal(_s,"xcallee",TYPE_REF,_stop);
      ev3obj_setMemberScal(_s,"length",TYPE_NUM,_c);
      for(_i=0;_i<_c;_i++)
        ev3obj_setMemberScal(_s,_i,TYPE_REF,_args[_i]);

      ev3obj_release(_stop);
      if(_scont!=NULL)
        ev3obj_release(_scont);
      return TRUE;
    }

    ev3obj_release(_stop);
  }else{
    # () etc
    if(_ww=="[]"){
      _s=ev3parse_stack_emplaceTop(stack,EV3_ST_EXPR,EV3_XT_ARR); # 配列作成関数に redirect?
      if(_scont!=NULL){
        _c=ev3parse_unpackArgumentArray(_scont,_args);
        for(_i=0;_i<_c;_i++)
          ev3obj_setMemberScal(_s,_i,TYPE_REF,_args[_i]);
        ev3obj_release(_scont);
      }else{
        _c=0;
      }
      ev3obj_setMemberScal(_s,"length",TYPE_NUM,_c);
      return TRUE;
    }else if(_ww=="{}"||_ww=="()"){
      # ■中が空の () はエラーにするべきでは??
      if(_scont==NULL){
        _scont=ev3obj_new();
        ev3obj_setMemberScal(_scont,"xtype",EV3_TYPE_XT,EV3_XT_VOID);
      }

      _s=ev3parse_stack_emplaceTop(stack,EV3_ST_EXPR,EV3_WT_CLS,_ww);
      ev3obj_setMemberScal(_s,"operand",TYPE_REF,_scont);
      ev3obj_release(_scont);

      if(_ww=="{}"){
        
      }

      return TRUE;
    }
  }

  _ev3_error("ev3parse","unrecognized parentheses '" _ww "'.");
  ev3obj_release(_scont);
  return FALSE;
}

function ev3parse_processControlConstructs(stack,word, _sl,_stop,_stype,_oword){
  if(word==";"){
    for(;;){
      # 式があれば抽出
      _sl=ev3parse_stack_reduce(stack,ev3scan_op[word,EV3_OPKEY_LPREC]+0.01);
      if(_sl!=NULL)break;

      _stop=ev3parse_stack_top(stack);
      _stype=ev3obj_getMemberValue(_stop,"stype");
      _oword=ev3obj_getMemberValue(_stop,"oword");
      if(_stype==EV3_ST_XPREF){
        if(_oword ~ /^(if|for|while|catch|switch|with|else|try|finally|do)$/){
          # 引数が文末で空でも良い prefix 達: 空式を置いて再度
          # ■空でも良いという意味で EV3_ST_XPREF0 等という名前を付けて reduce で処理しても良い。
          ev3parse_stack_emplaceTop(stack,EV3_ST_EXPR,EV3_XT_VOID);
          continue;

          # 例x
          # PPREF(if) if 1+2+3 ;                                    入力
          # PPREF(if) PPREF(if) XPREF(1+) XPREF(2+) EXPR(3) | OP(;) 解析
          # PPREF(if) XPREF(if(1+2+3)) | OP(;)                      reduce
          # PPREF(if) XPREF(if(1+2+3)) EXPR() | OP(;)               空式を置く
          # XPREF(if(if(1+2+3)())) | OP(;)                          reduce
          # XPREF(if(if(1+2+3)())) EXPR() | OP(;)                   空式を置く
          # EXPR(if(if(1+2+3)())()) | OP(;)                         reduce
        }else{
          _ev3_error("ev3parse(;)","sentence cannot end here. remaining prefix = " ev3obj_dump(_stop) ".");
          return FALSE;
        }
      }

      break;
    }

    if(_sl==NULL){
      #空文を積む?
      #■前に prefix がある時にエラーにならない。或いは変な所でエラーになる。
      ev3parse_stack_emplaceTop(stack,EV3_ST_SENT,EV3_XT_VOID);
      return TRUE;
    }else{
      #式文: 文に変換して再 push
      ev3obj_setMemberScal(_sl,"stype",EV3_TYPE_ST,EV3_ST_SENT);
      ev3parse_stack_push(stack,_sl);
      ev3obj_release(_sl);
      return TRUE;
    }

  }else if(word=="else"){

    # 式 reduce
    _sl=ev3parse_stack_reduce(stack,ev3scan_op[word,EV3_OPKEY_LPREC]);

    if(_sl!=NULL){
      _stop=ev3parse_stack_top(stack);
      if(ev3obj_getMemberValue(_stop,"stype")==EV3_ST_XPREF&&ev3obj_getMemberValue(_stop,"oword")=="if"){
        ev3obj_setMemberScal(_stop,"xtrue",TYPE_REF,_sl);
        ev3obj_release(_sl);
        ev3obj_setMemberScal(_stop,"oword",TYPE_STR,"else");
        ev3obj_setMemberScal(_stop,"oprec",TYPE_NUM,ev3scan_op[word,EV3_OPKEY_RPREC]);
        return TRUE;
      }
    }

    _ev3_error("ev3parse(else)","missing a corresponding if clause.");
    return FALSE;
  }
  
  _ev3_assert(FALSE,"ev3parse","unknown EV3_WT_SNT/" word);
  return FALSE;
}

function ev3parse(expression, _wlen,_words,_stack,_i,_t,_w,_stop,_s,_p,_sl,_stype){
  _wlen=ev3scan(expression,_words);
  
  _stack=ev3obj_new();
  ev3obj_setMemberScal(_stack,"count",TYPE_NUM,0);

  for(_i=0;_i<_wlen;_i++){
    _t=_words[_i,EV3_WKEY_WTYP];
    _w=_words[_i,EV3_WKEY_WORD];

    #print ev3parse_stack_getStateText(_stack) " <- " ev3obj_enumType_getName(EV3_TYPE_XT,_t,_t) " '" _w "'";

    # determine type
    if(_t==EV3_WT_SGN){
      #print "stack = " ev3obj_dump(_stack)
      if(ev3parse_stack_isTopPotentialExpression(_stack,ev3scan_op[_w,EV3_OPKEY_LPREC]))
        _t=EV3_WT_BIN; # binary operator
      #print ev3obj_enumType_getName(EV3_TYPE_XT,_t)
      # else: prefix operator (SGN)
    }else if(_t==EV3_WT_INC){
      if(!ev3parse_stack_isTopPotentialExpression(_stack,ev3scan_op[_w,EV3_OPKEY_LPREC]))
        _t=EV3_WT_UNA; # prefix operator
      # else: postfix operator (INC)
    }else if(_t==EV3_WT_CLS&&_w==":"){
      _stop=ev3parse_stack_topMark(_stack);
      if(_stop==NULL||ev3obj_getMemberValue(_stop,"oword")!="?")
        _t=EV3_WT_BIN;
    }

    if(_t==EV3_WT_VAL){
      _s=ev3parse_stack_emplaceTop(_stack,EV3_ST_EXPR,_t);
      ev3obj_setMemberScal(_s,"value",_words[_i,EV3_WKEY_OTYP],_w);
    }else if(_t==EV3_WT_BIN){
      # binary operator

      # precedence
      _p=ev3scan_op[_w,EV3_OPKEY_RPREC];

      # lhs
      _sl=ev3parse_stack_reduce(_stack,ev3scan_op[_w,EV3_OPKEY_LPREC]);
      if(_sl==NULL){
        _ev3_error("ev3parse","missing left operand of '" _w "'.");
        ev3obj_release(_stack);
        return;
      }

      _s=ev3parse_stack_emplaceTop(_stack,EV3_ST_XPREF,_t,_w,_p);
      ev3obj_setMemberScal(_s,"lhs",TYPE_REF,_sl);
      ev3obj_release(_sl);
    }else if(_t==EV3_WT_UNA||_t==EV3_WT_SGN){
      # unary prefix operator

      # precedence
      if(_t==EV3_WT_SGN)
        _p=ev3scan_op["u" _w,EV3_OPKEY_RPREC];
      else
        _p=ev3scan_op[_w,EV3_OPKEY_RPREC];

      ev3parse_stack_emplaceTop(_stack,EV3_ST_XPREF,EV3_WT_UNA,_w,_p);
    }else if(_t==EV3_WT_INC){
      # suffix operator

      # lhs
      _sl=ev3parse_stack_reduce(_stack,ev3scan_op[_w,EV3_OPKEY_LPREC]);
      if(_sl==NULL){
        _ev3_error("ev3parse","missing an operand of suffix operator '" _w "'.");
        ev3obj_release(_stack);
        return;
      }

      _s=ev3parse_stack_emplaceTop(_stack,EV3_ST_EXPR,_t,_w);
      ev3obj_setMemberScal(_s,"operand",TYPE_REF,_sl);
      ev3obj_release(_sl);
    }else if(_t==EV3_WT_OPN){
      ev3parse_stack_emplaceTop(_stack,EV3_ST_MARK,_t,_w);
    }else if(_t==EV3_WT_CLS){
      if(!ev3parse_processClosingBracket(_stack,_t,_w)){
        ev3obj_release(_stack);
        return;
      }
    }else if(_t==EV3_WT_NAME){
      ev3parse_stack_emplaceTop(_stack,EV3_ST_EXPR,_t,_w);
    }else if(_t==EV3_WT_PPR){
      # if/while/for/switch/catch
      ev3parse_stack_emplaceTop(_stack,EV3_ST_PPREF,EV3_WT_SNT,_w,ev3scan_op[_w,EV3_OPKEY_RPREC]);
    }else if(_t==EV3_WT_SNT){
      if(!ev3parse_processControlConstructs(_stack,_w)){
        ev3obj_release(_stack);
        return;
      }
    }else{
      _ev3_assert(FALSE,"ev3parse","unknown token type " _t);
    }
  }

  #print ev3parse_stack_getStateText(_stack) " <- EOF";
  _s=ev3parse_stack_reduceSentences(_stack);
  if(ev3parse_stack_size(_stack)!=0){
    #print ev3parse_stack_getStateText(_stack);
    _ev3_error("ev3parse","expression not ended (expr='" expression "')");
    ev3obj_release(_s);
    _s=NULL;
  }
  ev3obj_release(_stack);
  return _s;
}

#------------------------------------------------------------------------------
#
# P6 ev3eval_expr の部分式も全て独立実体として定義しているのは非効率?
#   これは実行速度の問題に過ぎないので、遅いと感じない限りは保留で良い。
#   A 部分式も全て独立実体として定義 (現状)
#     参照カウント UKEY_REF を作成し inc/dec する労力が必要。
#   B 部分式は全て何かのオブジェクトのメンバとして定義
#     メンバを登録するのに CNT, ORD, KEY の3つを余分に定義する。
#   C 部分式は全て配列の要素として定義
#     CLASS_ARRAY を作成して、メンバの管理を CNT だけにできれば楽。
#     (CNT に関しては、A の方針でも ev3obj_new の時にカウントが必要なので、オーバーヘッドではない)。
#

function ev3eval_initialize(_proto, _context){
  # context
  EV3_CTXKEY_ROOT=0;

  ev3eval_null_singleton=ev3obj_setMemberScal(ev3proto_world,"null",TYPE_NULL);
  ev3eval_true_singleton=ev3obj_setMemberScal(ev3proto_world,"true",TYPE_BOOL,TRUE);
  ev3eval_false_singleton=ev3obj_setMemberScal(ev3proto_world,"false",TYPE_BOOL,FALSE);

  _proto=ev3obj_placementNew(ev3proto_world,"String.prototype");
  ev3obj_type[TYPE_STR,UKEY_PROTO]=_proto;
  ev3obj_setMemberScal(_proto,"+toLower",TYPE_NFUNC,"String#toLower");
  ev3obj_setMemberScal(_proto,"+toUpper",TYPE_NFUNC,"String#toUpper");
  ev3obj_setMemberScal(_proto,"![]",TYPE_NFUNC,"String#![]");

  _proto=ev3obj_placementNew(ev3proto_world,"Function.prototype");
  ev3obj_type[TYPE_XFUNC,UKEY_PROTO]=_proto;
  ev3obj_setMemberScal(_proto,"!()",TYPE_NFUNC,"Function#!()");

  _context=ev3obj_placementNew(ev3proto_world,"global");
  ev3obj_setMemberScal(_context,"+puts",TYPE_NFUNC,"global#puts");
  ev3obj_setMemberScal(_context,"+printf",TYPE_NFUNC,"global#printf");
  ev3obj_setMemberScal(_context,"+sprintf",TYPE_NFUNC,"global#sprintf");

  ev3obj_setMemberScal(_context,"+dump",TYPE_NFUNC,"global#dump");
  ev3obj_setMemberScal(_context,"+eval",TYPE_NFUNC,"global#eval");
  
  ev3obj_setMemberScal(_context,"+sin"  ,TYPE_NFUNC,"math::sin"  );
  ev3obj_setMemberScal(_context,"+cos"  ,TYPE_NFUNC,"math::cos"  );
  ev3obj_setMemberScal(_context,"+tan"  ,TYPE_NFUNC,"math::tan"  );
  ev3obj_setMemberScal(_context,"+sinh" ,TYPE_NFUNC,"math::sinh" );
  ev3obj_setMemberScal(_context,"+cosh" ,TYPE_NFUNC,"math::cosh" );
  ev3obj_setMemberScal(_context,"+tanh" ,TYPE_NFUNC,"math::tanh" );
  ev3obj_setMemberScal(_context,"+log"  ,TYPE_NFUNC,"math::log"  );
  ev3obj_setMemberScal(_context,"+exp"  ,TYPE_NFUNC,"math::exp"  );
  ev3obj_setMemberScal(_context,"+sqrt" ,TYPE_NFUNC,"math::sqrt" );
  ev3obj_setMemberScal(_context,"+cbrt" ,TYPE_NFUNC,"math::cbrt" );
  ev3obj_setMemberScal(_context,"+int"  ,TYPE_NFUNC,"math::int"  );
  ev3obj_setMemberScal(_context,"+floor",TYPE_NFUNC,"math::floor");
  ev3obj_setMemberScal(_context,"+ceil" ,TYPE_NFUNC,"math::ceil" );
  ev3obj_setMemberScal(_context,"+round",TYPE_NFUNC,"math::round");
  ev3obj_setMemberScal(_context,"+atan" ,TYPE_NFUNC,"math::atan" );
  ev3obj_setMemberScal(_context,"+asin" ,TYPE_NFUNC,"math::asin" );
  ev3obj_setMemberScal(_context,"+acos" ,TYPE_NFUNC,"math::acos" );
  ev3obj_setMemberScal(_context,"+atanh",TYPE_NFUNC,"math::atanh");
  ev3obj_setMemberScal(_context,"+asinh",TYPE_NFUNC,"math::asinh");
  ev3obj_setMemberScal(_context,"+acosh",TYPE_NFUNC,"math::acosh");
  ev3obj_setMemberScal(_context,"+atan2",TYPE_NFUNC,"math::atan2");
  ev3obj_setMemberScal(_context,"+pow"  ,TYPE_NFUNC,"math::pow"  );
  ev3obj_setMemberScal(_context,"+min"  ,TYPE_NFUNC,"math::min"  );
  ev3obj_setMemberScal(_context,"+hypot",TYPE_NFUNC,"math::hypot");
  ev3obj_setMemberScal(_context,"+max"  ,TYPE_NFUNC,"math::max"  );
}
function ev3eval_finalize(){
}


function ev3eval_ctx_save(ctx){
  ctx[EV3_CTXKEY_ROOT]=ev3eval_ctx_root;
  ctx[EV3_CTXKEY_SCOPE]=ev3eval_ctx_scope;
}
function ev3eval_ctx_restore(ctx){
  ev3eval_ctx_root=ctx[EV3_CTXKEY_ROOT];
  ev3eval_ctx_scope=ctx[EV3_CTXKEY_SCOPE];
}
function ev3eval_context_initialize(ctx, _scope,_parentScope){
  _scope=ctx[EV3_CTXKEY_SCOPE]=ev3obj_new();
  _parentScope=ev3obj_getMemberValue(ev3proto_world,"global");
  ev3obj_assignScal(_scope SUBSEP UKEY_PROTO,TYPE_REF,_parentScope);
  ctx[EV3_CTXKEY_ROOT]=_scope;
  ctx[EV3_CTXKEY_SCOPE]=_scope;
}
function ev3eval_context_finalize(ctx){
  ev3obj_release(ctx[EV3_CTXKEY_SCOPE]);
}

function ev3eval_null(){
  ev3obj_capture(ev3eval_null_singleton);
  return ev3eval_null_singleton;
}
function ev3eval_bool(value, _ret){
  _ret=value?ev3eval_true_singleton:ev3eval_false_singleton;
  ev3obj_capture(_ret);
  return _ret;
}

function ev3eval_nativeFunction_vsprintf(fmt,va){
  return sprintf(fmt,va[0],va[1],va[2],va[3],va[4],va[5],va[6],va[7],va[8],va[9],va[10],va[11],va[12],va[13],va[14],va[15],va[16],va[17],va[18],va[19]);
}
function ev3eval_nativeFunction_floor(x, _ix){
  if(x>=0)return x;
  _ix=int(1-x);
  return int(x+_ix)-_ix;
}

function ev3eval_nativeFunctionMath_call(dst,obj,fname,args, _fname,_i,_c,_f,_x,_y){
  _fname=fname
  sub(/^math::/,"",_fname);
  if(_fname ~ /^(a?(sin|cos|tan)h?|log|exp|(sq|cb)rt|int|floor|ceil|round)$/){
    _x=ev3eval_tonumber(args SUBSEP UKEY_MEM SUBSEP "+0");

    if(_fname=="sin")_x=sin(_x);
    else if(_fname=="cos")_x=cos(_x);
    else if(_fname=="tan")_x=sin(_x)/cos(_x);
    else if(_fname=="sinh"){_x=exp(_x);_x=0.5*(_x-1/_x);}
    else if(_fname=="cosh"){_x=exp(_x);_x=0.5*(_x+1/_x);}
    else if(_fname=="tanh"){_x=exp(2*_x);_x=(_x-1)/(_x+1);}
    else if(_fname=="log"){_x=log(_x);}
    else if(_fname=="exp"){_x=exp(_x);}
    else if(_fname=="sqrt"){_x=sqrt(_x);}
    else if(_fname=="cbrt"){_x=_x^(1.0/3.0);}
    else if(_fname=="int"){_x=int(_x);}
    else if(_fname=="floor"){_x=ev3eval_nativeFunction_floor(_x);}
    else if(_fname=="ceil"){_x=-ev3eval_nativeFunction_floor(-_x);}
    else if(_fname=="round"){_x=int(_x+(_x<0?-0.5:0.5));}
    else if(_fname=="atan"){_x=atan2(_x,1);}
    else if(_fname=="asin"){_x=atan2(_x,sqrt(1-_x*_x));}
    else if(_fname=="acos"){_x=atan2(sqrt(1-_x*_x),_x);}
    else if(_fname=="atanh"){_x=0.5*log((1+_x)/(1-_x));}
    else if(_fname=="asinh"){_x=log(_x+sqrt(_x*_x+1));}
    else if(_fname=="acosh"){_x=log(_x+sqrt(_x*_x-1));}

    ev3obj_assignScal(dst,TYPE_NUM,_x);
    return TRUE;
  }else if(_fname ~ /^(atan2|pow|hypot)$/){
    _x=ev3eval_tonumber(args SUBSEP UKEY_MEM SUBSEP "+0");
    _y=ev3eval_tonumber(args SUBSEP UKEY_MEM SUBSEP "+1");

    if(_fname=="atan2"){_x=atan2(_x,_y);}
    else if(_fname=="pow"){_x=_x^_y;}
    else if(_fname=="hypot"){_x=sqrt(_x*_x+_y*_y);}
      
    ev3obj_assignScal(dst,TYPE_NUM,_x);
    return TRUE;
  }else if(_fname ~ /^(min|max)$/){
    _f=_fname=="min"
    _x=ev3eval_tonumber(args SUBSEP UKEY_MEM SUBSEP "+0");
    _c=ev3obj_getMemberValue(args,"+length");
    for(_i=1;_i<_c;_i++){
      _y=ev3eval_tonumber(args SUBSEP UKEY_MEM SUBSEP "+" _i);
      if(_f!=(_x<_y))_x=_y;
    }
      
    ev3obj_assignScal(dst,TYPE_NUM,_x);
    return TRUE;
  }
}

function ev3eval_nativeFunctionObject_call(dst,obj,fname,args, _value){
  if(fname=="toString"){
    _value=ev3obj_toString(obj);
    ev3obj_assignScal(dst,TYPE_STR,_value);
    return TRUE;
  }
}
function ev3eval_nativeFunctionFunction_call(dst,obj,fname,args, _value,_expr,_scope,_ctxSave,_returnValue){
  if(fname=="!()"){
    _expr =ev3obj_getMemberPtr(obj,"[[Expr]]");
    _scope=ev3obj_getMemberPtr(obj,"[[Scope]]");

    # dereference
    if(!(_expr SUBSEP UKEY_TYP in ev3obj_universe)){
      _ev3_error("ev3eval (Function#!())","invalid function object. The expression [[Expr]] is undefined.");
      return;
    }
    if(ev3obj_universe[_expr,UKEY_TYP]==TYPE_REF)
      _expr=ev3obj_universe[_expr];

    ev3eval_ctx_save(_ctxSave);
    ev3eval_ctx_scope=ev3obj_new();
    ev3obj_assignScal(ev3eval_ctx_scope SUBSEP UKEY_PROTO,TYPE_REF,_scope);
    ev3obj_setMemberScal(ev3eval_ctx_scope,"+this",TYPE_REF,ev3obj_getMemberValue(args,"+0"));
    ev3obj_setMemberScal(ev3eval_ctx_scope,"+arguments",TYPE_REF,ev3obj_getMemberValue(args,"+1"));
    _returnValue=ev3eval_expr(_ctxSave,_expr);
    ev3obj_release(ev3eval_ctx_scope);
    ev3eval_ctx_restore(_ctxSave);

    ev3obj_assignObj(dst,_returnValue);
    ev3obj_release(_returnValue);
    return TRUE;
  }
}
function ev3eval_nativeFunctionString_call(dst,obj,fname,args, _value,_a1){
  if(fname ~ /^to(Lower|Upper)$/){
    _value=ev3eval_tostring(obj);

    if(fname=="toLower")_value=tolower(_value);
    else if(fname=="toUpper")_value=toupper(_value);

    ev3obj_assignScal(dst,TYPE_STR,_value);
    return TRUE;
  }

  if(fname ~ /^indexOf$/){
    _value=ev3eval_tostring(obj);
    _a1=ev3eval_tostring(args SUBSEP UKEY_MEM SUBSEP "+0");

    _value=index(_value,_a1)-1;

    ev3obj_assignScal(dst,TYPE_NUM,_value);
    return TRUE;
  }

  if(fname=="![]"){
    _value=ev3eval_tostring(obj);
    _a1=int(ev3eval_tonumber(args SUBSEP UKEY_MEM SUBSEP "+0"));
    if(_a1<0)_a1+=length(_value);

    _value=substr(_value,1+_a1,1);
    
    ev3obj_assignScal(dst,TYPE_STR,_value);
    return TRUE;
  }
}

function ev3eval_nativeFunction_call(dst,obj,fname,args, _fname2,_i,_a,_c,_r,_f,_x,_y,_m,_s,_v){
  if(fname ~ /^global#/){
    _fname2=fname
    sub(/^global#/,"",_fname2);
    if(_fname2=="puts"){
      #print "puts() args = " ev3obj_dump(args) ", args[0] = " ev3obj_dump(args SUBSEP UKEY_MEM SUBSEP "+0");
      print ev3eval_tostring(args SUBSEP UKEY_MEM SUBSEP "+0");
      return;
    }else if(_fname2=="printf"){
      _f=ev3eval_tostring(args SUBSEP UKEY_MEM SUBSEP "+0");
      _c=ev3obj_getMemberValue(args,"+length");
      for(_i=1;_i<_c;_i++)_a[_i-1]=ev3obj_getMemberValue(args,"+" _i);
      _r=ev3eval_nativeFunction_vsprintf(_f,_a);
      printf("%s",_r);
      ev3obj_assignScal(dst,TYPE_NUM,length(_r));
      return;
    }else if(_fname2=="sprintf"){
      _f=ev3eval_tostring(args SUBSEP UKEY_MEM SUBSEP "+1");
      _c=ev3obj_getMemberValue(args,"+length");
      for(_i=2;_i<_c;_i++)_a[_i-2]=ev3obj_getMemberValue(args,"+" _i);
      _r=ev3eval_nativeFunction_vsprintf(_f,_a);

      _f=args SUBSEP UKEY_MEM SUBSEP "+0";
      if(!(_f SUBSEP UKEY_TYP in ev3obj_universe)){
        _ev3_error("ev3eval (global#sprintf)","first argument undefined");
        return;
      }
      if(ev3obj_universe[_f,UKEY_TYP]!=TYPE_REF){
        # ■第一引数=ポインタ?
        _ev3_error("ev3eval (global#sprintf)","first argument should be an object reference");
        return;
      }

      ev3obj_assignScal(ev3obj_universe[_f],TYPE_STR,_r);
      ev3obj_assignScal(dst,TYPE_NUM,length(_r));
      return;
    }else if(_fname2=="dump"){
      print ev3obj_dump(args SUBSEP UKEY_MEM SUBSEP "+0");
      return;
    }else if(_fname2=="eval"){
      _s=ev3eval_tostring(args SUBSEP UKEY_MEM SUBSEP "+0");
      if((_s=ev3parse(_s))!=NULL){
        _v=ev3eval_expr(g_ctx,_s);
        _v=ev3eval_lvalueRead(_v);
        ev3obj_assignObj(dst,_v);
        ev3obj_release(_v);
        ev3obj_release(_s);
      }else{
        ev3obj_assignScal(dst,TYPE_NULL);
      }
      return;
    }
  }else if(fname ~ /^math::/){
    if(ev3eval_nativeFunctionMath_call(dst,obj,fname,args))return TRUE;
  }else if(match(fname,/^String#(.+)$/,_m)>=1){
    if(ev3eval_nativeFunctionString_call(dst,obj,_m[1],args))return TRUE;
  }else if(match(fname,/^Function#(.+)$/,_m)>=1){
    if(ev3eval_nativeFunctionFunction_call(dst,obj,_m[1],args))return TRUE;
  }else if(match(fname,/^default#(.+)$/,_m)>=1){
    if(ev3eval_nativeFunctionObject_call(dst,obj,_m[1],args))return TRUE;
  }

  _ev3_assert(FALSE,"ev3eval (ev3eval_nativeFunction_call)","specified function '" fname "' does not exist.");
}

#------------------------------------------------------------------------------
# EV3_TYPE_LVALUE
#
# どの様な時に参照解決が呼び出されるか?
# A 代入をする為に lvalue を取得する時。
#   メンバが存在しない場合は新しくメンバを作成する。
#   新しくメンバを作成するのにも失敗したら、エラーを吐いて NULL を返す。
#   そもそも参照でない場合にも NULL を返す。
# B rvalue を評価するに先立って。
#   メンバを作成できるが存在していない時は、null を返したい。
#   
#   そもそも参照でない場合は値をそのまま返したい。
# C & でポインタを取得する場合。
#   メンバが存在しない場合は新しくメンバを作成する。
#   (メンバが整数の場合は、作成せずに配列へのポインタと添字の両方を保持し、必要に応じて作成する?)。
#
# 参照解決の際、以下の5種類のパターンがある
# 1 そもそも参照でない
# 2 参照であり、当該変数を持つ事自体が不正である。
# 3 参照であり、変数が未だ存在しない。
# 4 参照であり、変数が既に存在する。
# 5 参照であり、当該変数にハンドラ(getter/setter)が登録されている
#
# A 代入時
#   1 -> エラーを出力し、適当な善後策を採る
#   2 -> エラーを出力し、適当な善後策を採る
#   3 -> メンバを登録し、代入する
#   4 -> そのまま代入する
#   5 -> setter を呼び出す
# B 右辺値取得時
#   1 -> そのまま値を返す
#   2 -> エラーを出力し、null を返す。
#   3 -> null を返す。
#   4 -> 読み取った値を返す。
#   5 -> getter を呼び出す。
# C 参照取得時
#   1 -> エラーを出力し、nullptr を返す。
#   2 -> エラーを出力し、nullptr を返す。
#   3 -> (object,メンバ名) のペアを返す。
#   4 -> (object,メンバ名) のペアを返す。
#   5 -> (object,メンバ名) のペアを返す。(getter/setter の resolution は使用時に)
# D 変数定義問い合わせ
#   1 -> エラーを出力, false (delete 100 などがこれに当たる)
#   2 -> false ('hello' in null など) ※JavaScriptでは型エラー
#   3 -> false ('hello' in {} など)
#   4 -> true  ('hello' in {hello:0} など)
#   5 -> true  ('length' in [] など)
#
# 処理を (1) 左辺値を取得する (2) 右辺値を取得する の2段階に分けるのが賢明である。
# %%{先ず、(1) 左辺値を取得するという段階が無視できない事を意識する。
#   変数名やメンバアクセスなど、式の構造からして既に左辺値が確定している様に思われるが、
#   実際にはそれが指し示す対象というのは文脈によって変化するし、
#   そもそも指し示す対象が存在しているかどうかも怪しい (変数名・メンバ名が不正な場合など)
#
#   特に左辺値を取得する場合は (object,メンバ名) という形にする事にする。
#   左辺値を取得するタイミングは評価の直前であるべきである。
#   というのも hello . world 等となっている場合に、
#   world 単体で左辺値に変換するのは問題があるからである→本当か?
#
#   考えてみれば、そもそも world を式として評価しようとしている時点でおかしい。
#   . 演算子の場合は、右辺の内容を評価せずに直接 memberName を取り出せば良い。
# }%%
#
# →文脈はその式が現れた時点で確定している筈だし、すぐさま左辺値にして問題ないのでは?
#   実際によく考えてみれば (obj,memberName) の組合せで lvalue は充分に思われる。
#
# ただ、考慮に入れなければならない事は
# (1) a が CLASS_STRUCT の場合、a.b はどの様なデータを保持するべきか?
#     ev3obj_univ キーが直接取得できればそれを返す。
#     プロパティで取得される値であるならばその値へ書き込む形にする。
#

function ev3eval_lvalueRead(obj, _type,_rv){
  _type=ev3obj_univ(obj SUBSEP UKEY_TYP);
  if(_type==EV3_TYPE_LVALUE){
    _rv=obj SUBSEP UKEY_MEM SUBSEP "rvalue";
    if(!(_rv SUBSEP UKEY_TYP in ev3obj_universe)){
      _root=obj SUBSEP UKEY_MEM SUBSEP "obj";
      _member=ev3obj_getMemberValue(obj,"memberName");
      ev3proto_getProperty(_root,_member,_rv);
    }
    return _rv;
  }else{
    return obj;
  }
}
function ev3eval_lvalueWrite(obj,src, _root,_member,_mt){
  _type=ev3obj_univ(obj SUBSEP UKEY_TYP);
  if(_type==EV3_TYPE_LVALUE){
    _root=obj SUBSEP UKEY_MEM SUBSEP "obj";
    _member=ev3obj_getMemberValue(obj,"memberName");
    ev3obj_unsetMember(obj,"rvalue");
    ev3proto_setProperty(_root,_member,ev3eval_lvalueRead(src));
    # print "dbg201411-1: dst = " ev3obj_dump(obj) ", src = " ev3obj_dump(src);
    # print "dbg201411-1: _root = " ev3obj_dump(_root) ", memberName = " _member ", value = " ev3obj_dump(ev3eval_lvalueRead(src));
    return TRUE;
  }
}
function ev3eval_lvalueWriteScal(obj,type,value, _root,_member,_mt){
  _type=ev3obj_univ(obj SUBSEP UKEY_TYP);
  if(_type==EV3_TYPE_LVALUE){
    _root=obj SUBSEP UKEY_MEM SUBSEP "obj";
    _member=ev3obj_getMemberValue(obj,"memberName");
    ev3obj_unsetMember(obj,"rvalue");
    ev3proto_setPropertyScal(_root,_member,type,value);
    return TRUE;
  }
}

# function ev3eval_lvalue_getType(obj){
#   obj=ev3eval_lvalueRead(obj);
#   return ev3obj_univ(obj SUBSEP UKEY_TYP);
# }

#------------------------------------------------------------------------------

function ev3eval_tonumber(obj, _type){
  obj=ev3eval_lvalueRead(obj);
  _type=ev3obj_univ(obj SUBSEP UKEY_TYP);
  if(_type==NULL||_type==TYPE_NULL)
    return 0;
  else if(_type==TYPE_REF)
    return ev3eval_tonumber(ev3obj_universe[obj]);
  else if(_type==TYPE_NUM)
    return ev3obj_universe[obj];
  else if(_type==TYPE_STR)
    return ev3obj_universe[obj]+0;
  else
    return QNAN;
}
function ev3eval_toboolean(obj){
  obj=ev3eval_lvalueRead(obj);
  _type=ev3obj_univ(obj SUBSEP UKEY_TYP);
  if(_type==NULL||_type==TYPE_NULL)
    return FALSE;
  else if(_type==TYPE_REF)
    return ev3eval_toboolean(ev3obj_universe[obj]);
  else if(_type==TYPE_NUM||_type==TYPE_BOOL)
    return ev3obj_universe[obj]!=0;
  else
    return TRUE;
}
# obj は評価式の値を格納する
function ev3eval_tostring(obj, _type,_fun,_ret,_value,_args,_r){
  obj=ev3eval_lvalueRead(obj);

  #if(ev3obj_type[ev3obj_universe[obj,UKEY_TYP],EV3OBJ_TKEY_CLS]==CLASS_BYREF){
  if(ev3obj_univ(obj SUBSEP UKEY_TYP)==TYPE_REF&&ev3obj_univ(ev3obj_universe[obj] SUBSEP UKEY_TYP)==TYPE_OBJ){
    #■専用の構造体or要素数3の配列の型を作成し一括で管理する。
    _fun=ev3obj_new();
    _ret=ev3obj_new();
    _args=ev3obj_new();

    ev3proto_getProperty(obj,"+toString",_fun);

    ev3obj_setMemberScal(_args,"+length",TYPE_NUM,0);
    _r=ev3proto_callFunction(_ret,obj,_fun,_args);

    _value=ev3obj_toString(_ret);

    ev3obj_release(_args);
    ev3obj_release(_ret);
    ev3obj_release(_fun);
    if(_r)return _value;
  }

  return ev3obj_toString(obj);
}
function ev3eval_equals(lhs,rhs,exact, _ltype,_rtype,_lclass,_rclass,_i,_iN){
  lhs=ev3eval_lvalueRead(lhs);
  rhs=ev3eval_lvalueRead(rhs);
  _ltype=ev3obj_univ(lhs SUBSEP UKEY_TYP);
  _rtype=ev3obj_univ(rhs SUBSEP UKEY_TYP);
  if(_ltype==NULL||_ltype==CLASS_NULL||_rtype==NULL||_rtype==CLASS_NULL){
    if(exact)
      return _ltype==_rtype;
    else
      return (_ltype==NULL||_ltype==CLASS_NULL)==(_rtype==NULL||_rtype==CLASS_NULL);
  }

  _lclass=ev3obj_type[_ltype,EV3OBJ_TKEY_CLS];
  _rclass=ev3obj_type[_rtype,EV3OBJ_TKEY_CLS];
  _ev3_assert(_lclass!=CLASS_BYREF&&_rclass!=CLASS_BYREF,"ev3eval_equals","bare byref object should not appear here!");

  if(_lclass==CLASS_STRUCT||_rclass==CLASS_STRUCT){
    if(_lclass!=_rclass)return FALSE;
    
    _iN=ev3obj_type[_lclass,UKEY_MEM_CNT];
    for(_i=0;_i<_iN;_i++){
      _key=ev3obj_type[_lclass,UKEY_MEM,_i];
      if(!ev3eval_equals(lhs SUBSEP _key,rhs SUBSEP _key,exact))
        return FALSE;
    }
    return FALSE;
  }

  # assert(_lclass==CLASS_SCAL&&_rclass==CLASS_SCAL)
  if(exact||_ltype==TYPE_REF||_rtype==TYPE_REF){
    return _ltype==_rtype&&ev3obj_universe[lhs]==ev3obj_universe[rhs];
  }else{
    return ev3eval_tostring(lhs)==ev3eval_tostring(rhs);
  }
}

# 副作用なし単純二項演算子の評価
function ev3eval_expr_binary_operator_v(ctx,oword,lhs,rhs, _ltype,_rtype,_rlhs,_rrhs,_vlhs,_vrhs,_vret,_ret,_lvalue){
  if(oword ~ /^([-+*\/%\|^&]|<<|>>)$/){
    lhs=ev3eval_lvalueRead(lhs);
    rhs=ev3eval_lvalueRead(rhs);

    # str+str
    if(oword=="+"){
      _ltype=ev3obj_univ(lhs SUBSEP UKEY_TYP);
      _rtype=ev3obj_univ(rhs SUBSEP UKEY_TYP);
      if(_ltype==TYPE_STR||_rtype==TYPE_STR){
        _vret=ev3eval_tostring(lhs) ev3eval_tostring(rhs);
        return ev3obj_new_scal(TYPE_STR,_vret);
      }
    }

    _vlhs=ev3eval_tonumber(lhs);
    _vrhs=ev3eval_tonumber(rhs);

    _vret=QNAN;
    if(oword=="+")_vret=_vlhs+_vrhs;
    else if(oword=="-")_vret=_vlhs-_vrhs;
    else if(oword=="*")_vret=_vlhs*_vrhs;
    else if(oword=="/")_vret=_vlhs/_vrhs;
    else if(oword=="%")_vret=_vlhs%_vrhs;
    else if(oword=="|")_vret=or(_vlhs,_vrhs);
    else if(oword=="^")_vret=xor(_vlhs,_vrhs);
    else if(oword=="&")_vret=and(_vlhs,_vrhs);
    else if(oword=="<<")_vret=lshift(_vlhs,_vrhs);
    else if(oword==">>")_vret=rshift(_vlhs,_vrhs);

    return ev3obj_new_scal(TYPE_NUM,_vret);
  }

  # obj<obj
  if(oword ~ /^([<>]=?|[<>]\?|\?[<>])$/){
    _vlhs=ev3eval_lvalueRead(lhs);
    _vrhs=ev3eval_lvalueRead(rhs);
    _ltype=ev3obj_univ(_vlhs SUBSEP UKEY_TYP);
    _rtype=ev3obj_univ(_vrhs SUBSEP UKEY_TYP);
    if(_ltype==TYPE_NUM||_rtype==TYPE_NUM){
      # num<num
      _vlhs=ev3eval_tonumber(_vlhs);
      _vrhs=ev3eval_tonumber(_vrhs);
    }else{
      # str<str
      _vlhs=ev3eval_tostring(_vlhs);
      _vrhs=ev3eval_tostring(_vrhs);
    }

    if(oword ~ /^[<>]=?$/){
      # 大小比較
      _vret=FALSE;
      if(oword=="<")
        _vret=_vlhs<_vrhs;
      else if(oword==">")
        _vret=_vlhs>_vrhs;
      else if(oword=="<=")
        _vret=_vlhs<=_vrhs;
      else if(oword==">=")
        _vret=_vlhs>=_vrhs;

      return ev3eval_bool(_vret);
    }else{
      # 最大・最小演算子
      if(oword=="<?"){
        _ret=_vlhs<_vrhs?lhs:rhs;
      }else if(oword==">?"){
        _ret=_vlhs>_vrhs?lhs:rhs;
      }else if(oword=="?>"){
        _ret=_vlhs>_vrhs?rhs:lhs;
      }else if(oword=="?<"){
        _ret=_vlhs<_vrhs?rhs:lhs;
      }
      ev3obj_capture(_ret);
      return _ret;
    }
  }

  if(oword ~ /^[!=]==?$/){
    _vret=ev3eval_equals(lhs,rhs,oword ~ /^[!=]==$/);
    if(oword ~ /^!/)_vret=!_vret;

    return ev3eval_bool(_vret);
  }

  # 代入演算子達
  if(oword=="="){
    rhs=ev3eval_lvalueRead(rhs);
    if(ev3eval_lvalueWrite(lhs,rhs))
      _ret=lhs;
    else{
      _ret=rhs;
      _ev3_error("ev3eval (operator" oword ")","lhs is not an lvalue (lhs = " ev3obj_dump(lhs) ").");
    }
    # print "dbg201411(=): _ret=" ev3obj_dump(_ret);
    ev3obj_capture(_ret);
    return _ret;
  }else if(oword ~ /^([-+*\/%\|^&]|<<|>>|[<>]\?|\?[<>])=$/){
    _ret=ev3eval_expr_binary_operator_v(ctx,substr(oword,1,length(oword)-1),lhs,rhs);
    if(ev3eval_lvalueWrite(lhs,_ret)){
      ev3obj_release(_ret);
      ev3obj_capture(lhs);
      _ret=lhs;
    }else{
      _ev3obj_error("ev3eval (operator" oword "): lhs is not an lvalue (lhs = " ev3obj_dump(lhs) ").");
    }
    return _ret;
  }

  _ev3_assert(FALSE,"ev3eval","not supported binary operator '" oword "'");
  return ev3eval_null();
}
function ev3eval_expr_binary_operator(ctx,oword,xlhs,xrhs, _lhs,_rhs,_ret,_member){
  # 遅延評価・怠惰評価
  if(oword ~ /^(&&|\|\|)=?$/){
    _lhs=ev3eval_expr(ctx,xlhs);
    if((oword ~ /^&/)==!!ev3eval_toboolean(_lhs)){
      _rhs=ev3eval_expr(ctx,xrhs);
      if((oword ~ /=$/)&&ev3eval_lvalue_setProperty(_lhs,_rhs)){
        ev3obj_release(_rhs);
        return _lhs;
      }else{
        ev3obj_release(_lhs);
        return _rhs;
      }
    }else{
      return _lhs;
    }
  }else if(oword ~ /^[,;]$/){
    _lhs=ev3eval_expr(ctx,xlhs);
    ev3obj_release(_lhs);
    return ev3eval_expr(ctx,xrhs);
  }else if(oword ~ /^(\.|::|->)$/){
    # member access の場合

    #■-> :: は異なる意味

    _lhs=ev3eval_expr(ctx,xlhs);

    if(ev3obj_getMemberValue(xrhs,"xtype")==EV3_WT_NAME){
      _lhs=ev3eval_lvalueRead(_lhs);
      _member="+" ev3obj_getMemberValue(xrhs,"oword");
      if(!ev3proto_isPropertyNameValid(_lhs,_member)){
        _ev3_error("ev3eval (binary operator " oword ")"," lhs does not have a member '" substr(_member,2) "' (lhs = " ev3obj_dump(_lhs) ").");
        ev3obj_release(_lhs);
        return ev3eval_null();
      }

      _ret=ev3obj_new_scal(EV3_TYPE_LVALUE);
      ev3obj_setMemberObj(_ret,"obj",_lhs);
      ev3obj_setMemberScal(_ret,"memberName",TYPE_STR,_member);
      ev3obj_release(_lhs);
      return _ret;

      # ■a.b の時、a は rvalue になっても良い?
      #   a の中身が CLASS_BYREF ならば rvalue になっても OK
      #   a の中身が CLASS_STRUCT だと rvalue になられると困る
      #   → lhs を lvalue_getProperty にするのではなく lvalue_getPropertyAsRef 的にするべき。
    }else{
      _ev3_error("ev3eval","rhs of member access operator '" oword "' should be an identifier.");
      ev3obj_release(_lhs);
      return ev3eval_null();
    }
  }else if(oword ~ /^=>$/){
    _ret=ev3obj_new_scal(TYPE_XFUNC);
    ev3obj_setMemberScal(_ret,"[[Expr]]",TYPE_REF,xrhs);
    ev3obj_setMemberScal(_ret,"[[Scope]]",TYPE_REF,ev3eval_ctx_scope);

    return _ret;
  }

  # 以降の演算子はオーバーロードを許可する■
  _lhs=ev3eval_expr(ctx,xlhs);
  _rhs=ev3eval_expr(ctx,xrhs);

  # 型に依存しない演算
  _ret=ev3eval_expr_binary_operator_v(ctx,oword,_lhs,_rhs);

  # ■
  # ->* .*
  # これを実装する為には「変数名の参照」を実装する必要がある。

  ev3obj_release(_rhs);
  ev3obj_release(_lhs);
  return _ret;
}

function ev3eval_expr_unary_operator(ctx,oword,xarg, _arg){
  _arg=ev3eval_expr(ctx,xarg);
  _ret=ev3eval_expr_unary_operator_v(ctx,oword,_arg);
  ev3obj_release(_arg);
  return _ret;
}
function ev3eval_expr_unary_operator_v(ctx,oword,arg, _varg,_vret,_ret){
  # oword = "i++" "i--" "++" "--" "-" "+" "~" "!"
  # oword = "&" "*" ■
  if(oword ~ /^i/){
    # 後置演算子
    if(oword=="i++"||oword="i--"){
      _ret=ev3obj_new(_varg=ev3eval_lvalueRead(arg));
      _varg=ev3eval_tonumber(_varg);
      _varg=oword=="i++"?_varg+1:_varg-1;
      ev3eval_lvalueWriteScal(arg,TYPE_NUM,_varg);
      return _ret;
    }

    #_ev3_assert(FALSE,"ev3eval","not supported suffix operator '" oword "'");
    return ev3eval_null();
  }else{
    # 前置演算子
    if(oword ~ /^[-+~]$/){
      _varg=ev3eval_tonumber(arg);

      _vret=QNAN;
      if(oword=="+")_vret=_varg;
      else if(oword=="-")_vret=-_varg;
      else if(oword=="~")_vret=compl(_varg);
      return ev3obj_new_scal(TYPE_NUM,_vret);
    }

    if(oword=="!"){
      _varg=ev3eval_toboolean(arg);
      return ev3obj_new_scal(TYPE_BOOL,!_varg);
    }

    if(oword ~ /^(--|\+\+)$/){
      _varg=ev3eval_tonumber(arg);
      _varg=oword=="++"?_varg+1:_varg-1;
      ev3eval_lvalueWriteScal(arg,TYPE_NUM,_varg);
      ev3obj_capture(arg);
      return arg;
    }

    _ev3_assert(FALSE,"ev3eval","not supported prefix operator '" oword "'");
    return ev3eval_null();
  }
}

function ev3eval_expr_evaluateArgs(ctx,x,argarr, _args,_i,_iN,_elem){
  _iN=ev3obj_getMemberValue(x,"length");
  _args=ev3obj_new();
  ev3obj_setMemberScal(_args,"+length",TYPE_NUM,_iN);
  for(_i=0;_i<_iN;_i++){
    _elem=ev3eval_expr(ctx,ev3obj_getMemberValue(x,_i));
    ev3obj_setMemberObj(_args,"+" _i,ev3eval_lvalueRead(_elem));
    ev3obj_release(_elem);
  }
  argarr["length"]=_iN;
  return _args;
}

function ev3eval_expr_functionCall(ctx,x,xtype, _arginfo,_args,_iN,_last,_oword,_this,_callee,_ret,_accessor){
  # 引数を _args に読み取り
  if(xtype==EV3_XT_CALL){
    _callee=ev3eval_expr(ctx,ev3obj_getMemberValue(x,"xcallee"));
    _args=ev3eval_expr_evaluateArgs(ctx,x,_arginfo);
    _oword=ev3obj_getMemberValue(x,"oword");
    _ret=NULL;
    if(_oword=="()"){
      if(ev3obj_univ(_callee SUBSEP UKEY_TYP)==EV3_TYPE_LVALUE){
        _this=_callee SUBSEP UKEY_MEM SUBSEP "obj";
        _callee=ev3eval_lvalueRead(_callee);
        #print "dbg: _this = " ev3obj_dump(_this) ", _callee = " ev3obj_dump(_callee);
      }else{
        _this=ev3eval_ctx_root;
      }
      
      _ret=ev3obj_new();
      ev3proto_callFunction(_ret,_this,_callee,_args);
    }else if(_oword=="[]"){
      _callee=ev3eval_lvalueRead(_callee);
      _ret=ev3obj_new();
      _accessor=ev3obj_new();
      if(ev3proto_getProperty(_callee,"![]",_accessor)){
        # operator[] が overload されている時

        # if(ev3obj_universe[_accessor,UKEY_TYP]==TYPE_PROP){
        # ■getter/setter で処理する為に EV3_TYPE_LVALUE ならぬ EV3_TYPE_PROP_LVALUE 的な物を作成する…。
        # }

        ev3proto_callFunction(_ret,_callee,_accessor,_args);
      }else{
        # メンバアクセスに変換
        _iN=_arginfo["length"];
        _last=(_iN>=1?ev3eval_tostring(_args SUBSEP UKEY_MEM SUBSEP "+" (_iN-1)):"");
        if(ev3proto_isPropertyNameValid(_callee,"+" _last)){
          ev3obj_assignScal(_ret,EV3_TYPE_LVALUE);
          ev3obj_setMemberScal(_ret,"obj",TYPE_REF,_callee);
          ev3obj_setMemberScal(_ret,"memberName",TYPE_STR,"+" _last);
        }else{
          _ev3_error("ev3eval (operator" _oword ")"," callee does not have a member '" _last "' (callee = " ev3obj_dump(_callee) ").");
          ev3obj_assignScal(_ret,TYPE_NULL);
        }
      }
      ev3obj_release(_accessor);
    }else{
      _ev3_assert(FALSE,"ev3eval_expr","unknown function-call bracket '" _oword "'!");
    }
    ev3obj_release(_args);
    ev3obj_release(_callee);
  }else{
    _args=ev3eval_expr_evaluateArgs(ctx,x);
    _ret=ev3obj_new_scal(TYPE_REF,_args);
    ev3obj_release(_args);
  }

  return _ret;
}

function ev3eval_expr_controlConstructs(ctx,x,xtype, _oword,_init,_xcond,_cond,_xterm,_term,_xcont,_value){
  _oword=ev3obj_getMemberValue(x,"oword");
  if(_oword=="if"){
    _cond=ev3eval_expr(ctx,ev3obj_getMemberValue(x,"cond"));
    if(!ev3eval_toboolean(_cond))return _cond;

    ev3obj_release(_cond);
    return ev3eval_expr(ctx,ev3obj_getMemberValue(x,"content"));
  }else if(_oword=="else"){
    # if(cond)xtrue else content;
    _cond=ev3eval_expr(ctx,ev3obj_getMemberValue(x,"cond"));
    if(ev3eval_toboolean(_cond)){
      _value=ev3eval_expr(ctx,ev3obj_getMemberValue(x,"xtrue"));
    }else{
      _value=ev3eval_expr(ctx,ev3obj_getMemberValue(x,"content"));
    }
    ev3obj_release(_cond);
    return _value;
  }else if(_oword=="for"){
    _init=ev3eval_expr(ctx,ev3obj_getMemberValue(x,"init"));
    ev3obj_release(_init);

    _xcond=ev3obj_getMemberValue(x,"cond");
    _xterm=ev3obj_getMemberValue(x,"term");
    _xcont=ev3obj_getMemberValue(x,"content");

    for(;;){
      _cond=ev3eval_expr(ctx,_xcond);
      if(!ev3eval_toboolean(_cond))return _cond;
      ev3obj_release(_cond);

      ev3obj_release(ev3eval_expr(ctx,_xcont));
      ev3obj_release(ev3eval_expr(ctx,_xterm));
    }
  }else{
    _ev3_error(FALSE,"ev3eval_expr_controlConstructs","unknown oword='" _oword "'");
  }
}

# 必ず NULL, CLASS_NULL, CLASS_SCAL, CLASS_STRUCT のどれか。
# CLASS_BYREF の結果の場合は参照 (TYPE_REF) を返す。
function ev3eval_expr(ctx,x, _xtype,_oword,_xlhs,_xrhs,_xarg,_ret, _arr,_i,_iN,_callee,_this,_scope,_original_ctx,_owner){
  _xtype=ev3obj_getMemberValue(x,"xtype");
  if(_xtype==EV3_WT_BIN){
    _oword=ev3obj_getMemberValue(x,"oword");
    _xlhs=ev3obj_getMemberValue(x,"lhs");
    _xrhs=ev3obj_getMemberValue(x,"rhs");
    return ev3eval_expr_binary_operator(ctx,_oword,_xlhs,_xrhs);
  }else if(_xtype==EV3_WT_UNA){
    _oword=ev3obj_getMemberValue(x,"oword");
    _xarg=ev3obj_getMemberValue(x,"operand");
    return ev3eval_expr_unary_operator(ctx,_oword,_xarg);
  }else if(_xtype==EV3_WT_INC){
    _oword=ev3obj_getMemberValue(x,"oword");
    _xarg=ev3obj_getMemberValue(x,"operand");
    return ev3eval_expr_unary_operator(ctx,"i" _oword,_xarg);
  }else if(_xtype==EV3_WT_VAL){
    _ret=ev3obj_new();
    ev3obj_assignObj(_ret,ev3obj_getMemberPtr(x,"value"));
    return _ret;
  }else if(_xtype==EV3_XT_VOID){
    return ev3obj_new_scal(TYPE_NULL);
  }else if(_xtype==EV3_WT_CLS){
    # 唯の括弧
    _oword=ev3obj_getMemberValue(x,"oword")
    _xarg=ev3obj_getMemberValue(x,"operand");
    if(_oword ~ /^(\(\)|\{\})$/){
      # {} の時は ev3obj_new() をそのまま返す。
      if(_oword=="{}")
        if(ev3obj_getMemberValue(_xarg,"xtype")==EV3_XT_VOID)
          return ev3obj_new();

      # ■{a:b,c:d} の場合
      
      return ev3eval_expr(ctx,_xarg);
    }else{
      _ev3_error("ev3eval","unknown parenthesis pair");
      return ev3eval_expr(ctx,ev3obj_getMemberValue(x,"operand"));
    }

  }else if(_xtype==EV3_XT_ARR||_xtype==EV3_XT_CALL){
    _ret=ev3eval_expr_functionCall(ctx,x,_xtype);
    if(_ret!=NULL)return _ret;
  }else if(_xtype==EV3_WT_NAME){
    _scope=ev3eval_ctx_scope;
    _oword=ev3obj_getMemberValue(x,"oword");

    # 変数の宣言されている位置
    _owner=ev3proto_getVariableOwner(_scope,"+" _oword);
    if(_owner==NULL)_owner=ev3eval_ctx_root;
    
    _ret=ev3obj_new_scal(EV3_TYPE_LVALUE);
    ev3obj_setMemberScal(_ret,"obj",TYPE_REF,_owner);
    ev3obj_setMemberScal(_ret,"memberName",TYPE_STR,"+" _oword);
    return _ret;
  }else if(_xtype==EV3_WT_SNT){
    _ret=ev3eval_expr_controlConstructs(ctx,x,_xtype);
    if(_ret!=NULL)return _ret;
  }

  _ev3_assert(FALSE,"ev3eval_expr","unprocessed token (xtype = " ev3obj_enumType_getName(EV3_TYPE_XT,_xtype) ")!");
  return;
}

function ev3eval(ctx,expr, _s,_v,_ctxSave){
  _ret="undefined";
  if((_s=ev3parse(expr))!=NULL){
    ev3eval_ctx_save(_ctxSave);
    ev3eval_ctx_restore(ctx);

    _v=ev3eval_expr(NULL,_s);
    _v=ev3eval_lvalueRead(_v);
    _ret="result = " ev3obj_dump(_v);
    ev3obj_release(_v);
    ev3obj_release(_s);

    ev3eval_ctx_restore(_ctxSave);
  }
  return _ret;
}

#------------------------------------------------------------------------------

function dbg_ev3scan(){
  wc=ev3scan("1 2 1.2 1e5 0x64 077 \"a\" \"\\e[91mhello\\e[m\" '\\'' + /hello\\.\\./ /* this is comment */",words);
  dump_words(words,wc);

  wc=ev3scan("あ /^hello/ いろは this is return { } ( ) += *= <?=",words);
  dump_words(words,wc);
}
function test_ev3parse(expr,_s,_v,_ctx){
  #expr="1";
  #expr="-2|-1";
  #expr="1*2+4*-+-+-5+'5'+'hello'";
  #expr="1-(2+3)";
  #expr="1+2+3+4";
  #expr="1,2,3,4";
  #expr="[1,2,3,4]";
  #expr="1+'2'+2(1,2,3,4)";
  #expr="hello=2004,a=b=3,a+=b+=3";
  #expr="hello=2004";
  #expr="o=[1,2,3];o.hello=123;o.o=[1,2,3,4]";
  #expr="1..toString";
  #expr="(a=[]).toString='array';(1).toString;[a.toString,[].toString,(1).toString]";
  #expr="a=2;++a;++++a;--a;b=1;b++"
  #expr="[1]";
  #expr="a=1;puts('hello world')";
  #expr="printf('%05d',12)";

  # 文
  # 制御文 for
  # ラムダ式
  # 環境

  if((_s=ev3parse(expr))!=NULL){
    #print ev3obj_dump(_s);

    _v=ev3eval_expr(g_ctx,_s);
    #print "(" expr ") => " ev3obj_dump(ev3eval_lvalueRead(_v));
    ev3obj_release(_v);

  #ev3obj_univ_print();
    ev3obj_release(_s);
  }

  #print "_ctx.global = " ev3obj_dump(_ctx[EV3_CTXKEY_ROOT]);
}

BEGIN{
  ev3obj_initialize();
  ev3proto_initialize();
  ev3scan_initialize();
  ev3eval_initialize();
  ev3eval_context_initialize(g_ctx);
  #test_ev3parse();
}
NR!=1||!/^[[:space:]]*#/{
  #print ev3eval(g_ctx,$0);
  ev3eval(g_ctx,$0);
}
END{
  print_heap=ev3obj_tryGetMemberValue(g_ctx[EV3_CTXKEY_ROOT],"+__EV3_CHECK_HEAP__",FALSE);

  ev3eval_context_finalize(g_ctx);

  ev3eval_finalize();
  ev3scan_finalize();
  ev3proto_finalize();

  if(print_heap)ev3obj_univ_print();
}
