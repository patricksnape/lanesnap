PREFIX_BIN ?= $(HOME)/.local/bin
HYPR_DIR   ?= $(HOME)/.config/hypr
PLUGIN_DIR ?= $(HOME)/.config/omarchy/plugins/psnape.lanesnap
CONF_DIR   ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/lanesnap
REQUIRE    := require("hypr.lanesnap")
SRC        := $(abspath .)

.PHONY: install uninstall test doctor lint

# Symlinks, not copies: `git pull` (or `omarchy plugin update`) updates the installed scripts too.
install:
	mkdir -p $(PREFIX_BIN) $(HYPR_DIR) $(CONF_DIR) $(dir $(PLUGIN_DIR))
	for f in bin/*; do ln -sf $(SRC)/$$f $(PREFIX_BIN)/$$(basename $$f); done
	ln -sf $(SRC)/hypr/lanesnap.lua $(HYPR_DIR)/lanesnap.lua
	touch $(HYPR_DIR)/bindings.lua
	grep -qF '$(REQUIRE)' $(HYPR_DIR)/bindings.lua || printf '\n-- lanesnap: window snap zones\n$(REQUIRE)\n' >> $(HYPR_DIR)/bindings.lua
	[ -e $(CONF_DIR)/layouts.json ] || cp config/layouts.json $(CONF_DIR)/layouts.json
	[ "$(SRC)" = "$(abspath $(PLUGIN_DIR))" ] || ln -sfn $(SRC) $(PLUGIN_DIR)
	-omarchy-shell shell rescanPlugins
	-omarchy plugin enable psnape.lanesnap
	-hyprctl reload
	@echo "Installed. Run 'make doctor' to check, SUPER+Z to try it."

uninstall:
	-omarchy plugin disable psnape.lanesnap
	for f in bin/*; do rm -f $(PREFIX_BIN)/$$(basename $$f); done
	rm -f $(HYPR_DIR)/lanesnap.lua
	-sed -i '/-- lanesnap: window snap zones/d; /hypr\.lanesnap/d' $(HYPR_DIR)/bindings.lua
	[ "$(SRC)" = "$(abspath $(PLUGIN_DIR))" ] || rm -f $(PLUGIN_DIR)
	-hyprctl reload
	@echo "Removed. Your layouts in $(CONF_DIR) were kept."

doctor:
	bin/lanesnap-doctor

test:
	tests/smoke.sh

lint:
	for f in bin/* lib/hypr.sh tests/smoke.sh; do bash -n $$f || exit 1; done
	jq empty config/layouts.json manifest.json
	@for n in $$(grep -oE 'hl\.(dsp\.[a-z_.]+|workspace_rule)' lib/hypr.sh | sort -u); do grep -qF "$$n" ci/api-check.lua || { echo "ci/api-check.lua is missing $$n (keep it in sync with lib/hypr.sh)"; exit 1; }; done
	@if command -v shellcheck >/dev/null; then shellcheck -x -P SCRIPTDIR bin/* lib/hypr.sh tests/smoke.sh; fi
