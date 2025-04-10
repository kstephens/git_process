
all : simulate.html

clean :
	rm -f simulate.html

simulate.ansi : ../simulation/simulate.sh # Makefile
	(cd ../simulation && ./simulate.sh 2>&1) | tee /dev/tty > $@

simulate.html : simulate.ansi Makefile
	ansi2html -p < simulate.ansi | perl -pne 's@<BODY>@<BODY style="color: gray; background: black">@g; s@line-height: 1;@line-height: 1.2;@g; s@<br>@<br>\n@g; s@(</HTML>)@$$1\n@g;' > $@

