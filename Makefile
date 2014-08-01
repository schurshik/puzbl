# PUZBL
# Makefile
# Developer: Branitskiy Alexander <schurshick@yahoo.com>

PROJ = puzbl
OUT = $(PROJ)
SRC = src/puzblmain.pl src/puzbl.pm src/puzbltab.pm
INSTPATH = /usr/bin

$(OUT): $(SRC)
	@$(foreach FILE,$(SRC),$(shell cat $(FILE) | perl -p -e "s/.*#---\n//" >> $(OUT)))
	chmod +x $(OUT)

.PHONY: clean install uninstall

clean:
	rm -f $(OUT)

install:
	cp -f $(OUT) $(INSTPATH)

uninstall:
	rm -f $(INSTPATH)/$(OUT)
