REPO=mozilla-git
LOCAL=~/public_html/arch/$(REPO)
REMOTE=buttercup.local:~/public_html/arch/$(REPO)

PWD=$(shell pwd)
DIRS=firefox-nightly
DATE=$(shell date +"%Y%m%d")
TIME=$(shell date +"%H%M")
PACMAN=yaourt
MAKEPKG=makepkg -sfLc
PKGEXT=pkg.tar.xz
GITFETCH=git fetch --all -p
GITCLONE=git clone --mirror

TARGETS=$(addsuffix /built, $(DIRS))

.PHONY: $(DIRS)

all:
	$(MAKE) pull
	$(MAKE) build
	$(MAKE) push

push:
	$(MAKE) rebuildrepo
	$(MAKE) pkgpush

pkgpush:
	rsync -v --recursive --links --times -D --delete \
		$(LOCAL)/ \
		$(REMOTE)/

pull:
	rsync -v --recursive --links --times -D --delete \
		$(REMOTE)/ \
		$(LOCAL)/

clean:
	sudo rm -rf */*.log */pkg */src */logpipe*

reset: clean
	sudo rm -f */built $(LOCAL)/*

show:
	@echo $(DATE)
	@echo $(DIRS)

updateversions:
	sed -i "s/^pkgver=[^ ]*/pkgver=$(DATE)/" */PKGBUILD ; \
	sed -i "s/^pkgrel=[^ ]*/pkgrel=$(TIME)/" */PKGBUILD

build: $(DIRS)

test:
	@echo "REPO    : $(REPO)" ; \
	echo "LOCAL   : $(LOCAL)" ; \
	echo "REMOTE  : $(REMOTE)" ; \
	echo "PACMAN  : $(PACMAN)" ; \
	echo "PKGEXT  : $(PKGEXT)" ; \
	echo "GITFETCH: $(GITFETCH)" ; \
	echo "GITCLONE: $(GITCLONE)"

%/built:
	@_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		sed -i "s/^pkgver=[^ ]*/pkgver=$(DATE)/" "$(PWD)/$*/PKGBUILD" ; \
		sed -i "s/^pkgrel=[^ ]*/pkgrel=$(TIME)/" "$(PWD)/$*/PKGBUILD" ; \
	fi ; \
	cd $* ; \
	rm -f *$(PKGEXT) *.log ; \
	yes y$$'\n' | $(MAKEPKG) || exit 1 && \
	yes y$$'\n' | $(PACMAN) -U --force *.$(PKGEXT) ; \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		cd $(PWD)/$*/$$_gitname ; git log -1 | head -n1 > $(PWD)/$*/built ; \
	else \
		touch $(PWD)/$*/built ; \
	fi ; \
	cd $(PWD) ; \
	rm -f $(addsuffix /built, $(shell grep ' $*' Makefile | cut -d':' -f1)) ; \

#	rm -f $(addsuffix *, $(addprefix $(LOCAL)/, $(shell grep -R '^pkgname' $*/PKGBUILD | sed -e 's/pkgname=//' -e 's/(//g' -e 's/)//g' -e "s/'//g" -e 's/"//g'))) ; \

rebuildrepo:
	@cd $(LOCAL) ; \
	rm -f $(LOCAL)/* ; \
	cp $(PWD)/*/*.$(PKGEXT) . ; \
	repo-add -q $(LOCAL)/$(REPO).db.tar.gz $(LOCAL)/*$(PKGEXT)

$(DIRS):
	@if [ ! -f $(PWD)/$@/built ]; then \
		$(MAKE) $@/built ; \
	fi

PULL_TARGETS=$(addsuffix -pull, $(DIRS))

gitpull: $(PULL_TARGETS)

%-pull:
	@_gitroot=$$(grep -R '^_gitroot' $(PWD)/$*/PKGBUILD | sed -e 's/_gitroot=//' -e "s/'//g" -e 's/"//g') && \
	_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		echo "Updating $$_gitname" ; \
		cd $(PWD)/$*/$$_gitname && \
		$(GITFETCH) && \
		if [ -f $(PWD)/$*/built ] && [ "$$(cat $(PWD)/$*/built)" != "$$(git log -1 | head -n1)" ]; then \
			rm -f $(PWD)/$*/built ; \
		fi ; \
		cd $(PWD) ; \
	fi

VER_TARGETS=$(addsuffix -ver, $(DIRS))

vers: $(VER_TARGETS)

%-ver:
	@_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	if [ -d $(PWD)/$*/src/$$_gitname ]; then \
		cd $(PWD)/$*/src/$$_gitname && \
		autoreconf -f > /dev/null 2>&1 && \
		_oldver=$$(grep -R '^_realver' $(PWD)/$*/PKGBUILD | sed -e 's/_realver=//' -e "s/'//g" -e 's/"//g') && \
		_realver=$$(grep 'PACKAGE_VERSION=' configure | head -n1 | sed -e 's/PACKAGE_VERSION=//' -e "s/'//g") ; \
		if [ ! -z $$_realver ] && [ $$_oldver != $$_realver ]; then \
			echo "$(subst -git,,$*) : $$_oldver $$_realver" ; \
			sed -i "s/^_realver=[^ ]*/_realver=$$_realver/" "$(PWD)/$*/PKGBUILD" ; \
			rm -f "$(PWD)/$*/built" ; \
		fi ; \
	fi

