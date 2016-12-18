
function ev3obj_init(){
  TYPE_NUL =0;
  TYPE_REF =1; # shared_ref
  TYPE_REFW=2; # weak_ref
  TYPE_ERR =3; # error

  TYPE_NUM =11;
  TYPE_STR =12;
  TYPE_PTR =13; # shared_ptr
  TYPE_PTRW=14; # weak_ptr

  TYPE_ARR =21;
  TYPE_ARG =22;
  TYPE_OBJ =23;

  TYPE_MEM =4; # data member
  TYPE_MEMF=5; # member function
  TYPE_MEMU=6; # uninitialized member (write only member)

  # TYPE_HASH
  # TYPE_LIST
  # TYPE_FUN  function
  # TYPE_FUNM method
}

#------------------------------------------------------------------------------
# Fundamental operations

function ev3obj_internal_inc(ptr){
  if(ptr!=""&&ev3obj[ptr,"&"]>0)
    ev3obj[ptr,"&"]++;
}
function ev3obj_internal_dec(ptr){
  if(ptr!=""&&--ev3obj[ptr,"&"]<=0)
    ev3obj_free(ptr);
}
function ev3obj_internal_clear(ptr ,_type,_i,_iN,_p,_n){
  _type=ev3obj[ptr,"T"];
  if(_type==TYPE_ARR||_type==TYPE_ARG){
    for(_i=0,_iN=ev3obj[ptr];_i<_iN;_i++)
      ev3obj_free(ptr SUBSEP "." _i);
  }else if(_type==TYPE_OBJ){
    for(_i=0,_iN=ev3obj[ptr];_i<_iN;_i++){
      _n=ev3obj[ptr,"." _i];
      if(_n!="")
        ev3obj_free(ptr SUBSEP ".:" _n);
      delete ev3obj[ptr,"." _i];
    }
  }else if(_type==TYPE_REF){
    ev3obj_internal_dec(ev3obj[ptr]);
  }

  ev3obj[ptr,"T"]=TYPE_NUL;
}
function ev3obj_internal_copy(dst,src ,_type,_i,_iN){
  # dst must be empty

  ev3obj[dst]=ev3obj[src];
  ev3obj[dst,"T"]=ev3obj[src,"T"];

  _type=ev3obj[src,"T"];
  if(_type==TYPE_ARR||_type==TYPE_ARG){
    for(_i=0,_iN=ev3obj[src];_i<_iN;_i++)
      ev3obj_copy(dst SUBSEP "." _i,src SUBSEP "." _i);
  }else if(_type==TYPE_OBJ){
    ev3obj[dst]=0;
    for(_i=0,_iN=ev3obj[src];_i<_iN;_i++){
      _n=ev3obj[src,"." _i];
      if(_n=="")continue;

      ev3obj[dst,"." ev3obj[dst]++]=_n;
      ev3obj_copy(dst SUBSEP ".:" _n,src SUBSEP ".:" _n);
    }
  }else if(_type==TYPE_REF||_type==TYPE_PTR){
    ev3obj_internal_inc(ev3obj[src]);
  }
}

function ev3obj_internal_error(dst,msg){
  ev3obj[dst]=msg;
  ev3obj[dst,"T"]=TYPE_ERR;
  ev3obj_errno=dst;
}

function ev3obj_copy(dst,src ,_type,_i,_iN){
  ev3obj_internal_clear(dst);
  ev3obj_internal_copy(dst);
}
function ev3obj_alloc(_ret){
  _ret="h:" ev3obj_heap_count++;
  ev3obj[_ret,"T"]=TYPE_NUL;
  ev3obj[_ret,"&"]=1;
  return _ret;
}
function ev3obj_free(ptr ,_type,_i,_iN,_p,_n){
  ev3obj_internal_clear(ptr);
  delete ev3obj[ptr];
  delete ev3obj[ptr,"T"];
  delete ev3obj[ptr,"&"];
}
function ev3obj_clone(ptr,_ret){
  _ret=ev3obj_alloc();
  ev3obj_copy(_ret,ptr);
  return _ret;
}
#------------------------------------------------------------------------------
function ev3obj_rvalue(ptr ,_type){
  _type=ev3obj[ptr,"T"];
  if(_type==TYPE_REF||_type==TYPE_REFW)
    return ev3obj[ptr];
  if(_type==TYPE_ARG)
    return ptr SUBSEP "." ev3obj[ptr]-1;
  return ptr;
}
function ev3obj_raw_int(ptr){
  ptr=ev3obj_rvalue(ptr);
  _type=ev3obj[ptr,"T"];
  if(_type==TYPE_NUM)
    return int(ev3obj[ptr]);
  else
    return 0;
}
function ev3obj_ref_create(dst,ptr){
  ev3obj_internal_inc(ptr);
  ev3obj[dst]=ptr;
  ev3obj[dst,"T"]=TYPE_REF;
}


function ev3obj_obj_getptr(ptr,mem){
  if(ev3obj[ptr]!=TYPE_OBJ)
    ev3obj_internal_error(dst,"type_error: not object"); # BUG: dst?
  if(!((ptr SUBSEP ".:" mem SUBSEP "T") in ev3obj))
    ev3obj_internal_error(dst,"no member named '" mem "'");
  return ptr SUBSEP ".:" mem;
}
function ev3obj_obj_set(ptr,mem,src ,_pmem){
  if(ev3obj[ptr]!=TYPE_OBJ)
    ev3obj_internal_error(dst,"type_error: not object");

  _pmem=ptr SUBSEP ".:" mem;
  if(!((_pmem SUBSEP "T") in ev3obj)){
    ev3obj_internal_clear(_pmem);
  }else{
    ev3obj[ptr,"." ev3obj[ptr]++]=mem;
  }
  ev3obj_internal_copy(_pmem,src);
}

function ev3obj_setval(ptr,value,type){
  ev3obj[ptr]=value;
  ev3obj[ptr,"T"]=type;
}

#==============================================================================
# Scan

function ev3scan_init_operator(opname,optype,opprec){
  ev3scan_op[opname]=optype;
  ev3scan_op[opname,"p"]=opprec;
}

function ev3scan_init(){
  OP_BIN=1;
  OP_UNA=2; # prefix
  OP_SGN=3; # prefix or binary
  OP_INC=4; # prefix or suffix

  OP_OPN=5; # left bracket
  OP_CLS=6; # right bracket

  OP_NUM=10; # number literal
  OP_NAM=11; # identifier
  OP_STR=11; # string literal

  ev3scan_init_op("." ,OP_BIN,12.0);

  ev3scan_init_op("++",OP_INC,11.0);
  ev3scan_init_op("--",OP_INC,11.0);
  ev3scan_init_op("!" ,OP_UNA,11.0);

  ev3scan_init_op("*" ,OP_BIN,10.0);ev3scan_init_op("/" ,OP_BIN,10.0);ev3scan_init_op("%" ,OP_BIN,10.0);
  ev3scan_init_op("+" ,OP_SGN,9.0);ev3scan_init_op("-" ,OP_SGN,9.0);
  ev3scan_init_op("<<",OP_SGN,8.0);ev3scan_init_op(">>",OP_SGN,8.0);

  ev3scan_init_op("==",OP_BIN,6.0);ev3scan_init_op("!=",OP_BIN,6.0);
  ev3scan_init_op("<" ,OP_BIN,6.0);ev3scan_init_op(">" ,OP_BIN,6.0);
  ev3scan_init_op("<=",OP_BIN,6.0);ev3scan_init_op(">=",OP_BIN,6.0);

  ev3scan_init_op("&" ,OP_BIN,5.4);ev3scan_init_op("^" ,OP_BIN,5.2);ev3scan_init_op("|" ,OP_BIN,5.0);
  ev3scan_init_op("&&",OP_BIN,4.4);ev3scan_init_op("||",OP_BIN,4.0);

  # ?: 3.0

  ev3scan_init_op("=" ,OP_BIN,2.0);
  ev3scan_init_op("*=",OP_BIN,2.0);ev3scan_init_op("/=",OP_BIN,2.0);ev3scan_init_op("%=",OP_BIN,2.0);
  ev3scan_init_op("+=",OP_BIN,2.0);ev3scan_init_op("-=",OP_BIN,2.0);
  ev3scan_init_op("<<=",OP_BIN,2.0);ev3scan_init_op(">>=",OP_BIN,2.0);
  ev3scan_init_op("|=",OP_BIN,2.0);ev3scan_init_op("^=",OP_BIN,2.0);ev3scan_init_op("&=",OP_BIN,2.0);
  ev3scan_init_op("," ,OP_BIN,1.0);
  ev3scan_op["=","r"]=1;
  ev3scan_op["*=","r"]=1;ev3scan_op["/=","r"]=1;ev3scan_op["%=","r"]=1;
  ev3scan_op["+=","r"]=1;ev3scan_op["-=","r"]=1;ev3scan_op["-=","r"]=1;
  ev3scan_op["<<=","r"]=1;ev3scan_op[">>=","r"]=1;
  ev3scan_op["|=","r"]=1;ev3scan_op["^=","r"]=1;ev3scan_op["&=","r"]=1;

  ev3scan_init_op("(" ,OP_OPN);ev3scan_init_op(")" ,OP_CLS);
  ev3scan_init_op("[" ,OP_OPN);ev3scan_init_op("]" ,OP_CLS);
  ev3scan_init_op("{" ,OP_OPN);ev3scan_init_op("}" ,OP_CLS);
  ev3scan_init_op("?" ,OP_OPN);ev3scan_init_op(":" ,OP_CLS);

  SE_NULL=0;
  SE_VALU=1;
  SE_PREF=2;
  SE_MARK=3;

  # ATTR_SET="t";
  # ATTR_TYP="T";
  # ATTR_MOD="M";
}

function ev3scan(expression,words, _wlen,_i,_len,_c,_t,_w){
  _wlen=0;
  _len=length(expression);
  for(_i=0;_i<_len;_i++){
    _c=substr(expression,_i+1,1);

    if(_c ~ /[.0-9]/){
      # TODO: 0xFF
      # TODO: 0777
      # TODO: 1e10 1e+10 1e-10
      for(_w=_c;_i+1<_len;_i++){
        _c=substr(expression,_i+2,1);
        if(_c !~ /[.0-9]/)break;
        _w=_w _c;
      }

      _t=_w=="."?OP_BIN:OP_NUM;
    }else if(ev3scan_op[_c]!=""){
      for(_w=_c;_i+1<_len;_i++){
        _c=substr(expression,_i+2,1);
        if(ev3scan_op[_w _c]=="")break;
        _w=_w _c;
      }

      _t=ev3scan_op[_w];
    }else if(_c ~ /[_a-zA-Z]/){
      for(_w=_c;_i+1<_len;_i++){
        _c=substr(expression,_i+2,1);
        if(_c !~ /[_a-zA-Z0-9]/)break;
        _w=_w _c;
      }

      _t=OP_NAM;
    }else if(_c=="\""){
      _w="";
      while(_i+1<_len){
        _c=substr(expression,_i+2,1);
        _i++;
        if(_c=="\"")break;

        if(_c=="\\"){
          # TODO: \xFF
          # TODO: \uFFFF
          # TODO: \777
          if(_i+1<_len){
            _w=_w ev3scan_escchar(substr(expression,_i+2,1));
            _i++;
          }else{
            _w=_w _c;
          }
        }else{
          _w=_w _c;
        }
      }

      _t=OP_STR;
    }else if(_c ~ /[[:space:]]/){
      continue; # ignore blank
    }else{
      print_error("mwg_pp.ev3scan","unrecognized character '" _c "'");
      continue; # ignore unknown character
    }

    words[_wlen,"t"]=_t;
    words[_wlen,"w"]=_w;
    _wlen++;
  }

  # debug
  #for(_i=0;_i<_wlen;_i++){
  #    print "yield " words[_i,"w"] " as " words[_i,"t"] > "/dev/stderr"
  #}

  return _wlen;
}

function ev3scan_escchar(c){
  if(c !~ /nrtvfaeb/)return c;
  if(c=="n")return "\n";
  if(c=="r")return "\r";
  if(c=="t")return "\t";
  if(c=="v")return "\v";
  if(c=="f")return "\f";
  if(c=="a")return "\a";
  if(c=="e")return "\33";
  if(c=="b")return "\b";
  return c;
}

#==============================================================================

function ev3parse_push(sid,value,type,stype ,_ptr){
  _ptr=sid ":" ++ev3obj[sid];
  ev3obj[_ptr]=value;
  ev3obj[_ptr,"T"]=value;
  ev3obj[_ptr,"&"]=1;
  ev3obj[_ptr,"+t"]=stype;
  return _ptr;
}

function ev3parse_top_stype(sid ,_sp){
  _sp=ev3obj[sid];
  return _sp>=0?ev3obj[sid ":" _sp,"+t"]:SE_NULL;
}

function ev3parse_se_free(sp){
  ev3obj_free(sp);
  delete ev3obj[sp,"+ot"];
  delete ev3obj[sp,"+ow"];
  delete ev3obj[sp,"+op"];
}
function ev3parse_pop(sid ,_sl,_sp){
  _sl=ev3obj[sid];
  if(_sl<0)return;
  ev3obj_se_free(sid ":" _sl);
  ev3obj[sid]--;
}

function ev3parse(expression, _wlen,_words,_i,_len,_t,_w,_sid,_p,_sp,_sp1,_sp2,_sl,_stype,_v, _stk){
  _wlen=ev3scan(expression,_words);

  # kakikae
  #  _stk -> _s[0] # stkid e.g. "s0:"
  #  _sp  -> _s[1] # stkid e.g. "_sp"

  # parse
  _sid="s0"; # TODO "s" ev3parse_stack_level++ ":"
  ev3obj[_sid]=-1;
  for(_i=0;_i<_wlen;_i++){
    # _t: token type
    # _w: token word
    # _p: token prefix level
    _t=_words[_i,"t"];
    _w=_words[_i,"w"];

    if(_t==OP_SGN){
      if(ev3parse_top_stype(_sid)==SE_VALU)
        _t=OP_BIN; # binary operator
      else
        _t=OP_UNA; # unary operator
    }else if(_t==OP_INC){
      if(ev3parse_top_stype(_sid)!=SE_VALU)
        _t=OP_UNA; # unary operator
    }

    #-- process token --
    if(_t==OP_NUM){
      ev3parse_push(_sid,+_w,TYPE_NUM,SE_VALU);
    #---------------------------------------------------------------------------
    }else if(_t==OP_BIN){
      # binary operator
      _p=ev3scan_op[_w,"p"];
      # get lhs
      if(ev3scan_op[_w,"r"])
        _sp=ev3parse_pop_value(_stk,_p+0.1); # right assoc
      else
        _sp=ev3parse_pop_value(_stk,_p); # left assoc

      # overwrite to lhs
      ev3obj[_sp,"+t"]=SE_PREF;
      ev3obj[_sp,"+ot"]=_t;
      ev3obj[_sp,"+ow"]=_w;
      ev3obj[_sp,"+op"]=_p;
    }else if(_t==OP_UNA){
      # unary operator
      _p=ev3scan_op[_w,"a"];

      _sp=ev3parse_push(_sid,0,TYPE_NUL,SE_PREF);
      ev3obj[_sp,"+ot"]=_t;
      ev3obj[_sp,"+ow"]=_w;
      ev3obj[_sp,"+op"]=_p;
    }else if(_t==OP_INC){
      _sp=_sid ":" ev3obj[_sid];
      if(ev3obj[_sp,"T"]=TYPE_REF||ev3obj[_sp,"T"]==TYPE_REFW){
        _sp2=ev3obj[_sp];
        ev3obj_internal_inc(_sp2);
        ev3obj_internal_clear(_sp);
        ev3obj_internal_copy(_sp,_sp2);
        ev3obj_internal_dec(_sp2);
        ev3parse_op_inc(_w,_sp2);
      }

      _t="";
    }else if(_t==OP_OPN){
      _sp=ev3parse_push(_sid,0,TYPE_NUL,SE_MARK);
      ev3obj[_sp,"+ot"]=_t;
      ev3obj[_sp,"+ow"]=_w;
    }else if(_t==OP_CLS){
      _stype=ev3parse_top_stype(_sid);
      if(_stype==SE_VALU){
        _sp1=ev3parse_pop_value(_sid,0);
        _sl=ev3obj[_sid];
        _sp=_sid ":" _sl-1;
        if(!(_sl>=1&&ev3obj[_sp,"+t"]==SE_MARK)){
          print_error("mwg_pp.ev3:syntax","no matching open paren to " _w " in " expression);
          continue;
        }
      }else if(_stype==SE_MARK){
        # empty arg
        _sp1=ev3parse_push(_sid,0,TYPE_ARG,SE_VALU);
        _sl=ev3obj[_sid];
        _sp=_sid ":" _sl-1;
      }else{
        print_error("mwg_pp.ev3:syntax","unexpected right bracket '" _w "' in " expression);
        continue;
      }
      # state: [.. _sp(=open) _sp1]

      # parentheses
      _w=ev3obj[_sp,"+ow"] _w; # "()" "[]" etc
      if(_sl>=2&&ev3obj[_sid ":" _sl-2,"+t"]==SE_VALU){

        if(_w=="?:"){ # conditional operation
          ev3obj[sid]=_sl-2;
          _sp2=ev3parse_pop_value(_sid,3.0); # assoc_value_3
          # state: [ ... _sp2] ... _sp(=open) _sp1
          #   _sp and _sp1 must be released manually

          _v=(ev3obj[_sp2]!=0&&ev3obj[_sp2]!=""); # TODO: bool
          _w=(_v?"T":"F") _w;

          if(_v){
            ev3obj_internal_clear(_sp2);
            ev3obj_internal_copy(_sp2,_sp1);
            ev3obj[_sp2,"+ot"]=SE_PREF;
            ev3obj[_sp2,"+ow"]=_w; "T?:"
            ev3obj[_sp2,"+op"]=3.0; # level
          }else{
            ev3parse_pop(_sp2);
          }

          ev3parse_se_free(_sp);
          ev3parse_se_free(_sp1);
        }else{ # function call/member access
          ev3obj[sid]=_sl-2;
          _sp2=ev3parse_pop_value(_sid,12.0); # assoc_value_12
          # state: [ ... _sp2] ... _sp(=open) _sp1
          #   _sp and _sp1 must be released manually

          ev3parse_op_call(_sp2,_w,_sp2,_sp1);
          ev3parse_se_free(_sp);
          ev3parse_se_free(_sp1);
        }
      }else{
        ev3obj_internal_clear(_sp);

        if(_w=="[]"){
          # array
          if(ev3obj[_sp1,"T"]==TYPE_ARG){
            ev3obj_internal_copy(_sp,_sp1);
            ev3obj[_sp,"T"]=TYPE_ARR;
          }else{
            ev3obj[_sp]=1;
            ev3obj[_sp,"T"]=TYPE_ARR;
            ev3obj_internal_copy(_sp SUBSEP "." 0,_sp1);
          }
        }else{
          if(ev3obj[_sp1,"T"]==TYPE_ARG){
            # last element
            if(ev3obj[_sp1]>0)
              ev3obj_internal_copy(_sp,_sp1 SUBSEP "." ev3obj[_sp1]-1);
          }else{
            ev3obj_internal_copy(_sp,_sp1);
          }
        }

        ev3parse_pop(_sid);
      }
    #---------------------------------------------------------------------------
    }else if(_t==OP_NAM){
      ev3parse_push(_sid,_w,TYPE_TOK,SE_VALU);
    }else if(_t==OP_STR){
      ev3parse_push(_sid,_w,TYPE_STR,SE_VALU);
    }else{
      print_error("mwg_pp.ev3:fatal","unknown token type " _t);
    }
  }

  # TODO copy to dst
  ev3parse_pop_value(_sid,0);
  return ev3obj[_sid]>=1?"err":ev3obj[_sid ":" 0];
}

# i++ i--
function ev3parse_op_inc(w,ptr ,_T,_p){
  _ptr=ev3obj_rvalue(ptr);
  if(ptr!=_ptr){
    # reference
    _T=ev3obj[_ptr,"T"];
    if(_T=TYPE_NUM){
      if(w=="++")
        ev3obj[ptr]++;
      else if(w=="--")
        ev3obj[ptr]--;
      else
        print_error("mwg_pp.ev3:fatal","unknown increment operator " w);
    }else{
      print_error("mwg_pp.ev3:type","type(" _T ")::operator" w);
    }
  }else{
    # value (do nothing)
  }
}

function ev3parse_op_call(dst,w,pobj,parg ,_pobj,_isref,_T,_i,_p){
  if(w=="[]"){
    _pobj=ev3obj_rvalue(pobj);
    _isref=pobj!=_pobj;

    _T=ev3obj[_pobj,"T"];
    if(_T==TYPE_ARR){
      _i=ev3obj_raw_int(parg);
      if(0<=_i&&_i<ev3obj[_pobj]){
        if(isref){
          ev3obj_internal_clear(dst);
          ev3obj_create_ref(dst,_pobj SUBSEP "." _i);
        }else{
          # value
          if(dst==_pobj){
            _p=ev3obj_alloc();
            ev3obj_internal_copy(_p,_pobj SUBSEP "." _i);
            ev3obj_internal_clear(dst);
            ev3obj_internal_copy(dst,_p);
            ev3obj_free(_p);
          }else{
            ev3obj_internal_clear(dst);
            ev3obj_internal_copy(dst,_pobj SUBSEP "." _i);
          }
        }
      }else{
        print_error("mwg_pp.ev3:runtime","array_index_out_of_range");
      }
    }else if(_T==TYPE_OBJ){
      _i=ev3obj_raw_int(_pobj);

    }else{
      print_error("mwg_pp.ev3:type","type(" _T ")::operator" w);
    }
  }else if(w=="()"){

  }else{
    print_error("mwg_pp.ev3:type","unknown type of function call '" w "' in " expression);
  }

  if(_w=="[]"&&and(ev3obj[_sp2,"M"],MOD_REF)){
    # indexing
    ev3obj[_sp2]=d_data[ev3obj[_sp2,"R"],ev3obj[_sp1]];
    ev3obj[_sp2,"t"]=SE_VALU;
    ev3obj[_sp2,"T"]=(ev3obj[_sp2]==0+ev3obj[_sp2]?TYPE_NUM:TYPE_STR);
    ev3obj[_sp2,"M"]=MOD_REF;
    ev3obj[_sp2,"R"]=ev3obj[_sp2,"R"] SUBSEP ev3obj[_sp1];
  }else if(and(ev3obj[_sp2,"M"],MOD_REF)){
    # function call
    ev2_funcall(ev3obj,_sp2,ev3obj[_sp2,"R"],ev3obj,_sp1);
  }else if(and(ev3obj[_sp2,"M"],MOD_MTH)){
    # member function call
    ev2_memcall(ev3obj,_sp2,ev3obj,_sp2 SUBSEP ATTR_MTH_OBJ,ev3obj[_sp2,ATTR_MTH_MEM],ev3obj,_sp1);
  }else{
    print_error("mwg_pp.eval","invalid function call " ev3obj[_sp2] " " _w " in " expression)
  }
}

function ev3parse_pop_value(sid,prec){

  # return _ptr_stack_top=_ptr_result
}
