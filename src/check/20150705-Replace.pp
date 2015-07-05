#%[hello="operator()"]
#%[world=hello.Replace("(.)","[$1]")]
#%[text3=hello.Replace("(.)","\\\\$1")]
#%x
hello=${hello}
world=${world}
world=${text3}
#%end.i
