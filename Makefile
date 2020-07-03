define existing
	$(shell test -e $(1) && echo $(1))
endef
define replace_expr
  $(shell test "$(1)" != "" && echo 's\#$(1)\#$(2)\#;')
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
GHC_PKG:=$(shell which ghc-pkg)
OLD_ROOT:=$(shell $(STACK_CALL) path --snapshot-install-root)
OLD_PKG_DB:=$(shell $(STACK_CALL) path --snapshot-pkg-db)
OLD_ROOT_FILES=$(filter-out $(OLD_PKG_DB),$(wildcard $(OLD_ROOT)/*))
ROOT_FILES=$(subst $(OLD_ROOT),$(ROOT),$(OLD_ROOT_FILES))
OLD_PKG_DB_FILES=$(filter-out $(OLD_PKG_DB)/package.cache.lock, $(filter-out $(OLD_PKG_DB)/package.cache, $(wildcard $(OLD_PKG_DB)/*)))
PKG_DB_FILES=$(subst $(OLD_PKG_DB),$(PKG_DB),$(OLD_PKG_DB_FILES))
SNAPSHOT=$(shell cat $(VERSION_FILE))
SNAPSHOT_BACKUP=$(BACKUP_DIR)/$(shell cat $(VERSION_FILE) | grep -ohe "[0-9a-f]\{64\}")
VERSION_FILE:=version.txt
OLD_VERSION:=$(shell cat $(VERSION_FILE))
LINK_DIR:=/tmp/updated
LINK_SUB_DIR_NAME:=$(shell date +"%Y-%m-%d_%H-%M-%S")
LINK_SUB_DIR:=$(LINK_DIR)/$(LINK_SUB_DIR_NAME)
LINK_SNAPSHOT_ROOT:=$(LINK_SUB_DIR)/snapshot-root
LINK_SNAPSHOT:=$(LINK_SUB_DIR)/snapshot
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
TARGET_DIRS:=$(call uniq,$(TARGET_IMPORT_DIRS) $(TARGET_DATA_DIRS) $(TARGET_HADDOCK_DIRS) $(TARGET_HADDOCK_INTERFACES) $(TARGET_DYNAMIC_LIBRARIES))
SRC_DIRS:=$(call uniq,$(IMPORT_DIRS) $(LIBRARY_DIRS) $(DATA_DIRS) $(HADDOCK_INTERFACES) $(HADDOCK_HTMLS) $(DYNAMIC_LIBRARIES))

MAKEFILE:=$(lastword $(MAKEFILE_LIST))

test:
	$(MAKE) -e -f $(MAKEFILE) $(TARGET_DIRS)

.PHONY: all build install link backup clean-pkgdb
all: | build install link

build: $(VERSION_FILE)

$(VERSION_FILE): stack.yaml package.yaml
	$(STACK_CALL) build .
	echo $(OLD_ROOT) > $(VERSION_FILE)

$(TARGET_DIRS): $(SRC_DIRS)
	rsync -cr --delete $(filter %$(notdir $@),$^)$(shell test -d $(filter %$(notdir $@),$^) && echo /) $@

$(ROOT):
	test -d $@ || mkdir -p $@

$(PKG_DB) $(LIB_ROOT) $(DOC_ROOT): stack.yaml.lock
	rm -rf $@
	mkdir -p $@

$(PKG_DB)/%: $(OLD_PKG_DB)/% stack.yaml.lock
	$(eval $@_import:=$(call replace_expr,$(abspath $(dir $(call part,import-dirs,$<))),$(LIB_ROOT)))
	$(eval $@_data:=$(call replace_expr,$(abspath $(dir $(call part,data-dir,$<))),$(DATA_ROOT)))
	$(eval $@_html:=$(call replace_expr,$(abspath $(dir $(call part,haddock-html,$<))),$(DOC_ROOT)))
	bbe -e '$($@_import)$($@_data)$($@_html)' $< > $@

$(ROOT)/%: $(OLD_ROOT)/% $(ROOT) stack.yaml.lock
	rsync -cr --delete $< $@

install: $(PKG_DB)/package.cache

$(PKG_DB)/package.cache: stack.yaml.lock | $(PKG_DB) $(LIB_ROOT) $(DOC_ROOT) $(PKG_DB_FILES) $(TARGET_DIRS)
	ghc-pkg recache --package-db=$(PKG_DB)

link: $(LINK_SUB_DIR)

$(LINK_SUB_DIR): $(VERSION_FILE)
	@export LINK_SUB_DIR=$(LINK_SUB_DIR) \
	  && test v$(OLD_VERSION) = v$(SNAPSHOT) \
	  || ( echo linking $$LINK_SUB_DIR to $(SNAPSHOT) \
	  && mkdir -p $(LINK_SUB_DIR) \
	  && $(MAKE) -e -f $(MAKEFILE) $(LINK_SNAPSHOT_ROOT) \
	  && $(MAKE) -e -f $(MAKEFILE) $(LINK_SNAPSHOT) )

$(LINK_SNAPSHOT_ROOT): $(OLD_ROOT) $(LINK_SUB_DIR)
	ln -s $< $@

$(LINK_SNAPSHOT): $(OLD_PKG_DB) $(LINK_SUB_DIR)
	ln -s $< $@

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
