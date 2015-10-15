#!/usr/bin/gawk -f

# 20120726 行番号出力機能 (例: '#line 12 a.cpp')

function awk_getfiledir(_ret){
  _ret=m_lineno_cfile;
  sub(/[^\/\\]+$/,"",_ret);
  if(_ret=="/")return "/";
  sub(/[\/\\]$/,"",_ret);
  return _ret
}

function print_error(title,msg){
  global_errorCount++;
  print "\33[1;31m" title "!\33[m " msg > "/dev/stderr"
}

function trim(text){
  #gsub(/^[ \t]+|[ \t]+$/,"",text);
  gsub(/^[[:space:]]+|[[:space:]]+$/,"",text);
  return text
}

function slice(text,start,end, _l){
  _l=length(text);
  if(start<0)start+=_l;
  end=end==null?_l: end<0?end+_l: end;

  return substr(text,start+1,end-start);
}

#function head_token(text,ret,  _i,_l){
#  _i=match(text,/[^-a-zA-Z\:0-9_]/);
#  _l=_i?_i-1:length(text);
#  ret[0]=trim(substr(text,1,_l));
#  ret[1]=trim(substr(text,_l+1));
#}

#-------------------------------------------------------------------------------
function unescape(text, _ret,_capt){
  _ret="";
  while(match(text,/\\(.)/,_capt)>0){
    _ret=_ret substr(text,1,RSTART-1) _capt[1];
    text=substr(text,RSTART+RLENGTH);
  }
  return _ret text;
}

#-------------------------------------------------------------------------------
# replace
function replace(text,before,after, _is_tmpl,_is_head,_captures,_rep,_ltext,_rtext){
  _is_tmpl=(match(after,/\$[0-9]+/)>0);
  _is_head=(substr(before,1,1)=="^");

  _ret="";
  while(match(text,before,_captures)>0){
    _ltext=substr(text,1,RSTART-1);
    _rtext=substr(text,RSTART+RLENGTH);

    _rep=_is_tmpl?rep_instantiate_tmpl(after,_captures):after;

    _ret=_ret _ltext _rep;
    text=_rtext;

    if(_is_head)break;
    if(RLENGTH==0){
      _ret=_ret substr(text,1,1);
      text=substr(text,2);
      if(length(text)==0)break;
    }
  }
  return _ret text;
}
function rep_instantiate_tmpl(text,captures,  _ret,_num,_insert){
  _ret="";
  while(match(text,/\\(.)|\$([0-9]+)/,_num)){
    #print "dbg: $ captured: RSTART=" RSTART "; num=" _num[1] "; captures[num]=" captures[_num[1]] > "/dev/stderr"
    if(_num[2]!=""){
      _insert=captures[_num[2]];
    }else if(_num[1]~/^[$\\]$/){
      _insert=_num[1];
    }else{
      _insert=_num[0];
    }
    _ret=_ret substr(text,1,RSTART-1) _insert;
    text=substr(text,RSTART+RLENGTH);
  }
  return _ret text;
}

#===============================================================================
#  mwg_pp.eval
#-------------------------------------------------------------------------------
# function eval_expr(expression);

#%include ev1scan.awk
#%#include ev1.awk
#%include ev2.awk

#===============================================================================
#  Parameter Expansion
#-------------------------------------------------------------------------------
function inline_expand(text, _ret,_ltext,_rtext,_mtext,_name,_r,_s,_a,_caps){
  _ret="";
  while(match(text,/\${([^{}]|\\.)+}|\$"([^"]|\\.)+"/)>0){
    _ltext=substr(text,1,RSTART-1);
    _mtext=substr(text,RSTART,RLENGTH);
    _rtext=substr(text,RSTART+RLENGTH);
    _name=unescape(slice(_mtext,2,-1));
    if(match(_name,/^[-a-zA-Z0-9_]+$/)>0){                     # ${key}
      _r="" d_data[_name];
    }else if(match(_name,/^[-a-zA-Z0-9_]+\:-/)>0){             # ${key:-alter}
      _s["key"]=slice(_name,0,RLENGTH-2);
      _s["alter"]=slice(_name,RLENGTH);
      _r="" d_data[_s["key"]];
      if(_r=="")_r=_s["alter"];
    }else if(match(_name,/^[-a-zA-Z0-9_]+\:\+/)>0){            # ${key:+value}
      _s["key"]=slice(_name,0,RLENGTH-2);
      _s["value"]=slice(_name,RLENGTH);
      _r="" d_data[_s["key"]];
      _r=_r==""?"":_s["value"];
    }else if(match(_name,/^[-a-zA-Z0-9_]+\:\?/)>0){            # ${key:?warn}
      _s["key"]=slice(_name,0,RLENGTH-2);
      _s["warn"]=slice(_name,RLENGTH);
      _r="" d_data[_s["key"]];
      if(_r==""){
        print "(parameter expansion:" _mtext ")! " _s["warn"] > "/dev/stderr"
        _ltext=_ltext _mtext;
        _r="";
      }
    }else if(match(_name,/^([-a-zA-Z0-9_]+)\:([0-9]+)\:([0-9]+)$/,_caps)>0){ # ${key:start:length}
      _r=substr(d_data[_caps[1]],_caps[2]+1,_caps[3]);
    }else if(match(_name,/^([-a-zA-Z0-9_]+)(\/\/?)(([^/]|\\.)+)\/(.*)$/,_caps)>0){ # ${key/before/after}
      _r=d_data[_caps[1]];
      if(_caps[3]=="/")
        sub(_caps[3],_caps[5],_r);
      else
        gsub(_caps[3],_caps[5],_r);
    }else if(match(_name,/^([-a-zA-Z0-9_]+)(##?|%%?)(.+)$/,_caps)>0){ # ${key#head} ${key%tail}
      if(length(_caps[2])==2){
        # TODO
        gsub(/\./,/\./,_caps[3]);
        gsub(/\*/,/.+/,_caps[3]);
        gsub(/\?/,/./,_caps[3]);
      }
      if(_caps[2]=="#"||_caps[2]=="##"){
        _caps[3]="^" _caps[3];
      }else{
        _caps[3]=_caps[3] "$";
      }

      _r=d_data[_caps[1]];
      sub(_caps[3],"",_r);
    }else if(match(_name,/^\#[-a-zA-Z0-9_]+$/)>0){             # ${#key}
      _r=length("" d_data[substr(_name,2)]);
    }else if(match(_name,/^([-a-zA-Z0-9_]+)(\..+)$/,_caps)>0){ # ${key.modifiers}
      _r=modify_text(d_data[_caps[1]],_caps[2]);
    }else if(match(_name,/^\.[-a-zA-Z0-9_]+./)>0){             # ${.function:args...}
      match(_name,/^\.[-a-zA-Z0-9_]+./);
      _s["i"]=RLENGTH;
      _s["func"]=substr(_name,2,_s["i"]-2);
      _s["sep"] =substr(_name,_s["i"],1);
      _s["args"]=substr(_name,_s["i"]+1);
      _s["argc"]=split(_s["args"],_a,_s["sep"]);
      if(_s["func"]=="for"&&_s["argc"]==5){
        _r=inline_function_for(_a);
      }else if(_s["func"]=="sep_for"&&_s["argc"]==5){
        _r=inline_function_sepfor(_a);
      }else if(_s["func"]=="for_sep"&&_s["argc"]==5){
        _r=inline_function_forsep(_a);
      }else if(_s["func"]=="eval"&&_s["argc"]==1){
        _r=inline_function_eval(_a);
      }else{
        print "(parameter function:" _s["func"] ")! unrecognized function." > "/dev/stderr"
        _r=_mtext;
      }
    }else{
      print "(parameter expansion:" _mtext ")! unrecognized expansion." > "/dev/stderr"
      _r=_mtext;
    }
        
    if(_mtext ~ /^\${/){
      # enable re-expansion ${}
      _ret=_ret _ltext;
      text=_r _rtext;
    }else{
      # disable re-expansion $""
      _ret=_ret _ltext _r;
      text=_rtext;
    }
  }
  return _ret text;
}

function inline_function_forsep(args,  _r,_sep){
  _sep=args[5];
  _r=inline_function_for(args);
  return _r==""?"":_r _sep;
}
function inline_function_sepfor(args,  _r,_sep){
  _sep=args[5];
  _r=inline_function_for(args);
  return _r==""?"":_sep _r;
}
function inline_function_for(args, _rex_i,_i0,_iM,_field,_sep,_i,_r,_t){
  # ${for:%i%:1:9:typename A%i%:,}
  _rex_i=args[1];
  _i0=int(eval_expr(args[2]));
  _iM=int(eval_expr(args[3]));
  _field=args[4];
  _sep=args[5];

  _r="";
  for(_i=_i0;_i<_iM;_i++){
    _t=_field;
    gsub(_rex_i,_i,_t);
    _r=_i==_i0?_t:_r _sep _t;
  }
  return _r;
}
function inline_function_eval(args){
  return eval_expr(args[1]);
}

#===============================================================================
#   mwg.pp text modification
#-------------------------------------------------------------------------------
function modify_text__replace0(text,before,after,flags){
  if(index(flags,"R")){
    return replace(text,before,after);
  }else{
    gsub(before,after,text);
    return text;
  }
}

function modify_text__replace(content,before,after,flags){
  if(index(flags,"m")){
    _jlen=split(content,_lines,"\n");
    content=modify_text__replace0(_lines[1],before,after,flags);
    #print_error("mwg_pp(modify_text)","replace('" _lines[1] "','" before "','" after "') = '" content "'");
    for(_j=1;_j<_jlen;_j++)
      content=content "\n" modify_text__replace0(_lines[_j+1],before,after,flags);
  }else{
    content=modify_text__replace0(content,before,after,flags);
  }
  return content;
}

function modify_text(content,args, _len,_i,_m,_s,_c, _j,_jlen,_lines){
  # _len: length of args
  # _i: index in args
  # _c: current character in args
  # _m: current context mode in args
  # _s: data store

  _m="";
  _len=length(args);
  for(_i=0;_i<_len;_i++){
    _c=substr(args,_i+1,1);
    #-------------------------------------------------
    if(_m=="c"){
      if(_c=="r"||_c=="R"){
        _m="r0";
        _s["flags"]=_c=="R"?_c:"";
        _s["sep"]="";
        _s["rep_before"]="";
        _s["rep_after"]="";
      }else if(_c=="f"){
        _m="f0";
        _s["sep"]="";
        _s["for_var"]="";
        _s["for_begin"]="";
        _s["for_end"]="";
      }else if(_c=="i"){
        content=inline_expand(content);
        _m="";
      }else{
        print "unrecognized expand fun '" _c "'" > "/dev/stderr"
      }
    #-------------------------------------------------
    # r, R: replace
    }else if(_m=="r0"){
      _s["sep"]=_c;
      _m="r1";
    }else if(_m=="r1"){
      if(_c==_s["sep"]){
        _m="r2";
      }else{
        _s["rep_before"]=_s["rep_before"] _c;
      }
    }else if(_m=="r2"){
      if(_c==_s["sep"]){

        # check flag m
        _c=substr(args,_i+2,1);
        if(_c=="m"){
          _s["flags"]=_s["flags"] "m";
          _i++;
        }

        content=modify_text__replace(content,_s["rep_before"],_s["rep_after"],_s["flags"]);
        _m="";
      }else{
        _s["rep_after"]=_s["rep_after"] _c;
      }
    #-------------------------------------------------
    # f: for
    }else if(_m=="f0"){
      _s["sep"]=_c;
      _m="f1";
    }else if(_m=="f1"){
      if(_c!=_s["sep"]){
        _s["for_var"]=_s["for_var"] _c;
      }else{
        _m="f2";
      }
    }else if(_m=="f2"){
      if(_c!=_s["sep"]){
        _s["for_begin"]=_s["for_begin"] _c;
      }else{
        _s["for_begin"]=int(eval_expr(_s["for_begin"]));
        _m="f3";
      }
    }else if(_m=="f3"){
      if(_c!=_s["sep"]){
        _s["for_end"]=_s["for_end"] _c;
      }else{
        _s["for_end"]=int(eval_expr(_s["for_end"]));
        _m="";

        _s["content"]=content;
        content="";
        for(_s["i"]=_s["for_begin"];_s["i"]<_s["for_end"];_s["i"]++){
          _c=_s["content"];
          gsub(_s["for_var"],_s["i"],_c);
          content=content _c;
        }
      }
    #-------------------------------------------------
    }else{
      if(_c=="."){
        _m="c";
      }else if(_c ~ /[/#]/){
        break;
      }else if(_c !~ /[ \t\r\n]/){
        print "unrecognized expand cmd '" _c  "'" > "/dev/stderr"
      }
    }
  }

  return content;
}
#===============================================================================
#   mwg.pp commands
#-------------------------------------------------------------------------------
function range_begin(cmd,arg){
  d_level++;
  d_rstack[d_level,"c"]=cmd;
  d_rstack[d_level,"a"]=arg;
  d_content[d_level]="";
  d_content[d_level,"L"]="";
  d_content[d_level,"F"]="";
}
function range_end(args, _cmd,_arg,_txt,_clines,_cfiles){
  if(d_level==0){
    print "mwg_pp.awk:#%}: no matching range beginning" > "/dev/stderr"
    return;
  }

  # pop data
  _cmd=d_rstack[d_level,"c"];
  _arg=d_rstack[d_level,"a"];
  _txt=d_content[d_level];
  if(m_lineno){ # 20120726
    _clines=d_content[d_level,"L"];
    _cfiles=d_content[d_level,"F"];
  }
  d_level--;

  if(args!="")
    _txt=modify_text(_txt,args);

  # process
  if(_cmd=="define"){
    d_data[_arg]=_txt;
    if(m_lineno){ # 20120726
      d_data[_arg,"L"]=_clines;
      d_data[_arg,"F"]=_cfiles;
    }
  }else if(_cmd=="expand"||_cmd=="IF1"||_cmd=="IF4"){
    process_multiline(_txt,_clines,_cfiles); # 20120726
  }else if(_cmd=="none"||_cmd ~ /IF[023]/){
    # do nothing
  }else{
    print "mwg_pp.awk:#%}: unknown range beginning '" _cmd " ( " _arg " )'" > "/dev/stderr"
  }
}

function dctv_define(args,  _cap,_name,_name2){
  if(match(args,/^([-A-Za-z0-9_\:]+)[[:space:]]*(\([[:space:]]*)?$/,_cap)>0){
    # dctv: #%define hoge
    # dctv: #%define hoge (
    _name=_cap[1];
    if(_name=="end")
      range_end("");
    else
      range_begin("define",_name);
  }else if(match(args,/^([-_\:[:alnum:]]+)[[:space:]]+([-_\:[:alnum:]]+)(.*)$/,_cap)>0){
    # dctv: #%define a b.mods
    _name=_cap[1];
    _name2=_cap[2];
    _args=trim(_cap[3]);
    if(_args!="")
      d_data[_name]=modify_text(d_data[_name2],_args);
    else
      d_data[_name]=d_data[_name2];

    if(m_lineno){
      d_data[_name,"L"]=d_data[_name2,"L"];
      d_data[_name,"F"]=d_data[_name2,"F"];
    }
  }else{
    print "mwg_pp.awk:#%define: missing data name" > "/dev/stderr"
    return;
  }
}

# 状態は何種類あるか?
#     END      CONDT CONDF ELSE
# IF0 出力せず IF1   IF0   IF4  (not matched)
# IF1 出力する IF2   IF2   IF3  (matched)
# IF2 出力せず IF2   IF2   IF3  (finished)
# IF3 出力せず !IF3  !IF3  !IF3 (else unmatched) 旧 "el0"
# IF4 出力する !IF3  !IF3  !IF3 (else matched)   旧 "el1"

function dctv_if(cond,  _cap){
  gsub(/^[ \t]+|[ \t]*(\([ \t]*)?$/,"",cond);
  if(cond!=""){
    #print "dbg: if( "cond " ) -> " eval_expr(cond) > "/dev/stderr"
    if(cond=="end")
      range_end("");
    else if(eval_expr(cond)){
      range_begin("IF1");
    }else{
      range_begin("IF0");
    }
  }else{
    print "mwg_pp.awk:#%define: missing data name" > "/dev/stderr"
    return;
  }
}
function dctv_elif(cond, _cmd){
  if(d_level==0){
    print "mwg_pp.awk:#%elif: no matching if directive" > "/dev/stderr"
    return;
  }

  _cmd=d_rstack[d_level,"c"];
  if(_cmd ~ /IF[0-4]/){
    range_end("");
    if(_cmd=="IF0"){
      if(eval_expr(cond)){
        range_begin("IF1");
      }else{
        range_begin("IF0");
      }
    }else if(_cmd ~ /IF[12]/){
      range_begin("IF2");
    }else{
      range_begin("IF3");
      if(_cmd ~ /IF[34]/)
        print_error("mwgpp:#%else","if clause have already ended!");
    }
  }else{
    print_error("mwgpp:#%else","no matching if directive");
  }
}
function dctv_else(  _cap,_cmd){
  if(d_level==0){
    print_error("mwgpp:#%else","no matching if directive");
    return;
  }

  _cmd=d_rstack[d_level,"c"];
  if(_cmd ~ /IF[0-4]/){
    range_end("");
    if(_cmd=="IF0"){
      range_begin("IF4");
    }else{
      range_begin("IF3");
      if(_cmd ~ /IF[34]/)
        print_error("mwgpp:#%else","if clause have already ended!");
    }
  }else{
    print_error("mwgpp:#%else","no matching if directive");
  }
}

function dctv_expand(args,  _cap,_txt,_type){
  if(match(args,/^([-a-zA-Z\:0-9_]+|[\(])(.*)$/,_cap)>0){
    if(_cap[1]=="("){
      _type=1;
    }else{
      _txt=d_data[_cap[1]];
      _txt=modify_text(_txt,_cap[2]);
      process_multiline(_txt,d_data[_cap[1],"L"],d_data[_cap[1],"F"]);
    }
  }else if(match(args,/^[[:space:]]*$/)>0){
    _type=1;
  }else{
    print "mwg_pp.awk:#%expand: missing data name" > "/dev/stderr"
    return;
  }

  if(_type==1){
    # begin expand
    range_begin("expand",_cap[2]); # _cap[2] not used
  }
}

function dctv_modify(args,  _i,_len,_name,_content){
  _i=match(args,/[^-a-zA-Z\:0-9_]/);
  _len=_i?_i-1:length(args);
  _name=substr(args,1,_len);
  args=trim(substr(args,_len+1));

  d_data[_name]=modify_text(d_data[_name],args);
}

function include_file(file, _line,_lines,_i,_n,_dir,_originalFile,_originalLine){
  if(file ~ /^<.+>$/){
    gsub(/^<|>$/,"",file);
    file=INCLUDE_DIRECTORY "/" file;
  }else{
    gsub(/^"|"$/,"",file);
    if(file !~ /^\//){
      _dir=awk_getfiledir();
      if(_dir!="")file=_dir "/" file;
    }
  }

  _n=0;
  while((_r = getline _line < file) >0)
    _lines[_n++]=_line;
  if(_r<0)
    print_error("could not open the include file '" file "'");
  close(file);

  dependency_add(file);

  _originalFile=m_lineno_cfile;
  _originalLine=m_lineno_cline;
  for(_i=0;_i<_n;_i++){
    m_lineno_cfile=file; # 20120726
    m_lineno_cline=_i+1; # 20120726
    process_line(_lines[_i]);
  }
  m_lineno_cfile=_originalFile; # 2015-01-24
  m_lineno_cline=_originalLine; # 2015-01-24
}

function dctv_error(message, _title){
  if(m_lineno_cfile!=""||m_lineno)
    _title=m_lineno_cfile ":" m_lineno_cline;
  else
    _title=FILENAME;

  print_error(_title,message);
}

#===============================================================================
function data_define(pair, _sep,_i,_k,_v,_capt,_rex){
  if(pair ~ /^[^\(_a-zA-Z0-9]/){ # #%data/name/value/

    _sep="\\" substr(pair,1,1);
    _rex="^" _sep "([^" _sep "]+)" _sep "([^" _sep "]+)" _sep
    if(match(pair,_rex,_capt)){
      _k=_capt[1];
      _v=_capt[2];
      d_data[_k]=_v;
    }else{
      printf("(#%%data directive)! ill-formed. (pair=%s, _rex=%s)\n",pair,_rex) > "/dev/stderr"
      return 0;
    }
  }else{ # #%data name value
    # #%data(=) name=value
    _sep="";
    if(match(pair,/^\([^\)]+\)/)>0){
      _sep=substr(pair,2,RLENGTH-2);
      pair=trim(substr(pair,RLENGTH+1));
    }
        
    _i=_sep!=""?index(pair,_sep):match(pair,/[ \t]/);
    if(_i<=0){
      printf("(#%%data directive)! ill-formed. (pair=%s, _sep=%s)\n",pair,_sep) > "/dev/stderr"
      return 0;
    }
        
    _k=substr(pair,1,_i-1);
    _v=trim(substr(pair,_i+length(_sep)))
    d_data[_k]=_v;
        
    #_t[0];head_token(pair,_t);
    #d_data[_t[0]]=_t[1];
  }
}
function data_print(key){
  add_line(d_data[key]);
}
function execute(command, _line,_caps,_n,_cfile){
  if(match(command,/^(>>?)[[:space:]]*([^[:space:]]*)/,_caps)>0){
    # 出力先の変更
    fflush(m_outpath);
    m_outpath=_caps[2];
    m_addline_cfile="";
    if(_caps[1]==">"&&m_outpath!=""){
      printf("") > m_outpath
    }
  }else{
    _n=0;
    while((command | getline _line)>0)
      _lines[_n++]=_line;
    close(command);

    _cfile="$(" command ")";
    gsub(/[\\"]/,"\\\\&",_cfile);
    for(_i=0;_i<_n;_i++){
      m_lineno_cfile=_cfile;
      m_lineno_cline=_i+1;
      process_line(_lines[_i]);
    }
  }
}
#===============================================================================
function add_line(line){
  if(d_level==0){
    if(m_lineno){ # 20120726
      if(m_addline_cfile!=m_lineno_cfile||++m_addline_cline!=m_lineno_cline){
        m_addline_cline=m_lineno_cline;
        m_addline_cfile=m_lineno_cfile;
        if(m_addline_cline!=""&&m_addline_cfile!=""){
          if(m_outpath=="")
            print "#line " m_addline_cline " \"" m_addline_cfile "\""
          else
            print "#line " m_addline_cline " \"" m_addline_cfile "\"" >> m_outpath
        }
      }
    }

    if(m_outpath=="")
      print line
    else
      print line >> m_outpath
  }else{
    d_content[d_level]=d_content[d_level] line "\n"
    d_content[d_level,"L"]=d_content[d_level,"L"] m_lineno_cline "\n";
    d_content[d_level,"F"]=d_content[d_level,"F"] m_lineno_cfile "\n";
  }
}

# function process_multiline2(txt,cline,cfile, _s,_l,_f,_len,_i){
#   _len=split(txt,_s,"\n");
#   if(length(_s[_len])==0)_len--;

#   split(clines,_l,"\n");
#   split(cfiles,_f,"\n");
#   for(_i=0;_i<_len;_i++){
#     m_lineno_cline=_l[_i+1];
#     m_lineno_cfile=_f[_i+1];
#     process_line(_s[_i+1]);
#   }
# }

function process_multiline(txt,clines,cfiles,  _s,_l,_f,_len,_i){
  _len=split(txt,_s,"\n");
  if(length(_s[_len])==0)_len--;

  split(clines,_l,"\n");
  split(cfiles,_f,"\n");
  for(_i=0;_i<_len;_i++){
    m_lineno_cline=_l[_i+1];
    m_lineno_cfile=_f[_i+1];
    process_line(_s[_i+1]);
  }
}

function process_line(line,_line,_text,_ind,_len,_directive, _cap){
  _line=line;

  sub(/^[ \t]+/,"",_line);
  sub(/[ \t\r]+$/,"",_line);
  if(m_comment_cpp)
    sub(/^\/\//,"#",_line);
  if(m_comment_pragma)
    sub(/^[[:space:]]*\#[[:space:]]*pragma/,"#",_line);
  if(m_comment_c&&match(_line,/^\/\*(.+)\*\/$/,_cap)>0)
    _line="#" _cap[1];

  if(_line ~ /^#%[^%]/){
    # cut directive
    if(match(_line,/^#%[ \t]*([-a-zA-Z_0-9\:]+)(.*)$/,_cap)>0){
      _directive=_cap[1];
      _text=trim(_cap[2]);
    }else if(match(_line,/^#%[ \t]*([^-a-zA-Z_0-9\:])(.*)$/,_cap)>0){
      _directive=_cap[1];
      _text=trim(_cap[2]);
    }else{
      print_error("unrecognized directive line: " line);
      return;
    }

    # switch directive
    if(_directive=="("||_directive=="begin"){
      range_begin("none",_text);
    }else if(_directive==")"||_directive=="end"){
      range_end(_text);
    }else if(_directive=="define"||_directive=="m"){
      dctv_define(_text);
    }else if(_directive=="expand"||_directive=="x"){
      dctv_expand(_text);
    }else if(_directive=="if"){
      dctv_if(_text);
    }else if(_directive=="else"){
      dctv_else(_text);
    }else if(_directive=="elif"){
      dctv_elif(_text);
    }else if(_directive=="modify"){ # obsoleted. use #%define name name.mods
      print_error("obsoleted directive modify");
      dctv_modify(_text);
    }else if(_directive=="include"||_directive=="<"){
      include_file(_text);
    }else if(_directive=="data"){ # obs → データ設定に有意。残す?
      data_define(_text);
    }else if(_directive=="print"){ #obs
      data_print(_text);
    }else if(_directive=="eval"){
      eval_expr(_text);
    }else if(_directive=="["&&match(_text,/^(.+)\]$/,_cap)>0){
      eval_expr(_cap[1]);
    }else if(_directive=="exec"||_directive=="$"){
      execute(_text);
    }else if(_directive=="#"){
      # comment. just ignored.
    }else if(_directive=="error"){
      dctv_error(_text);
    }else{
      print_error("unrecognized directive " _directive);
    }
  }else if(_line ~ /^##+%/){
    add_line(substr(_line,2));
  }else if(_line ~ /^#%%+/){
    add_line("#" substr(_line,3));
  }else{
    add_line(line);
  }
}

BEGIN{
  FS="MWG_PP_COMMENT";
  ev1scan_init();
  d_level=0;
  d_data[0]="";

  m_outpath="";
  m_comment_c     =int(ENVIRON["PPC_C"])!=0;
  m_comment_cpp   =int(ENVIRON["PPC_CPP"])!=0;
  m_comment_pragma=int(ENVIRON["PPC_PRAGMA"])!=0;

  m_lineno        =int(ENVIRON["PPLINENO"])!=0;

  INCLUDE_DIRECTORY=ENVIRON["HOME"] "/.mwg/mwgpp/include"

  m_dependency_count=0
  m_dependency_guard[""]=1;
  m_dependency[0]="";
}

{
  if(NR==1){
    if(ENVIRON["PPLINENO_FILE"]!="")
      m_rfile=ENVIRON["PPLINENO_FILE"];
    else
      m_rfile=FILENAME;
  }
  m_lineno_cfile=m_rfile;
  m_lineno_cline=NR;
  process_line($1);
}

function dependency_add(file){
  if(!m_dependency_guard[file]){
    m_dependency_guard[file]=1;
    m_dependency[m_dependency_count++]=file;
  }
}
function dependency_generate(output,target, _i,_iMax){
  if(!target){
    target=m_rfile;
    sub(/\.pp$/,"",target);
    target=target ".out";
  }

  if(m_dependency_count==0){
    print target ": " m_rfile > output
  }else{
    print target ": " m_rfile " \\" > output
    _iMax=m_dependency_count-1;
    for(_i=0;_i<_iMax;_i++)
      print "  " m_dependency[_i] " \\" >> output;
    print "  " m_dependency[_iMax] >> output;
  }
}

END{
  # output dependencies
  DEPENDENCIES_OUTPUT=ENVIRON["DEPENDENCIES_OUTPUT"];
  if(DEPENDENCIES_OUTPUT)
    dependency_generate(DEPENDENCIES_OUTPUT,ENVIRON["DEPENDENCIES_TARGET"]);

  if(global_errorCount)exit(1);
}
