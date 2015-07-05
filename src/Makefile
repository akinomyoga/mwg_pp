# -*- makefile-gmake -*-

all:
.PHONY: all install

SHELL:=/bin/bash

BINDIR:=$(HOME)/bin
OUTDIR:=../out
$(OUTDIR) $(BINDIR):
	mkdir -p "$@"

all: $(OUTDIR)/mwg_pp.awk

-include $(OUTDIR)/main.d
$(OUTDIR)/main.d: $(OUTDIR)/mwg_pp.awk
$(OUTDIR)/mwg_pp.awk: main.awk | $(OUTDIR)
	DEPENDENCIES_OUTPUT=$(OUTDIR)/main.d DEPENDENCIES_TARGET="$@" ext/mwg_pp-2.1.awk $< > $@ && { [[ -x "$@" ]] || chmod +x $@; }

install: $(BINDIR) $(BINDIR)/mwg_pp.awk
$(BINDIR)/mwg_pp.awk: $(OUTDIR)/mwg_pp.awk | $(BINDIR)
	cp -p $< $@
