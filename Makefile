.PHONY: all doc code clean

all: doc code

doc:
	$(MAKE) --directory=./docsrc doc

code:
	$(MAKE) --directory=./docsrc code

clean:
	$(MAKE) --directory=./docsrc clean
