# Miner 2049er for the TRS-80 Model III (a port of the Atari game), Z80 assembly.
#
#   make            assemble src/ with zmac, make the cassette images, verify all three
#   make test       verify, then the regression suite in the emulator (python3, pip install z80)
#   make test-full  ... plus the explorer on all 10 stations
#   make native     build the C++ playtester (emulator/native/m3test; needs g++ and zlib)
#   make web        rebuild web/out/index.html, the browser-playable version
#   make regen      regenerate src/data.asm and src/tables.asm from the Atari cartridge
#                   (needs your own dump at rom/atari_miner.rom; not distributed)
#
# The binaries must match these SHA-256s byte for byte:
SHA_CMD  := 8a93240f4604b3aa8c7706de4ac8a94a35794a190402f899cfde2baac1f47385
SHA_CASH := 0905039c56afce6edc831306f2034c7d430ef288093659a262ee8c08f781c0fc
SHA_CASL := eb446a873fc3a5ef26a6031bafbe524b23dd9414e118fa2456635ffc1f5937f9

SHA := $(shell command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo "shasum -a 256")
SRC := src/miner3.asm src/specials.asm src/data.asm src/tables.asm

.PHONY: all verify test test-full native web regen clean

all: verify

build/miner3.cmd build/miner3.lst: $(SRC)
	@mkdir -p build
	cd src && zmac --zmac -o ../build/miner3.cmd -o ../build/miner3.lst miner3.asm

build/MINER3H.CAS build/MINER3L.CAS: build/miner3.cmd tools/mkcas.py
	python3 tools/mkcas.py build/miner3.cmd build/MINER3 MINER3

define check
	@got=$$($(SHA) $(1) | cut -d' ' -f1); \
	if [ "$$got" = "$(2)" ]; then echo "VERIFIED  $(1)"; \
	else echo "MISMATCH  $(1): SHA-256 $$got, expected $(2)"; exit 1; fi
endef

verify: build/miner3.cmd build/MINER3H.CAS build/MINER3L.CAS
	$(call check,build/miner3.cmd,$(SHA_CMD))
	$(call check,build/MINER3H.CAS,$(SHA_CASH))
	$(call check,build/MINER3L.CAS,$(SHA_CASL))

test: verify
	cd tests && python3 regress.py --no-build

test-full: verify
	cd tests && python3 regress.py --no-build --full

native:
	$(MAKE) -C emulator/native

web: build/miner3.cmd
	python3 tools/build_web.py

regen:
	@[ -f rom/atari_miner.rom ] || { echo "regen needs your own Atari cartridge dump at rom/atari_miner.rom"; exit 1; }
	python3 tools/gen_data.py
	$(MAKE) verify

clean:
	rm -f build/miner3.lst build/*.o
