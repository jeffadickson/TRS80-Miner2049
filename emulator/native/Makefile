# the native playtester: make, then ./m3test explore | play | check | trace
CXX ?= g++
m3test: m3test.cpp z80.h
	$(CXX) -O2 -std=c++17 -o m3test m3test.cpp -lz -lpthread
clean:
	rm -f m3test
