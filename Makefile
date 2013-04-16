REPO=mozilla-git
LOCAL=/home/serkan/public_html/arch/$(REPO)
REMOTE=74.72.157.140:/home/serkan/public_html/arch/$(REPO)

PWD=$(shell pwd)
DIRS=firefox-nightly
DATE=$(shell date +"%Y%m%d")
TIME=$(shell date +"%H%M")
PACMAN=sudo pacman
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
	rsync -v --recursive --links --times -D --delete \
		$(LOCAL)/ \
		$(REMOTE)/

pull:
	rsync -v --recursive --links --times -D --delete \
		$(REMOTE)/ \
		$(LOCAL)/

clean:
	find -name '*$(PKGEXT)' -exec rm {} \;
	find -name 'built' -exec rm {} \;
	rm -f */*.log $(LOCAL)/*$(PKGEXT)

show:
	@echo $(DATE)
	@echo $(DIRS)

updateversions:
	sed -i "s/^pkgver=[^ ]*/pkgver=$(DATE)/" */PKGBUILD ; \
	sed -i "s/^pkgrel=[^ ]*/pkgrel=$(TIME)/" */PKGBUILD

build: $(DIRS)

test:
	_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	echo $$_gitname

%/built:
	@_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		sed -i "s/^pkgver=[^ ]*/pkgver=$(DATE)/" "$(PWD)/$*/PKGBUILD" ; \
		sed -i "s/^pkgrel=[^ ]*/pkgrel=$(TIME)/" "$(PWD)/$*/PKGBUILD" ; \
	fi ; \
	rm -f $(PWD)/$*/*$(PKGEXT) $(PWD)/$*/*.log ; \
	cd $* ; yes y$$'\n' | $(MAKEPKG) || exit 1 && \
	yes y$$'\n' | $(PACMAN) -U --force *$(PKGEXT) && \
	cd $(PWD) && \
	rm -f $(addsuffix *, $(addprefix $(LOCAL)/, $(shell grep -R '^pkgname' $*/PKGBUILD | sed -e 's/pkgname=//' -e 's/(//g' -e 's/)//g' -e "s/'//g" -e 's/"//g'))) && \
	rm -f $(addsuffix /built, $(shell grep $* Makefile | cut -d':' -f1)) && \
	repo-remove $(LOCAL)/$(REPO).db.tar.gz $(shell grep -R '^pkgname' $*/PKGBUILD | sed -e 's/pkgname=//' -e 's/(//g' -e 's/)//g' -e "s/'//g" -e 's/"//g') ; \
	mv $*/*$(PKGEXT) $(LOCAL) && \
	repo-add $(LOCAL)/$(REPO).db.tar.gz $(addsuffix *, $(addprefix $(LOCAL)/, $(shell grep -R '^pkgname' $*/PKGBUILD | sed -e 's/pkgname=//' -e 's/(//g' -e 's/)//g' -e "s/'//g" -e 's/"//g'))) && \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		cd $(PWD)/$*/$$_gitname && \
		git log -1 | head -n1 > $(PWD)/$*/built ; \
	else \
		touch $(PWD)/$*/built ; \
	fi

rebuildrepo:
	cd $(LOCAL)
	rm -rf $(LOCAL)/$(REPO).db*
	repo-add $(LOCAL)/$(REPO).db.tar.gz $(LOCAL)/*$(PKGEXT)

$(DIRS):
	@_gitroot=$$(grep -R '^_gitroot' $(PWD)/$@/PKGBUILD | sed -e 's/_gitroot=//' -e "s/'//g" -e 's/"//g') && \
	_gitname=$$(grep -R '^_gitname' $(PWD)/$@/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	if [ -z $$_gitroot ]; then \
		$(MAKE) $@/built ; \
	else \
		if [ -f $(PWD)/$@/$$_gitname/HEAD ]; then \
			echo "Updating $$_gitname" ; \
			cd $(PWD)/$@/$$_gitname && $(GITFETCH) && \
			if [ -f $(PWD)/$@/built ] && [ "$$(cat $(PWD)/$@/built)" != "$$(git log -1 | head -n1)" ]; then \
				rm -f $(PWD)/$@/built ; \
			fi ; \
			cd $(PWD) ; \
		else \
			echo "Cloning $$_gitroot to $@/$$_gitname" ; \
			$(GITCLONE) $$_gitroot $(PWD)/$@/$$_gitname ; \
		fi ; \
		$(MAKE) $@/built ; \
	fi ; \

PULL_TARGETS=$(addsuffix -pull, $(DIRS))

gitpull: $(PULL_TARGETS)

%-pull:
	@_gitroot=$$(grep -R '^_gitroot' $(PWD)/$*/PKGBUILD | sed -e 's/_gitroot=//' -e "s/'//g" -e 's/"//g') && \
	_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		echo "Updating $$_gitname" ; \
		cd $(PWD)/$*/$$_gitname && \
		$(GITFETCH) && \
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
		fi ; \
	fi

