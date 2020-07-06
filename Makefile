define existing
	$(shell test -e $(1) && echo $(1))
endef
define replace_expr
  $(shell test "v$(1)" != "v" && echo 's\#$(1)\#$(2)\#;')
endef
define part
	$(shell sed -n "s/^$(1): \(.*\)/\1/p" $(2))
endef
define dynamic_library
	$(shell grep "^dynamic-library-dirs: " $(1) > /dev/null \
	  && find $$(sed -n "s/dynamic-library-dirs: \(.*\)/\1/p" $(1)) \
		    -depth 1 -name "*$$(sed -n 's/id: \(.*\)/\1/p' $(1))*")
endef
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))

STACK_ROOT:=/tmp/foobar
ROOT:=/tmp/foobaz
LIB_ROOT:=$(ROOT)/lib
DOC_ROOT:=$(ROOT)/doc
DATA_ROOT:=$(ROOT)/share
PKG_DB:=$(ROOT)/pkgdb
STACK:=$(shell which stack)
STACK_CALL:=STACK_ROOT=$(STACK_ROOT) $(STACK)
GHC_PKG:=$(shell $(STACK_CALL) exec -- which ghc-pkg)
GLOBAL_ROOT:=$(dir $(shell $(STACK_CALL) path --compiler-bin))
ifneq (,$(GLOBAL_ROOT))
GLOBAL_PKG_DB:=$(shell $(STACK_CALL) path --global-pkg-db)
GLOBAL_PKG_DB_FILES=$(filter-out $(GLOBAL_PKG_DB)/package.cache.lock, $(filter-out $(GLOBAL_PKG_DB)/package.cache, $(wildcard $(GLOBAL_PKG_DB)/*)))
endif
SNAPSHOT_ROOT:=$(shell $(STACK_CALL) path --snapshot-install-root)
ifneq (,$(SNAPSHOT_ROOT))
SNAPSHOT_PKG_DB:=$(shell $(STACK_CALL) path --snapshot-pkg-db)
SNAPSHOT_PKG_DB_FILES=$(filter-out $(SNAPSHOT_PKG_DB)/package.cache.lock, $(filter-out $(SNAPSHOT_PKG_DB)/package.cache, $(wildcard $(SNAPSHOT_PKG_DB)/*)))
endif
OLD_PKG_DB_FILES=$(SNAPSHOT_PKG_DB_FILES) $(GLOBAL_PKG_DB_FILES)
PKG_DB_FILES_S=$(subst $(SNAPSHOT_PKG_DB),$(PKG_DB),$(SNAPSHOT_PKG_DB_FILES))
PKG_DB_FILES_G=$(subst $(GLOBAL_PKG_DB),$(PKG_DB),$(GLOBAL_PKG_DB_FILES))
PKG_DB_FILES=$(PKG_DB_FILES_S) $(PKG_DB_FILES_G)
SNAPSHOT=$(shell cat $(VERSION_FILE))
SNAPSHOT_BACKUP=$(BACKUP_DIR)/$(shell cat $(VERSION_FILE) | grep -ohe "[0-9a-f]\{64\}")
VERSION_FILE:=version.txt
OLD_VERSION:=$(shell cat $(VERSION_FILE))
LINK_DIR:=/tmp/updated
LINK_SUB_DIR_NAME:=$(shell date +"%Y-%m-%d_%H-%M-%S")
LINK_SUB_DIR:=$(LINK_DIR)/$(LINK_SUB_DIR_NAME)
LINK_SNAPSHOT_ROOT:=$(LINK_SUB_DIR)/snapshot-root
LINK_SNAPSHOT:=$(LINK_SUB_DIR)/snapshot
LINK_GLOBAL_ROOT:=$(LINK_SUB_DIR)/global-root
LINK_GLOBAL:=$(LINK_SUB_DIR)/global
BACKUP_DIR:=/tmp/backup
BACKUP_SUB_DIR_NAME:=$(shell date +"%Y-%m-%d_%H-%M-%S")
BACKUP_SUB_DIR:=$(BACKUP_DIR)/$(BACKUP_SUB_DIR_NAME)
IMPORT_DIRS:=$(foreach package,$(OLD_PKG_DB_FILES),$(call part,import-dirs,$(package)))
LIBRARY_DIRS:=$(foreach package,$(OLD_PKG_DB_FILES),$(call part,library-dirs,$(package)))
DATA_DIRS:=$(foreach package,$(OLD_PKG_DB_FILES),$(call exisiting,$(call part,data-dir,$(package))))
HADDOCK_INTERFACES:=$(foreach package,$(OLD_PKG_DB_FILES),$(call exisiting,$(call part,haddock-interfaces,$(package))))
HADDOCK_HTMLS:=$(foreach package,$(OLD_PKG_DB_FILES),$(call existing,$(call part,haddock-html,$(package))))
DYNAMIC_LIBRARIES:=$(foreach package,$(OLD_PKG_DB_FILES),$(call dynamic_library,$(package)))
TARGET_IMPORT_DIRS:=$(addprefix $(LIB_ROOT)/,$(notdir $(IMPORT_DIRS)))
TARGET_DATA_DIRS:=$(addprefix $(DATA_ROOT)/,$(notdir $(DATA_DIRS)))
TARGET_HADDOCK_HTMLS:=$(addprefix $(DOC_ROOT)/,$(notdir $(HADDOCK_HTMLS)))
TARGET_HADDOCK_INTERFACES:=$(addprefix $(DOC_ROOT)/,$(dir $(notdir $(HADDOCK_INTERFACES)))$(notdir $(HADDOCK_INTERFACES)))
TARGET_DYNAMIC_LIBRARIES:=$(addprefix $(LIB_ROOT)/,$(notdir $(DYNAMIC_LIBRARIES)))
TARGET_LIB_DIRS:=$(call uniq,$(TARGET_IMPORT_DIRS) $(TARGET_DYNAMIC_LIBRARIES))
TARGET_DOC_DIRS:=$(call uniq,$(TARGET_HADDOCK_DIRS) $(TARGET_HADDOCK_INTERFACES))
TARGET_DATA_DIRS:=$(call uniq,$(TARGET_DATA_DIRS))
TARGET_DIRS:=$(TARGET_LIB_DIRS) $(TARGET_DOC_DIRS) $(TARGET_DATA_DIRS)
SRC_LIB_DIRS:=$(call uniq,$(IMPORT_DIRS) $(LIBRARY_DIRS) $(DYNAMIC_LIBRARIES))
SRC_DOC_DIRS:=$(call uniq,$(HADDOCK_INTERFACES) $(HADDOCK_HTMLS))
SRC_DATA_DIRS:=$(call uniq,$(IMPORT_DIRS) $(DATA_DIRS))
export LINK_SUB_DIR_NAME

MAKEFILE:=$(lastword $(MAKEFILE_LIST))

test:
	$(MAKE) -e -f $(MAKEFILE) $(TARGET_DIRS)

.PHONY: all build install link links backup clean
all: | build install link

build: $(VERSION_FILE)

$(VERSION_FILE): stack.yaml package.yaml
	$(STACK_CALL) build .
	echo $(SNAPSHOT_ROOT) > $(VERSION_FILE)

$(TARGET_LIB_DIRS): $(SRC_LIB_DIRS)
	rsync -cr --delete $(filter %$(notdir $@),$^)$(shell test -d $(filter %$(notdir $@),$^) && echo /) $@

$(TARGET_DOC_DIRS): $(SRC_DOC_DIRS)
	rsync -cr --delete $(filter %$(notdir $@),$^)$(shell test -d $(filter %$(notdir $@),$^) && echo /) $@

$(TARGET_DATA_DIRS): $(SRC_DATA_DIRS)
	rsync -cr --delete $(filter %$(notdir $@),$^)$(shell test -d $(filter %$(notdir $@),$^) && echo /) $@

$(PKG_DB) $(LIB_ROOT) $(DATA_ROOT) $(DOC_ROOT): stack.yaml.lock
	rm -rf $@
	mkdir -p $@

ifneq (,$(GLOBAL_ROOT))
$(PKG_DB)/%: $(GLOBAL_PKG_DB)/% stack.yaml.lock
	$(eval $@_import:=$(call replace_expr,$(abspath $(dir $(call part,import-dirs,$<))),$(LIB_ROOT)))
	$(eval $@_data:=$(call replace_expr,$(abspath $(dir $(call part,data-dir,$<))),$(DATA_ROOT)))
	$(eval $@_html:=$(call replace_expr,$(abspath $(dir $(call part,haddock-html,$<))),$(DOC_ROOT)))
	bbe -e '$($@_import)$($@_data)$($@_html)' $< > $@
endif

ifneq (,$(SNAPSHOT_ROOT))
$(PKG_DB)/%: $(SNAPSHOT_PKG_DB)/% stack.yaml.lock
	$(eval $@_import:=$(call replace_expr,$(abspath $(dir $(call part,import-dirs,$<))),$(LIB_ROOT)))
	$(eval $@_data:=$(call replace_expr,$(abspath $(dir $(call part,data-dir,$<))),$(DATA_ROOT)))
	$(eval $@_html:=$(call replace_expr,$(abspath $(dir $(call part,haddock-html,$<))),$(DOC_ROOT)))
	bbe -e '$($@_import)$($@_data)$($@_html)' $< > $@
endif

install: | $(PKG_DB) $(DATA_ROOT) $(LIB_ROOT) $(DOC_ROOT) $(PKG_DB)/package.cache

$(PKG_DB)/package.cache: stack.yaml.lock $(TARGET_DIRS) $(PKG_DB_FILES)
	$(GHC_PKG) recache --package-db=$(PKG_DB)

link: $(VERSION_FILE)
	@test v$(OLD_VERSION) = v$(SNAPSHOT) \
	  || $(MAKE) -e -f $(MAKEFILE) links

$(LINK_SUB_DIR):
	mkdir -p $(LINK_SUB_DIR)

links: $(LINK_SUB_DIR)
ifneq (,$(GLOBAL_ROOT))
	$(MAKE) -e -f $(MAKEFILE) $(LINK_GLOBAL_ROOT)
	$(MAKE) -e -f $(MAKEFILE) $(LINK_GLOBAL)
endif
ifneq (,$(SNAPSHOT_ROOT))
	$(MAKE) -e -f $(MAKEFILE) $(LINK_SNAPSHOT_ROOT)
	$(MAKE) -e -f $(MAKEFILE) $(LINK_SNAPSHOT)
endif

ifneq (,$(GLOBAL_ROOT))
$(LINK_GLOBAL_ROOT): $(GLOBAL_ROOT) $(LINK_SUB_DIR)
	ln -s $< $@

$(LINK_GLOBAL): $(GLOBAL_PKG_DB) $(LINK_SUB_DIR)
	ln -s $< $@
endif

ifneq (,$(SNAPSHOT_ROOT))
$(LINK_SNAPSHOT_ROOT): $(SNAPSHOT_ROOT) $(LINK_SUB_DIR)
	ln -s $< $@

$(LINK_SNAPSHOT): $(SNAPSHOT_PKG_DB) $(LINK_SUB_DIR)
	ln -s $< $@
endif

backup: $(BACKUP_SUB_DIR)

$(BACKUP_SUB_DIR): $(OLD_VERSION_FILE) $(VERSION_FILE)
	@test v$(OLD_VERSION) = v$(shell cat $(VERSION_FILE)) \
	  || ( echo backing up to $(BACKUP_SUB_DIR) \
	  && mkdir -p $(BACKUP_DIR) \
		&& echo rsync $(ROOT) $(SNAPSHOT_BACKUP) \
	  && rsync -ir --delete $(ROOT) $(SNAPSHOT_BACKUP) \
	  && rsync -ir --delete $(PKG_DB) $(SNAPSHOT_BACKUP)/pkgdb \
	  && echo ln -s $(SNAPSHOT_BACKUP) $(BACKUP_SUB_DIR) \
	  && ln -s $(SNAPSHOT_BACKUP) $(BACKUP_SUB_DIR) )

clean: $(ROOT) $(PKG_DB)
	rm -rf $(PKG_DB)
	rm -rf $(ROOT)
