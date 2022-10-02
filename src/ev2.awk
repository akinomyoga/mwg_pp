# -*- mode: awk -*-
#%begin
#
# public:
#   function eval_expr(expression);
#
# private:
#   function ev2_expr(expression);
#   function ev2_pop_value(s,sp,assoc,rDict,rName);
#   function ev2_memget(dDict,dName,oDict,oName,memname);
#   function ev2_memcall(dDict,dName,oDict,oName,memname,aDict,aName);
#   function ev2_funcall(dDict,dName,funcname,aDict,aName);
#   function ev2_apply(stk,iPre,iVal);
#   function ev2_copy(dDict,dName,sDict,sName);
#   function ev2_delete(sDict,sName);
#
#%end

function eval_expr(expression) {
  return ev2_expr(expression);
}

function ev2_expr(expression, _wlen, _words, _i, _len, _t, _w, _v, _sp, _s, _sp1, _optype) {
  _wlen = ev1scan_scan(expression, _words);

  # <param name="_s">
  #  parsing stack
  #  _s[index, "t"]  : SE_PREF  SE_MARK  SE_VALU
  #  _s[index]       : lhs               value
  #  _s[index, "T"]  : dataType          dataType
  #  _s[index, "c"]  : b+ u!    op
  #  _s[index, "l"]  : assoc
  #
  #  _s[index, "M"] = MOD_ARG;
  #  _s[index, "A"] = length;
  #  _s[index, "A", i] = element;
  # </param>

  # parse
  _sp = -1;
  for (_i = 0; _i < _wlen; _i++) {
    # _t: token type
    # _w: token word
    # _l: token prefix level
    _t = _words[_i, "t"];
    _w = _words[_i, "w"];

    #-- process token --
    if (_t == "n") {
      _sp++;
      _s[_sp] = 0 + _w;
      _s[_sp, "t"] = SE_VALU;
      _s[_sp, "T"] = TYPE_NUM;
      _s[_sp, "M"] = MOD_NUL;
    #---------------------------------------------------------------------------
    } else if (_t == "o") {
      _optype = ev_db_operator[_w];
      if (_optype == OP_SGN) { # signature operator +-
        if (_sp >= 0 && _s[_sp, "t"] == SE_VALU) {
          _t = "b"; # binary operator
        } else {
          _t = "u"; # unary operator
        }
      } else if (_optype == OP_BIN) { # binary operator
        _t = "b";
      } else if (_optype == OP_UNA) { # unary prefix operator
        _t = "u";
      } else if (_optype == OP_INC) { # operator++ --
        if (_sp >= 0 && _s[_sp, "t"] == SE_VALU) {
          if (and(_s[_sp, "M"], MOD_REF)) {
            if (_w == "++")
              d_data[_s[_sp, "R"]]++;
            else if (_w == "--")
              d_data[_s[_sp, "R"]]--;
            else
              print_error("mwg_pp.eval", "unknown increment operator " _w);

            _s[_sp, "M"] = MOD_NUL;
            delete _s[_sp, "R"];
          }

          _t = "";
        } else {
          _t = "u"; # unary operator
        }
      } else {
        print_error("mwg_pp.eval", "unknown operator " _w);
      }

      if (_t == "b") {
        #-- binary operator
        _l = ev_db_operator[_w, "a"];
        #print "dbg: binary operator level = " _l > "/dev/stderr"

        # get lhs
        _sp = ev2_pop_value(_s, _sp, _l); # left assoc
        #_sp = ev2_pop_value(_s, _sp, _l + 0.1); # right assoc # TODO =

        # overwrite to lhs
        _s[_sp, "t"] = SE_PREF;
        _s[_sp, "p"] = "b";
        _s[_sp, "P"] = _w;
        _s[_sp, "l"] = _l; # assoc level
      } else if (_t == "u") {
        # unary operator
        _l = ev_db_operator[_w, "a"];

        _sp++;
        _s[_sp, "t"] = SE_PREF
        _s[_sp, "p"] = "u";
        _s[_sp, "P"] = _w;
        _s[_sp, "l"] = _l; # assoc level
      }
    #---------------------------------------------------------------------------
    } else if (_t == "op") {
      _sp++;
      _s[_sp, "t"] = SE_MARK;
      _s[_sp, "m"] = _w;
    } else if (_t == "cl") {
      if (_sp >= 0 && _s[_sp, "t"] == SE_VALU) {
        _sp1 = ev2_pop_value(_s, _sp, 0);
        _sp = _sp1-1;
      } else {
        # empty arg
        _sp1 = _sp+1;
        _s[_sp1] = "";
        _s[_sp1, "t"] = SE_VALU;
        _s[_sp1, "T"] = TYPE_STR;
        _s[_sp1, "M"] = MOD_ARG;
        _s[_sp1, "A"] = 0;
      }
      # state: [.. _sp=open _sp1]

      # parentheses
      if (!(_sp >= 0 && _s[_sp, "t"] == SE_MARK)) {
        print_error("mwg_pp.eval: no matching open paren to " _w " in " expression);
        continue;
      }
      _w = _s[_sp, "m"] _w;
      _sp--;


      # state: [_sp open _sp1]
      if (_sp >= 0 && _s[_sp, "t"] == SE_VALU) {
        if (_w == "?:") {
          _sp = ev2_pop_value(_s, _sp, 3.0); # assoc_value_3
          _v = (_s[_sp] != 0 && _s[_sp] != "") ? "T" : "F";
          #print_error("dbg: _s[_sp]=" _s[_sp] " _v=" _v);

          # last element
          _s[_sp] = _s[_sp1];
          _s[_sp, "t"] = SE_VALU;
          _s[_sp, "T"] = _s[_sp1, "T"];
          _s[_sp, "M"] = MOD_NUL; #TODO reference copy

          # overwrite pref
          _s[_sp, "t"] = SE_PREF;
          _s[_sp, "p"] = _w;
          _s[_sp, "P"] = _v;
          _s[_sp, "l"] = 3.0; # level
        } else {
          _sp = ev2_pop_value(_s, _sp, 12); # assoc_value_12

          if (_w == "[]" && and(_s[_sp, "M"], MOD_REF)) {
            # indexing
            _s[_sp] = d_data[_s[_sp, "R"], _s[_sp1]];
            _s[_sp, "t"] = SE_VALU;
            _s[_sp, "T"] = (_s[_sp] == 0 + _s[_sp]? TYPE_NUM: TYPE_STR);
            _s[_sp, "M"] = MOD_REF;
            _s[_sp, "R"] = _s[_sp, "R"] SUBSEP _s[_sp1];
          } else if (and(_s[_sp, "M"], MOD_REF)) {
            # function call
            ev2_funcall(_s, _sp, _s[_sp, "R"], _s, _sp1);
          } else if (and(_s[_sp, "M"], MOD_MTH)) {
            # member function call
            ev2_memcall(_s, _sp, _s, _sp SUBSEP ATTR_MTH_OBJ, _s[_sp, ATTR_MTH_MEM], _s, _sp1);
          } else {
            print "mwg_pp.eval: invalid function call " _s[_sp] " " _w " in " expression > "/dev/stderr"
          }
        }
      } else {
        _sp++;
        if (_w == "[]") {
          # array
          ev2_copy(_s, _sp, _s, _sp1);
          _s[_sp, "M"] = MOD_ARR;
        } else {
          # last element
          _s[_sp] = _s[_sp1];
          _s[_sp, "t"] = SE_VALU;
          _s[_sp, "T"] = _s[_sp1, "T"];
          _s[_sp, "M"] = MOD_NUL;
        }
      }
    #---------------------------------------------------------------------------
    } else if (_t == "w") {
      _sp++;
      _s[_sp] = d_data[_w];
      _s[_sp, "t"] = SE_VALU;
      _s[_sp, "T"] = (_s[_sp] == 0 + _s[_sp]? TYPE_NUM: TYPE_STR);
      _s[_sp, "M"] = MOD_REF;
      _s[_sp, "R"] = _w;
    } else if (_t == "S") {
      # string
      _sp++;
      _s[_sp] = _w;
      _s[_sp, "t"] = SE_VALU;
      _s[_sp, "T"] = TYPE_STR;
      _s[_sp, "M"] = MOD_NUL;
    } else {
      print_error("mwg_pp.eval:fatal", "unknown token type " _t);
    }
  }

  _sp = ev2_pop_value(_s, _sp, 0);
  return _sp >= 1? "err": _s[_sp];
}

function ev2_pop_value(s, sp, assoc, rDict, rName, _vp, _value) {
  # <param> rDict [default = s]
  # <param> rName [default = <final stack top>]
  # <returns> sp = <final stack top>

  # read value
  if (sp >= 0 && s[sp, "t"] == SE_VALU) {
    sp--;
  } else {
    _vp = sp + 1;
    s[_vp] = 0;
    s[_vp, "t"] = SE_VALU;
    s[_vp, "T"] = TYPE_NUM;
    s[_vp, "M"] = MOD_NUL;
  }

  # proc prefices
  while(sp >= 0 && s[sp, "t"] == SE_PREF && s[sp, "l"] >= assoc) {
    ev2_apply(s, sp, sp + 1);
    sp--;
  }

  if (rDict == "")
    sp++;
  else
    ev2_copy(rDict, rName, s, sp + 1);

  return sp;
}

function ev2_memget(dDict, dName, oDict, oName, memname) {
  #print_error("mwg_pp.eval", "dbg: ev2_memget(memname=" memname ")");

  # embedded special member
  if (oDict[oName, "T"] == TYPE_STR) {
    if (memname == "length") {
      dDict[dName] = length(oDict[oName]);
      dDict[dName, "t"] = SE_VALU;
      dDict[dName, "T"] = TYPE_NUM;
      dDict[dName, "M"] = MOD_NUL;
      return;
    } else if (memname == "replace" || memname == "Replace" || memname == "slice" || memname ~ /^to(upper|lower)$/) {
      ev2_copy(dDict, dName SUBSEP ATTR_MTH_OBJ, oDict, oName);
      dDict[dName, ATTR_MTH_MEM] = memname;
      dDict[dName] = "";
      dDict[dName, "t"] = SE_VALU;
      dDict[dName, "T"] = TYPE_STR;
      dDict[dName, "M"] = MOD_MTH;
      #print_error("mwg_pp.eval", "dbg: method = String#" memname);
      return;
    }
  } else {
    # members for other types (TYPE_NUM MOD_ARR etc..)
  }

  # normal data member
  if (and(oDict[oName, ATTR_MOD], MOD_REF)) {
    dDict[dName] = d_data[oDict[oName, ATTR_REF], memname];
    dDict[dName, "t"] = SE_VALU;
    dDict[dName, "T"] = (dDict[dName] == 0 + dDict[dName]? TYPE_NUM: TYPE_STR);
    dDict[dName, "M"] = MOD_REF;
    dDict[dName, ATTR_REF] = oDict[oName, ATTR_REF] SUBSEP memname;
  } else {
    print_error("mwg.eval", "invalid member name '" memname "'");
    dDict[dName] = "";
    dDict[dName, "t"] = SE_VALU;
    dDict[dName, "T"] = TYPE_STR;
    dDict[dName, "M"] = MOD_NUL;
  }

  # rep: dDict dName oDict oName
}

function ev2_memcall(dDict, dName, oDict, oName, memname, aDict, aName, _a, _i, _c, _result, _resultT) {
  #print_error("mwg_pp.eval", "dbg: ev2_memcall(memname=" memname ")");

  _resultT = "";

  # read arguments
  if (aDict[aName, "M"] != MOD_ARG) {
    _c = 1;
    _a[0] = aDict[aName];
  } else {
    _c = aDict[aName, "A"];
    for (_i = 0; _i < _c; _i++) _a[_i] = aDict[aName, "A", _i];
  }

  #-----------------
  # process
  if (oDict[oName, "T"] == TYPE_STR) {
    if (memname == "replace") {
      _result = oDict[oName];
      gsub(_a[0], _a[1], _result);
      _resultT = TYPE_STR;
    } else if (memname == "Replace") {
      _result = replace(oDict[oName], _a[0], _a[1]);
      _resultT = TYPE_STR;
    } else if (memname == "slice") {
      _result = slice(oDict[oName], _a[0], _a[1]);
      _resultT = TYPE_STR;
    } else if (memname == "toupper") {
      _result = toupper(oDict[oName]);
      _resultT = TYPE_STR;
    } else if (memname == "tolower") {
      _result = tolower(oDict[oName]);
      _resultT = TYPE_STR;
    }
  }

  #-----------------
  # write value
  if (_resultT == "") {
    print_error("mwg.eval", "invalid member function name '" memname "'");
    _result = "";
    _resultT = TYPE_STR;
  }

  dDict[dName] = _result;
  dDict[dName, "t"] = SE_VALU;
  dDict[dName, "T"] = _resultT;
  dDict[dName, "M"] = MOD_NUL;
}

function ev2_funcall(dDict, dName, funcname, aDict, aName, _a, _i, _c, _result, _resultT, _cmd, _line) {
  _resultT = TYPE_NUM;

  if (aDict[aName, "M"] != MOD_ARG) {
    _c = 1;
    _a[0] = aDict[aName];
  } else {
    _c = aDict[aName, "A"];
    for (_i = 0; _i < _c; _i++) _a[_i] = aDict[aName, "A", _i];
  }

  if (funcname == "int") {
    _result = int(_a[0]);
  } else if (funcname == "float") {
    _result = 0 + _a[0];
  } else if (funcname == "floor") {
    if (_a[0] >= 0) {
      _result = int(_a[0]);
    } else {
      _result = int(1 - _a[0]);
      _result = int(_a[0] + _result)-_result;
    }
  } else if (funcname == "ceil") {
    if (_a[0] <= 0) {
      _result = int(_a[0]);
    } else {
      _result = int(1 + _a[0]);
      _result = int(_a[0]-_result) + _result;
    }
  } else if (funcname == "sqrt") {
    _result = sqrt(_a[0]);
  } else if (funcname == "sin") {
    _result = sin(_a[0]);
  } else if (funcname == "cos") {
    _result = cos(_a[0]);
  } else if (funcname == "tan") {
    _result = sin(_a[0]) / cos(_a[0]);
  } else if (funcname == "atan") {
    _result = atan2(_a[0], 1);
  } else if (funcname == "atan2") {
    _result = atan2(_a[0], _a[1]);
  } else if (funcname == "exp") {
    _result = exp(_a[0]);
  } else if (funcname == "log") {
    _result = log(_a[0]);
  } else if (funcname == "sinh") {
    _x = exp(_a[0]);
    _result = 0.5*(_x-1/_x);
  } else if (funcname == "cosh") {
    _x = exp(_a[0]);
    _result = 0.5 * (_x + 1 / _x);
  } else if (funcname == "tanh") {
    _x = exp(2 * _a[0]);
    _result = (_x - 1) / (_x + 1);
  } else if (funcname == "rand") {
    _result = rand();
  } else if (funcname == "srand") {
    _result = srand(_a[0]);
  } else if (funcname == "trim") {
    _resultT = TYPE_STR;
    _result = _a[0];
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", _result);
  } else if (funcname == "sprintf") {
    _resultT = TYPE_STR;
    _result = sprintf(_a[0], _a[1], _a[2], _a[3], _a[4], _a[5], _a[6], _a[7], _a[8], _a[9]);
  } else if (funcname == "slice") {
    _resultT = TYPE_STR;
    _result = slice(_a[0], _a[1], _a[2]);
  } else if (funcname == "length") {
    _result = length(_a[0]);
  } else if (funcname == "getenv") {
    _resultT = TYPE_STR;
    _result = ENVIRON[_a[0]];
  } else if (funcname == "system") {
    _resultT = TYPE_STR;
    _result = "";
    _cmd = _a[0];
    while ((_cmd | getline _line) > 0)
       _result = _result _line "\n";
    close(_cmd);
    sub(/\n+$/, "", _result);
  } else {
    print_error("mwg_pp.eval", "unknown function " funcname);
    _result = 0;
  }

  dDict[dName] = _result;
  dDict[dName, "t"] = SE_VALU;
  dDict[dName, "T"] = _resultT;
  dDict[dName, "M"] = MOD_NUL;
}

function ev2_unsigned(value) {
  return value >= 0 ? value : value + 0x100000000;
}

function ev2_apply(stk, iPre, iVal, _pT, _pW, _lhs, _rhs, _lhsT, _rhsT, _result, _i, _a, _b, _c) {
  # <param name="stk">stack</param>
  # <param name="iPre">prefix operator/resulting value</param>
  # <param name="iVal">input value</param>

  _pT = stk[iPre, "p"];
  _pW = stk[iPre, "P"];

  if (_pT == "b") {
    _lhs = stk[iPre];
    _rhs = stk[iVal];
    _lhsT = stk[iPre, "T"];
    _rhsT = stk[iVal, "T"];
    _resultT = TYPE_NUM;

    #print "binary " _lhs " " _pW " " _rhs > "/dev/stderr"
    if (_pW == "+") {
      if (_lhsT == TYPE_STR || _rhsT == TYPE_STR) {
        _result = _lhs _rhs;
        _resultT = TYPE_STR;
      } else
        _result = _lhs+_rhs;
    } else if (_pW == "-") _result = _lhs - _rhs;
    else if (_pW == "*") _result = _lhs * _rhs;
    else if (_pW == "/") _result = _lhs / _rhs;
    else if (_pW == "%") _result = _lhs % _rhs;
    else if (_pW == "==") _result = _lhs == _rhs;
    else if (_pW == "!=") _result = _lhs != _rhs;
    else if (_pW == ">=") _result = _lhs >= _rhs;
    else if (_pW == "<=") _result = _lhs <= _rhs;
    else if (_pW == "<") _result = _lhs < _rhs;
    else if (_pW == ">") _result = _lhs > _rhs;
    else if (_pW == "|") _result = or(ev2_unsigned(_lhs), ev2_unsigned(_rhs));
    else if (_pW == "^") _result = xor(ev2_unsigned(_lhs), ev2_unsigned(_rhs));
    else if (_pW == "&") _result = and(ev2_unsigned(_lhs), ev2_unsigned(_rhs));
    else if (_pW == "||") _result = ev1scan_cast_bool(_lhs) || ev1scan_cast_bool(_rhs); # not lazy evaluation
    else if (_pW == "&&") _result = ev1scan_cast_bool(_lhs) && ev1scan_cast_bool(_rhs); # not lazy evaluation
    else if (_pW ~ /[-+*/%|^&]?=/) {
      if (and(stk[iPre, "M"], MOD_REF)) {
        _resultT = TYPE_NUM;
        if (_pW == "=") {
          _result = _rhs;
          _resultT = _rhsT;
        } else if (_pW == "+=") _result = _lhs + _rhs;
        else if (_pW == "-=") _result = _lhs - _rhs;
        else if (_pW == "*=") _result = _lhs * _rhs;
        else if (_pW == "/=") _result = _lhs / _rhs;
        else if (_pW == "%=") _result = _lhs % _rhs;
        else if (_pW == "|=") _result = or(ev2_unsigned(_lhs), ev2_unsigned(_rhs));
        else if (_pW == "^=") _result = xor(ev2_unsigned(_lhs), ev2_unsigned(_rhs));
        else if (_pW == "&=") _result = and(ev2_unsigned(_lhs), ev2_unsigned(_rhs));

        stk[iPre] = _result;
        stk[iPre, "t"] = SE_VALU;
        stk[iPre, "T"] = _resultT;
        d_data[stk[iPre, "R"]] = _result;

        # TODO: array copy?
      } else {
        ev2_copy(stk, iPre, stk, iVal);
        # err?
      }
      return;
    } else if (_pW == ",") {
      if (stk[iPre, "M"] == MOD_ARG) {
        stk[iPre] = _rhs;
        stk[iPre, "t"] = SE_VALU;
        stk[iPre, "T"] = _rhsT;
        _i = stk[iPre, "A"]++;
        ev2_copy(stk, iPre SUBSEP "A" SUBSEP _i, stk, iVal);
      } else {
        stk[iPre, "t"] = SE_VALU;
        ev2_copy(stk, iPre SUBSEP "A" SUBSEP 0, stk, iPre);
        ev2_copy(stk, iPre SUBSEP "A" SUBSEP 1, stk, iVal);
        stk[iPre] = _rhs;
        stk[iPre, "T"] = _rhsT;
        stk[iPre, "M"] = MOD_ARG;
        stk[iPre, "A"] = 2;
      }
      return;
    } else if (_pW == ".") {
      _a = and(stk[iVal, "M"], MOD_REF)? stk[iVal, ATTR_REF]: _rhs;
      stk[iPre, "t"] = SE_VALU;
      ev2_memget(stk, iPre, stk, iPre, _a);
      return;
    }

    stk[iPre] = _result;
    stk[iPre, "t"] = SE_VALU;
    stk[iPre, "T"] = _resultT;
    stk[iPre, "M"] = MOD_NUL;
  } else if (_pT == "u") {
    _rhs = stk[iVal];

    if (_pW == "+") _result = _rhs;
    else if (_pW == "-") _result = -_rhs;
    else if (_pW == "!") _result = !ev1scan_cast_bool(_rhs);
    else if (_pW == "++") {
      _result = _rhs+1;
      stk[iPre] = _result;
      stk[iPre, "t"] = SE_VALU;
      stk[iPre, "T"] = TYPE_NUM;
      if (and(stk[iVal, "M"], MOD_REF)) {
        stk[iPre, "M"] = MOD_REF;
        stk[iPre, "R"] = stk[iVal, "R"];
        d_data[stk[iPre, "R"]] = _result;
      } else {
        stk[iPre, "M"] = MOD_NUL;
      }
      return;
    } else if (_pW == "--") {
      _result = _rhs-1;
      stk[iPre] = _result;
      stk[iPre, "t"] = SE_VALU;
      stk[iPre, "T"] = TYPE_NUM;
      if (and(stk[iVal, "M"], MOD_REF)) {
        stk[iPre, "M"] = MOD_REF;
        stk[iPre, "R"] = stk[iVal, "R"];
        d_data[stk[iPre, "R"]] = _result;
      } else {
        stk[iPre, "M"] = MOD_NUL;
      }
      return;
    }

    stk[iPre] = _result;
    stk[iPre, "t"] = SE_VALU;
    stk[iPre, "T"] = TYPE_NUM;
    stk[iPre, "M"] = MOD_NUL;
  } else if (_pT == "?:") {
    if (_pW == "T") {
      stk[iPre, "t"] = SE_VALU;
    } else {
      ev2_copy(stk, iPre, stk, iVal);
    }
  } else {
    ev2_copy(stk, iPre, stk, iVal);
  }
}

function ev2_copy(dDict, dName, sDict, sName, _M, _t, _i, _iN) {
  # assertion
  if (sDict[sName, "t"] != SE_VALU) {
    print_error("mwg_pp.eval:fatal", "copying not value element");
  }

  dDict[dName] = sDict[sName];                # value
  _t = dDict[dName, "t"] = sDict[sName, "t"]; # sttype
  _M = dDict[dName, "M"] = sDict[sName, "M"]; # mod

  if (_t == SE_VALU)
    dDict[dName, "T"] = sDict[sName, "T"];  # datatype

  # special data
  if (and(_M, MOD_REF)) {
    # reference
    dDict[dName, "R"] = sDict[sName, "R"]; # name in d_data
  }
  if (and(_M, MOD_ARG) || and(_M, MOD_ARR)) {
    # argument/array
    _iN = dDict[dName, "A"] = sDict[sName, "A"]; # array length
    for (_i = 0; _i < _iN; _i++)
      ev2_copy(dDict, dName SUBSEP "A" SUBSEP _i, sDict, sName SUBSEP "A" SUBSEP _i);
  }
  if (and(_M, MOD_MTH)) {
    # member function
    dDict[dName, ATTR_MTH_MEM] = sDict[sName, ATTR_MTH_MEM];
    ev2_copy(dDict, dName SUBSEP ATTR_MTH_OBJ, sDict, sName SUBSEP ATTR_MTH_OBJ);
  }
}

function ev2_delete(sDict, sName) {
  if (sDict[sName, "t"] != SE_VALU) {
    print_error("mwg_pp.eval:fatal", "deleting not value element");
  }

  delete sDict[sName];     # value
  delete sDict[sName, "t"]; # sttype
  delete sDict[sName, "T"]; # datatype
  _M = sDict[sName, "M"];     # mod
  delete sDict[sName, "M"];

  # special data
  if (_M == MOD_REF) {
    # reference
    delete sDict[sName, "R"]; # name in d_data
  } else if (_M == MOD_ARG || _M == MOD_ARR) {
    # argument/array
    _iN = sDict[sName, "A"];
    delete sDict[sName, "A"]; # array length
    for (_i = 0; _i < _iN; _i++)
      ev2_delete(sDict, sName SUBSEP "A" SUBSEP _i);
  }
}

# TODO? Dict[sp]       -> Dict[sp, "v"]
# TODO? s[i, "c"]="b+" -> s[i, "k"]="b" s["o"]="+"
