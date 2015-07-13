#
# ev3v2 Array
#

function ev3type_Array_prototype_splice(obj,args, _i,_c,_argc,_len,_ret,_shift,_s,_d,_ksrc){
  obj=ev3eval_rvalue(obj);
  _len=ev3eval_tonumber(ev3obj_getMemberPtr(obj,"+length"));
  _argc=ev3obj_getMemberValue(args,"+length");
  _i=int(ev3eval_tonumber(ev3obj_getMemberPtr(args,"+0")));
  if(_i<0)_i=0;else if(_i>_len)_i=_len;
  _c=1<_argc?int(ev3eval_tonumber(ev3obj_getMemberPtr(args,"+1"))):_len-_i;

  # create an array of the removed elements
  _ret=ev3proto_new(ev3type_Array_prototype);
  for(_d=0;_d<_c;_d++){
    _s=_i+_d;
    if((_ksrc=ev3obj_getMemberPtr(obj,"+" _s,EV3OBJ_MEMPTR_IFHAS)))
      ev3obj_setMemberObj(_ret,"+" _d,_ksrc);
  }
  ev3obj_setMemberScal(_ret,"+length",TYPE_NUM,_c);

  # shift the rest elements
  _shift=(_argc>2?_argc-2:0)-_c;
  if(_shift<0){
    for(_s=_i+_c;_s<_len;_s++){
      if((_ksrc=ev3obj_getMemberPtr(obj,"+" _s,EV3OBJ_MEMPTR_IFHAS)))
        ev3obj_setMemberObj(obj,"+" (_s+_shift),_ksrc);
      else
        ev3obj_unsetMember(obj,"+" (_s+_shift));
    }
    for(_d=_len+_shift;_d<_len;_d++)
      ev3obj_unsetMember(obj,"+" _d);
  }else if(_shift>0){
    for(_s=_len-1;_s>=_i+_c;_s--){
      if((_ksrc=ev3obj_getMemberPtr(obj,"+" _s,EV3OBJ_MEMPTR_IFHAS)))
        ev3obj_setMemberObj(obj,"+" (_s+_shift),_ksrc);
      else
        ev3obj_unsetMember(obj,"+" (_s+_shift));
    }
  }

  # assign values
  for(_s=2;_s<_argc;_s++){
    _d=_i+_s-2;
    ev3obj_setMemberObj(obj,"+" _d,ev3obj_getMemberPtr(args,"+" _s));
  }

  # update length
  ev3obj_setMemberScal(obj,"+length",TYPE_NUM,_len+_shift);
  return _ret;
}
function ev3type_Array_prototype_join(obj,args, _sep,_len,_i,_vret){
  obj=ev3eval_rvalue(obj);
  _sep=ev3obj_getMemberPtr(args,"+0",EV3OBJ_MEMPTR_IFHAS);
  _sep=_sep?ev3eval_tostring(_sep):",";
  _len=ev3eval_tonumber(ev3obj_getMemberPtr(obj,"+length"));
  _vret="";
  if(_len>0){
    _vret=ev3eval_tostring(ev3obj_getMemberPtr(obj,"+0",EV3OBJ_MEMPTR_IFHAS));
    for(_i=1;_i<_len;_i++)
      _vret=_vret _sep ev3eval_tostring(ev3obj_getMemberPtr(obj,"+" _i,EV3OBJ_MEMPTR_IFHAS));
  }
  return ev3obj_newScal(TYPE_STR,_vret);
}

function ev3type_Array_canonicalizeIndex(i,len){
  i=int(i);
  if(i<0){
    i+=len;
    if(i<0)i=0;
  }else if(i>len)
    i=len;
  return i;
}

function ev3type_Array_prototype_slice(obj,args, _len,_argc,_b,_e,_c,_i,_p){
  obj=ev3eval_rvalue(obj);
  _len=ev3eval_tonumber(ev3obj_getMemberPtr(obj,"+length"));
  _argc=ev3obj_getMemberValue(args,"+length");

  _b=0;_e=_len;
  if(0<_argc){
    _b=ev3eval_tonumber(ev3obj_getMemberPtr(args,"+0"));
    _b=ev3type_Array_canonicalizeIndex(_b,_len);

    if(1<_argc){
      _e=ev3eval_tonumber(ev3obj_getMemberPtr(args,"+1"));
      _e=ev3type_Array_canonicalizeIndex(_e,_len);
      if(_e<_b)_e=_b;
    }
  }
  _c=_e-_b;

  _ret=ev3proto_new(ev3type_Array_prototype);
  if(_c>0){
    ev3obj_setMemberScal(_ret,"+length",TYPE_NUM,_c);
    for(_i=0;_i<_c;_i++){
      if((_p=ev3obj_getMemberPtr(obj,"+" (_b+_i),EV3OBJ_MEMPTR_IFHAS)))
        ev3obj_setMemberObj(_ret,"+" _i,_p);
    }
  }
  return _ret;
}

function ev3type_Array_dispatch(obj,fname,args, _narg,_i,_ret){
  if(fname=="operator_index"){
    _narg=ev3obj_getMemberValue(args,"+length");
    _i=_narg>=1?int(ev3eval_tonumber(ev3obj_getMemberPtr(args,"+" (_narg-1)))):0;
    _ret=ev3obj_newScal(EV3_TYPE_LVALUE);
    ev3obj_setMemberScal(_ret,"obj",TYPE_REF,obj);
    ev3obj_setMemberScal(_ret,"memberName",TYPE_STR,"+" _i);
    return _ret;
  }else if(fname=="splice"){
    return ev3type_Array_prototype_splice(obj,args);
  }else if(fname=="join"){
    return ev3type_Array_prototype_join(obj,args);
  }else if(fname=="slice"){
    return ev3type_Array_prototype_slice(obj,args);
  }
}

## @param[in] world Array.prototype を定義する先のオブジェクトを指定します。
function ev3type_Array_initialize(world, _proto){
  _proto=ev3obj_placementNew(world,"Array.prototype");
  ev3obj_setMemberScal(_proto,"+splice",TYPE_NFUNC,"ev3type_Array_prototype_splice");
  ev3obj_setMemberScal(_proto,"+join",TYPE_NFUNC,"ev3type_Array_prototype_join");
  ev3obj_setMemberScal(_proto,"+slice",TYPE_NFUNC,"ev3type_Array_prototype_slice");
  ev3obj_setMemberScal(_proto,"+length",TYPE_NUM,0);
  #ev3obj_setMemberScal(_proto,"![]",TYPE_NFUNC,"ev3type_Array_prototype_operator_index");#■
  ev3type_Array_prototype=_proto;
}
