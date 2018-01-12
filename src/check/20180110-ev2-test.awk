#!/usr/bin/gawk -f

#------------------------------------------------------------------------------
# test1

function test1() {
  a = 0;
  if (a) {
    print "0 is true";
  } else {
    print "0 is false";
  }

  a = "0";
  if (a) {
    print "\"0\" is true";
  } else {
    print "\"0\" is false";
  }

  a = 0 == 1;
  if (a) {
    print "(0 == 1) is true";
  } else {
    print "(0 == 1) is false";
  }

  a = "";
  if (a) {
    print "\"\" is true";
  } else {
    print "\"\" is false";
  }
}

#------------------------------------------------------------------------------
# test2

function print_error(title,msg){
  global_errorCount++;
  print "\33[1;31m" title "!\33[m " msg > "/dev/stderr"
}

@include "../ev1scan.awk"
@include "../ev2.awk"

function my_typeof(x, v1, v2) {
  if (gawk_ver >= 40200)
    return typeof(x);

  if (x == 0) {
    if (x)
      return "string";
    else
      return "number";
  } else {
    OCONVFMT = CONVFMT;
    CONVFMT = "[%g]";
    v1 = "" x;
    CONVFMT = "(%g)";
    v2 = "" x;
    CONVFMT = OCONVFMT;
    if (v1 != v2)
      return "number";
    else
      return "string";
  }
}

function test2() {
  ev1scan_init();

  a = ev2_expr("0");
  if (a) {
    print "0 is true (" a ": " my_typeof(a) ")";
  } else {
    print "0 is false (" a ": " my_typeof(a) ")";
  }

  a = ev2_expr("\"0\"");
  if (a) {
    print "\"0\" is true (" a ": " my_typeof(a) ")";
  } else {
    print "\"0\" is false (" a ": " my_typeof(a) ")";
  }

  a = ev2_expr("0 == 1");
  if (a) {
    print "(0 == 1) is true (" a ": " my_typeof(a) ")";
  } else {
    print "(0 == 1) is false (" a ": " my_typeof(a) ")";
  }

  a = ev2_expr("\"\"");
  if (a) {
    print "\"\" is true (" a ": " my_typeof(a) ")";
  } else {
    print "\"\" is false (" a ": " my_typeof(a) ")";
  }
}

#------------------------------------------------------------------------------
# test3

function test3() {
  a = "0";
  if (a) {
    print "\"0\" is true";
  } else {
    print "\"0\" is false";
  }

  a = +a;
  if (a) {
    print "+\"0\" is true"; # gawk API: 2.0 (a is string)
  } else {
    print "+\"0\" is false"; # gawk API: 1.1 (a is number)
  }

  a = 0 + "0";
  if (a) {
    print "0+\"0\" is true (" a ")";
  } else {
    print "0+\"0\" is false (" a ")";
  }

  a = 0 + "1.2";
  if (a) {
    print "0+\"1.2\" is true (" a ")";
  } else {
    print "0+\"1.2\" is false (" a ")";
  }
}

BEGIN {
  gawk_ver = 0;
  if (match(PROCINFO["version"], /^([0-9]+)\.([0-9]+)(\.([0-9]+))?/, m) > 0)
    gawk_ver = m[1] * 10000 + m[2] * 100 + m[4];

  if (ARGV[1] == "test2") {
    test2();
  } else if (ARGV[1] == "test3") {
    test3();
  } else {
    test1();
  }

  exit
}
