
simulate.html : ../simulation/simulate.sh Makefile
	(cd ../simulation && ./simulate.sh 2>&1) | tee /dev/tty | ansi2html -p > $@

