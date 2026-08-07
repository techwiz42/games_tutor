# Builds priv/pdeathsig_wrapper (see c_src/pdeathsig_wrapper.c) via
# elixir_make, invoked automatically as part of `mix compile` -- see
# mix.exs's `compilers:` list. Same mechanism bcrypt_elixir (already a
# dependency here) uses for its own NIF.

PRIV_DIR = priv
WRAPPER = $(PRIV_DIR)/pdeathsig_wrapper

all: $(WRAPPER)

$(WRAPPER): c_src/pdeathsig_wrapper.c
	mkdir -p $(PRIV_DIR)
	$(CC) -O2 -o $@ $<

clean:
	rm -f $(WRAPPER)

.PHONY: all clean
