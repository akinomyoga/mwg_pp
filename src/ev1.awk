# -*- mode:awk -*-

# public
#   function eval_expr(expression);
#
# internal
#   function ev_apply(cmd,arg,value);
#   function ev_pop_value(s,level);

function eval_expr(expression, _wlen,_words,_i,_len,_t,_w,_v,_sp,_s){
  _wlen=ev1scan_scan(expression,_words);

  # parse
  _sp=-1;
  for(_i=0;_i<_wlen;_i++){
    # _t: token type
    # _w: token word
    # _l: token prefix level
    _t=_words[_i,"t"];
    _w=_words[_i,"w"];

    #-- operator context --
    if(_t=="o"){
      if(_w ~ /^[-+]$/){
        if(_sp>=0&&_s[_sp,"t"]=="value"){
          _t="b"; # binary operator
          _w="b" _w;
          _l=4;
        }else{
          _t="u"; # unary operator
          _w="u" _w;
        }
      }else if(ev_db_operator[_w,"a"]!=""){ # binary operator
        _l=ev_db_operator[_w,"a"];
        _t="b";_w="b" _w;
        #print "dbg: binary operator level = " _l > "/dev/stderr"
      }else if(_w ~ /^!$/){
        _t="u";_w="u" _w;
      }
    }

    #-- process token --
    if(_t=="n"){
      _sp++;
      _s[_sp,"t"]="value";
      _s[_sp,"v"]=_w;
    }else if(_t=="b"){
      # binary operator

      _s["sp"]=_sp;
      _v=ev_pop_value(_s,_l); # left associative
      # _v=ev_pop_value(_s,_l+0.1); # right associative
      _sp=_s["sp"];

      _sp++;
      _s[_sp,"t"]="prefix";
      _s[_sp,"c"]=_w; # operator
      _s[_sp,"l"]=_l; # level
      _s[_sp,"v"]=_v; # lhs
    }else if(_t=="u"){
      # unary operator
      _sp++;
      _s[_sp,"t"]="prefix"
      _s[_sp,"c"]=_w; # operator
      _s[_sp,"l"]=3;  # level
    }else if(_t=="op"){
      _sp++;
      _s[_sp,"t"]="open";
      _s[_sp,"c"]=_w;
    }else if(_t=="cl"){
      _s["sp"]=_sp;
      _v=ev_pop_value(_s,0);
      _sp=_s["sp"];

      if(!(_sp>=0&&_s[_sp,"t"]=="open")){
        print "mwg_pp.eval: no matching open paren to " _w " in " expression > "/dev/stderr"
        continue;
      }

      _w=_s[_sp,"w"] _w;
      _sp--;

      if(_w=="[]")_v=int(_v);
            
      _sp++;
      _s[_sp,"t"]="value";
      _s[_sp,"v"]=_v;
    }else if(_t=="w"){
      _w=d_data[_w];
      #_w=0+_w;

      _sp++;
      _s[_sp,"t"]="value";
      _s[_sp,"v"]=_w;
    }else if(_t=="v"){
      # some values (string, etc)
      _sp++;
      _s[_sp,"t"]="value";
      _s[_sp,"v"]=_w;
    }else{
      print "\33[1;31mmwg_pp.eval:internal:\33[m unknown token type " _t > "/dev/stderr"
    }
  }

  _s["sp"]=_sp;
  _v=ev_pop_value(_s,0);
  _sp=_s["sp"];

  if(_sp>=0)_v="err";
  return _v;
}

function ev_apply(cmd,arg,value){
  if(cmd ~ /^b/){
    cmd=substr(cmd,2);
    #print "binary " arg " " cmd " " value > "/dev/stderr"
    if(cmd=="+")return arg+value;
    if(cmd=="-")return arg-value;
    if(cmd=="*")return arg*value;
    if(cmd=="/")return arg/value;
    if(cmd=="==")return arg==value;
    if(cmd=="!=")return arg!=value;
    if(cmd==">=")return arg>=value;
    if(cmd=="<=")return arg<=value;
    if(cmd=="<")return arg<value;
    if(cmd==">")return arg>value;
    if(cmd=="|")return or(arg,value);
    if(cmd=="^")return xor(arg,value);
    if(cmd=="&")return and(arg,value);
    #print "dbg: left=" arg " , right=" value ", result=" (ev1scan_cast_bool(arg)||ev1scan_cast_bool(value)) > "/dev/stderr"
    if(cmd=="||")return ev1scan_cast_bool(arg)||ev1scan_cast_bool(value); # not lazy evaluation
    if(cmd=="&&")return ev1scan_cast_bool(arg)&&ev1scan_cast_bool(value); # not lazy evaluation
  }else if(cmd ~ /^u/){
    cmd=substr(cmd,2);
    if(cmd=="+")return value;
    if(cmd=="-")return -value;
    if(cmd=="!")return !ev1scan_cast_bool(value);
  }

  return value;
}

function ev_pop_value(s,level, _sp,_value){
  _sp=s["sp"];

  # read value
  if(_sp>=0&&s[_sp,"t"]=="value"){
    _value=s[_sp,"v"];
    _sp--;
  }else{
    _value=0;
  }

  # proc prefices
  while(_sp>=0&&s[_sp,"t"]=="prefix"&&s[_sp,"l"]>=level){
    _value=ev_apply(s[_sp,"c"],s[_sp,"v"],_value);
    _sp--;
  }

  s["sp"]=_sp;
  #print "debug: pop '" _value "'" > "/dev/stderr"
  return _value;
}
