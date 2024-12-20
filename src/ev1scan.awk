# -*- mode:awk -*-
#%begin
#
# public:
#   function ev1scan_init();
#   function ev1scan_scan(expression, words);
#   function ev1scan_cast_bool(arg);
#
# private:
#   function ev1scan_init_opregister(opname, optype, opprec);
#   function ev1scan_scan_escchar(c);
#
#%end

function ev1scan_init_opregister(opname, optype, opprec) {
  ev_db_operator[opname] = optype;
  ev_db_operator[opname, "a"] = opprec;
}

function ev1scan_init() {
  OP_BIN = 1;
  OP_UNA = 2; # prefix
  OP_SGN = 3; # prefix or binary
  OP_INC = 4; # prefix or suffix

  ev1scan_init_opregister("." , OP_BIN, 12.0);

  ev1scan_init_opregister("++", OP_INC, 11.0);
  ev1scan_init_opregister("--", OP_INC, 11.0);
  ev1scan_init_opregister("!" , OP_UNA, 11.0);

  ev1scan_init_opregister("*" , OP_BIN, 10.0);
  ev1scan_init_opregister("/" , OP_BIN, 10.0);
  ev1scan_init_opregister("%" , OP_BIN, 10.0);

  ev1scan_init_opregister("+" , OP_SGN, 9.0);
  ev1scan_init_opregister("-" , OP_SGN, 9.0);

  ev1scan_init_opregister("==", OP_BIN, 8.0);
  ev1scan_init_opregister("!=", OP_BIN, 8.0);
  ev1scan_init_opregister("<" , OP_BIN, 8.0);
  ev1scan_init_opregister("<=", OP_BIN, 8.0);
  ev1scan_init_opregister(">" , OP_BIN, 8.0);
  ev1scan_init_opregister(">=", OP_BIN, 8.0);

  ev1scan_init_opregister("&" , OP_BIN, 7.4);
  ev1scan_init_opregister("^" , OP_BIN, 7.2);
  ev1scan_init_opregister("|" , OP_BIN, 7.0);
  ev1scan_init_opregister("&&", OP_BIN, 6.4);
  ev1scan_init_opregister("||", OP_BIN, 6.0);

  ev1scan_init_opregister("=" , OP_BIN, 2.0);
  ev1scan_init_opregister("+=", OP_BIN, 2.0);
  ev1scan_init_opregister("-=", OP_BIN, 2.0);
  ev1scan_init_opregister("*=", OP_BIN, 2.0);
  ev1scan_init_opregister("/=", OP_BIN, 2.0);
  ev1scan_init_opregister("%=", OP_BIN, 2.0);
  ev1scan_init_opregister("|=", OP_BIN, 2.0);
  ev1scan_init_opregister("^=", OP_BIN, 2.0);
  ev1scan_init_opregister("&=", OP_BIN, 2.0);
  ev1scan_init_opregister("," , OP_BIN, 1.0);

  # for ev2
  SE_VALU = 1;
  SE_PREF = 0;
  SE_MARK = -1;

  ATTR_SET = "t";
  ATTR_TYP = "T";
  ATTR_MOD = "M";

  MOD_NUL = 0;
  MOD_REF = 1;
  ATTR_REF = "R";
  MOD_ARG = 2;
  MOD_ARR = 4;
  MOD_MTH = 8;
  ATTR_MTH_OBJ = "Mo";
  ATTR_MTH_MEM = "Mf";

  TYPE_NUM = 0;
  TYPE_STR = 1;
}

function ev1scan_scan(expression, words, _wlen, _i, _len, _c, _t, _w) {
  _wlen = 0;
  _len = length(expression);
  for (_i = 0; _i < _len; _i++) {
    _c = substr(expression, _i + 1, 1);

    if (_c ~ /[.0-9]/) {
      _t = "n";
      _w = _c;
      while (_i + 1 < _len) {
        _c = substr(expression, _i + 2, 1);
        if (_c !~ /[.0-9]/) break;
        _w = _w _c;
        _i++;
      }
      #if (_w == ".")_w = 0;
      if (_w == ".") {
        _t = "o";
      }
    } else if (ev_db_operator[_c] != "") {
      _t = "o";
      _w = _c;
      while (_i + 1 < _len) {
        _c = substr(expression, _i + 2, 1);
        #print "dbg: ev_db_op[" _w _c "] = " ev_db_operator[_w _c] > "/dev/stderr"
        if (ev_db_operator[_w _c] != "") {
          _w = _w _c;
          _i++;
        } else break;
      }
    } else if (_c ~ "[[({?]") {
      _t = "op";
      _w = _c;
    } else if (_c ~ "[])}:]") {
      _t = "cl";
      _w = _c;
    } else if (_c ~ /[_a-zA-Z]/) {
      _t = "w";
      _w = _c;
      while (_i + 1 < _len) {
        _c = substr(expression, _i + 2, 1);
        if (_c !~ /[_a-zA-Z0-9]/) break;
        _w = _w _c;
        _i++;
      }
    } else if (_c == "\"") {
      # string literal
      _t = "S";
      _w = "";
      while (_i + 1 < _len) {
        _c = substr(expression, _i + 2, 1);
        _i++;
        if (_c  == "\"") {
          break;
        } else if (_c == "\\") {
          #print_error("dbg: (escchar = " _c " " substr(expression, _i + 2, 1) ")" );
          if (_i + 1 < _len) {
            _w = _w ev1scan_scan_escchar(substr(expression, _i + 2, 1));
            _i++;
          } else {
            _w = _w _c;
          }
        } else {
          _w = _w _c;
        }
      }
    } else if (_c ~ /[[:blank:]]/) {
      continue; # ignore blank
    } else {
      print_error("mwg_pp.eval_expr", "unrecognizable character '" _c "'");
      continue; # ignore unknown character
    }

    words[_wlen, "t"] = _t;
    words[_wlen, "w"] = _w;
    _wlen++;
  }

  # debug
  #for (_i = 0; _i < _wlen; _i++) {
  #    print "yield " words[_i, "w"] " as " words[_i, "t"] > "/dev/stderr"
  #}

  return _wlen;
}

function ev1scan_scan_escchar(c) {
  if (c !~ /[nrtvfaeb]/) return c;
  if (c == "n") return "\n";
  if (c == "r") return "\r";
  if (c == "t") return "\t";
  if (c == "v") return "\v";
  if (c == "f") return "\f";
  if (c == "a") return "\a";
  if (c == "e") return "\33";
  if (c == "b") return "\b";
  return c;
}

function ev1scan_cast_bool(arg) {
  return arg != 0 && arg != "";
}
