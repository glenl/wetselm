#++
# PROJECT:
#   wetselm
#
# ABSTRACT:
#   A WETS simulator written in elm
#
# REQUIRED TOOLS:
#   atangle
#   pikchr
#   asciidoctor and various gems
#     asciidoctor-diagram
#     asciidoctor-rouge
#
#--
AUTHOR = "Glen Larsen"
VERSION = "1.0b"
REVISIONDATE = "21 Jan 2026"
PROJECT = wetselm

SITEDIR = ../site
DOCDIR = ../doc
CODEDIR = ../src
IMAGEDIR = ../images

vpath %.pdf $(DOCDIR)
vpath %.html $(DOCDIR)
vpath %.test $(TESTDIR)
vpath %.uxf $(IMAGEDIR)

DOCSRC = \
	$(PROJECT).adoc \
	$(NULL)

CODESRCS = \
	Main.adoc \
	Wets.adoc \
	Util.adoc \
	UI.adoc \
	$(NULL)

DOCSRCS = \
	$(PROJECT).adoc \
	overview.adoc \
	$(CODESRCS) \
	$(NULL)

REQUIRED_DIRS =\
	$(DOCDIR)\
	$(CODEDIR)\
	$(NULL)

_MKDIRS := $(shell for d in $(REQUIRED_DIRS) ;\
		 do\
			 [ -d $$d ] || mkdir -p $$d ;\
		 done)

PDF =\
	$(DOCDIR)/$(patsubst %.adoc,%.pdf,$(DOCSRC))\
	$(NULL)

ELMSRCS =\
	$(patsubst %.adoc,$(CODEDIR)/%.elm,$(CODESRCS))\
	$(NULL)


IMAGES =\
	$(IMAGEDIR)/wetselm-ui.png \
	$(IMAGEDIR)/chamber-layout.svg \
	$(NULL)

ATANGLEOPTS =\
	$(NULL)

CLEANFILES =\
	$(PDF) \
	$(ELMSRCS) \
	$(NULL)

ADOCTOR_OPTS =\
	-d book\
	-a source-highlighter=rouge \
	-a author=$(AUTHOR)\
	-a revnumber=$(VERSION)\
	-a revdate=$(REVISIONDATE)\
	-a umlet=$(HOME)/.local/bin/Umlet-15.0.0/umlet.jar\
	-a stem=latexmath \
	-r asciidoctor-diagram\
	$(NULL)

$(DOCDIR)/%.pdf : %.adoc # $(IMAGEDIR)/classes.uxf
	asciidoctor-pdf $(ADOCTOR_OPTS)\
		-a imagesdir=$(IMAGEDIR)\
		--theme ./wetselm-theme.yml\
		-o $@ $<

$(DOCDIR)/%-doc.html : %.adoc
	asciidoctor $(ADOCTOR_OPTS)\
		-a imagesdir=../src/images -o $@ $<

.PHONY : all doc code clean

all : doc code

doc :  $(PDF) # $(HTML)

$(PDF) : $(DOCSRC) $(DOCSRCS) wetselm-theme.yml $(IMAGES)

elm.js : $()
	elm make --optimize --output=$@ $(SRC)/Main.elm

UGFLAGS =\
	--compress 'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe'

#	$(CP) $< $@
$(SITEDIR)/elm.js : elm.js
	uglifyjs $< $(UGFLAGS) | uglifyjs --mangle >$@

code : $(ELMSRCS)
	elm make --optimize --output=$(SITEDIR)/elm.js $(CODEDIR)/Main.elm

clean :
	$(RM) $(CLEANFILES)

#-output $@ $<
$(CODEDIR)/%.elm : %.adoc
	atangle $(ATANGLEOPTS) -root $(notdir $@) $< \
		| elm-format --stdin > $@
