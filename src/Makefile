# -*- makefile-gmake -*-

all:
.PHONY: all install

BINDIR:=$(HOME)/bin

$(BINDIR):
	make -p "$@"

install: $(BINDIR) $(BINDIR)/mwg_pp.awk

$(BINDIR)/mwg_pp.awk: mwg_pp.awk
	cp -p $< $@
