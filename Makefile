SHARE_DIR := $(shell carton exec perl -Ilib -MFile::ShareDir=dist_dir -e \
	'print dist_dir("Dist-Zilla-PluginBundle-Author-GSG")' 2>/dev/null)

MAKEFILE=$(lastword $(MAKEFILE_LIST))
# Making it .PHONY will force it to copy even if this one is newer.
.PHONY: ${MAKEFILE}
update: ${MAKEFILE}
	${MAKE} FORCE=true $@

ifeq ($(SHARE_DIR)$(FORCE),)
${MAKEFILE}:
	carton install || true
	${MAKE} FORCE=true $@

else
${MAKEFILE}: $(SHARE_DIR)/Makefile.inc
	cp $< $@

$(SHARE_DIR)/Makefile.inc:
	@echo Something went wrong, make sure you followed the instructions >&2
	@echo "to install carton and run 'carton install'." >&2
	@echo "'$@' not found" >&2
	@false
endif

# Seems something went wrong and SHARE_DIR is empty,
# that means we need to complain and bail out.
# Hopefully the shell command above provided a useful message.
/Makefile.inc:
	@echo Something went wrong, make sure you followed the instructions >&2
	@echo "to install carton and run 'carton install'." >&2
	@false

