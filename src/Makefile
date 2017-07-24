# -*- makefile-gmake -*-

all:
.PHONY: all install

PP0:=ext/mwg_pp-2.1.awk

SHELL:=/bin/bash

BINDIR:=$(HOME)/bin
OUTDIR:=../out
$(OUTDIR) $(BINDIR):
	mkdir -p "$@"

all: $(OUTDIR)/mwg_pp.awk

-include $(OUTDIR)/main.d
$(OUTDIR)/main.d: $(OUTDIR)/mwg_pp.awk
$(OUTDIR)/mwg_pp.awk: main.awk | $(OUTDIR)
	DEPENDENCIES_OUTPUT=$(OUTDIR)/main.d DEPENDENCIES_TARGET="$@" $(PP0) $< > $@ && { [[ -x "$@" ]] || chmod +x $@; }

install: $(BINDIR) $(BINDIR)/mwg_pp.awk
$(BINDIR)/mwg_pp.awk: $(OUTDIR)/mwg_pp.awk | $(BINDIR)
	cp -p $< $@

#------------------------------------------------------------------------------
# ev3v2.awk

.DELETE_ON_ERROR:
-include $(OUTDIR)/ev3v2.d
$(OUTDIR)/ev3v2.d: $(OUTDIR)/ev3v2.awk
$(OUTDIR)/ev3v2.awk: ev3v2/ev3v2.awk | $(OUTDIR)
	DEPENDENCIES_OUTPUT=$(OUTDIR)/ev3v2.d DEPENDENCIES_TARGET="$@" $(PP0) $< > $@ && { [[ -x "$@" ]] || chmod +x $@; }
all: $(OUTDIR)/ev3v2.awk
