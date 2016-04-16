REPO=mozilla-git
PWD=$(shell pwd)
DIRS=$(shell ls -d */ | sed -e 's/\///' )
ARCHNSPAWN=arch-nspawn
MKARCHROOT=/usr/bin/mkarchroot -C /usr/share/devtools/pacman-multilib.conf
PKGEXT=pkg.tar.xz
GITFETCH=git remote update --prune
GITCLONE=git clone --mirror
CHROOTPATH64=/var/chroot64/$(REPO)
LOCKFILE=/tmp/$(REPO)-sync.lock
PACMAN=pacman -q
REPOADD=repo-add -n --nocolor -R

TARGETS=$(addsuffix /built, $(DIRS))
PULL_TARGETS=$(addsuffix -pull, $(DIRS))
VER_TARGETS=$(addsuffix -ver, $(DIRS))
SHA_TARGETS=$(addsuffix -sha, $(DIRS))
INFO_TARGETS=$(addsuffix -info, $(DIRS))
BUILD_TARGETS=$(addsuffix -build, $(DIRS))

.PHONY: $(DIRS) chroot

all:
	@$(MAKE) gitpull
	$(MAKE) build

clean:
	@sudo rm -rf */*.log */pkg */src */logpipe* $(CHROOTPATH64)

resetall: clean
	@sudo rm -f */built ; \
	sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=0/" $(PWD)/**/PKGBUILD ; \

chroot:
	@if [[ ! -f $(CHROOTPATH64)/root/.arch-chroot ]]; then \
		sudo mkdir -p $(CHROOTPATH64); \
		sudo rm -rf $(CHROOTPATH64)/root; \
		sudo $(MKARCHROOT) $(CHROOTPATH64)/root base-devel ; \
		sudo cp $(PWD)/pacman.conf $(CHROOTPATH64)/root/etc/pacman.conf ;\
		sudo cp $(PWD)/makepkg.conf $(CHROOTPATH64)/root/etc/makepkg.conf ;\
		sudo cp $(PWD)/locale.conf $(CHROOTPATH64)/root/etc/locale.conf ;\
		echo "MAKEFLAGS='-j$$(grep processor /proc/cpuinfo | wc -l)'" | sudo tee -a $(CHROOTPATH64)/root/etc/makepkg.conf ;\
		sudo mkdir -p $(CHROOTPATH64)/root/repo ;\
		sudo bsdtar -czf $(CHROOTPATH64)/root/repo/$(REPO).db.tar.gz -T /dev/null ; \
		sudo ln -sf $(REPO).db.tar.gz $(CHROOTPATH64)/root/repo/$(REPO).db ; \
		sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root /bin/bash -c 'yes | $(PACMAN) -Syu ; yes | $(PACMAN) -S gcc-multilib gcc-libs-multilib p7zip && chmod 777 /tmp' ; \
		echo 'builduser ALL = NOPASSWD: /usr/bin/pacman' | sudo tee -a $(CHROOTPATH64)/root/etc/sudoers.d/builduser ; \
		echo 'builduser:x:1000:100:builduser:/:/usr/bin/nologin\n' | sudo tee -a $(CHROOTPATH64)/root/etc/passwd ; \
		sudo mkdir -p $(CHROOTPATH64)/root/build; \
	fi ; \

build: $(DIRS)

check:
	@echo "REPO    : $(REPO)" ; \
	echo "DIRS    : $(DIRS)" ; \
	echo "PKGEXT  : $(PKGEXT)" ; \
	echo "GITFETCH: $(GITFETCH)" ; \
	echo "GITCLONE: $(GITCLONE)" ; \
	for d in $(DIRS) ; do \
		if [[ ! -f $$d/built ]]; then \
			_newpkgver=$$(bash -c "source $$d/PKGBUILD ; srcdir="$$(pwd)/$$d" pkgver ;") ; \
			_pkgrel=$$(grep '^pkgrel=' $$d/PKGBUILD | cut -d'=' -f2 ) ;\
			echo "$$d: $$_newpkgver-$$_pkgrel" ; \
		fi \
	done

info: $(INFO_TARGETS)

%-info:
	@cd $(PWD)/$* ; \
	makepkg --printsrcinfo | grep depends | while read p; do \
		echo "$*: $$p" ; \
	done ; \

%/built:
	@_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	cd $* ; \
	rm -f *.log ; \
	mkdir -p $(PWD)/$*/tmp ; mv $(PWD)/$*/*$(PKGEXT) $(PWD)/$*/tmp ; \
	$(MAKE) -C $(PWD) $*-build ; \
	if ! ls *.$(PKGEXT) &> /dev/null ; then \
		mv $(PWD)/$*/tmp/*.$(PKGEXT) $(PWD)/$*/ && rm -rf $(PWD)/$*/tmp ; \
		exit 1 ; \
	fi ; \
	sudo rm -rf $(CHROOTPATH64)/$* ; \
	rm -rf $(PWD)/$*/tmp ; \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		cd $(PWD)/$*/$$_gitname ; git log -1 | head -n1 > $(PWD)/$*/built ; \
	else \
		touch $(PWD)/$*/built ; \
	fi ; \

%-chroot: chroot
	@echo "==> Setting up chroot for [$*]" ; \
	sudo rsync -a --delete -q -W -x $(CHROOTPATH64)/root/* $(CHROOTPATH64)/$* ; \

%-sync: %-chroot
	@echo "==> Syncing packages for [$*]" ; \
	if ls */*.$(PKGEXT) &> /dev/null ; then \
		sudo cp -f */*.$(PKGEXT) $(CHROOTPATH64)/$*/repo ; \
		sudo $(REPOADD) $(CHROOTPATH64)/$*/repo/$(REPO).db.tar.gz $(CHROOTPATH64)/$*/repo/*.$(PKGEXT) > /dev/null 2>&1 ; \
	fi ; \

%-build: %-sync
	@echo "==> Building [$*]" ; \
	sudo mkdir -p $(CHROOTPATH64)/$*/build ; \
	sudo rsync -a --delete -q -W -x $(PWD)/$* $(CHROOTPATH64)/$*/build/ ; \
	sudo systemd-nspawn -q -D $(CHROOTPATH64)/$* /bin/bash -c 'yes | $(PACMAN) -Syu && chown builduser -R /build && cd /build/$* && sudo -u builduser makepkg -L --noconfirm --holdver --nocolor -sf > /dev/null'; \
	cp $(CHROOTPATH64)/$*/build/$*/*.$(PKGEXT) $(CHROOTPATH64)/$*/build/$*/*.log $(PWD)/$*/

%-deps:
	@rm -f $(PWD)/$*/built ; \
	for dep in $$(grep ' $* ' $(PWD)/Makefile | cut -d':' -f1) ; do \
		$(MAKE) -s -C $(PWD) $$dep-deps ; \
	done ; \

$(DIRS): chroot
	@if [ ! -f $(PWD)/$@/built ]; then \
		_pkgrel=$$(grep -R '^pkgrel' $(PWD)/$@/PKGBUILD | sed -e 's/pkgrel=//' -e "s/'//g" -e 's/"//g') && \
		sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=$$(($$_pkgrel+1))/" $(PWD)/$@/PKGBUILD ; \
		if ! $(MAKE) $@/built ; then \
			sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=$$_pkgrel/" $(PWD)/$@/PKGBUILD ; \
			exit 1 ; \
		fi ; \
	fi ; \
	sudo rm -rf $(CHROOTPATH64)/$@ $(CHROOTPATH64)/$@.lock ; \

gitpull: $(PULL_TARGETS)

%-pull:
	@_gitroot=$$(grep -R '^_gitroot' $(PWD)/$*/PKGBUILD | sed -e 's/_gitroot=//' -e "s/'//g" -e 's/"//g') && \
	_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	if [ ! -z "$$_gitroot" ] ; then \
		if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
			for f in $(PWD)/$*/*/HEAD; do \
				cd $$(dirname $$f) && $(GITFETCH) ; \
			done ; \
			cd $(PWD)/$*/$$_gitname && \
			if [ -f $(PWD)/$*/built ] && [ "$$(cat $(PWD)/$*/built)" != "$$(git log -1 | head -n1)" ]; then \
				$(MAKE) -s -C $(PWD) $*-ver ; \
				$(MAKE) -s -C $(PWD) $*-rel ; \
				$(MAKE) -s -C $(PWD) $*-deps ; \
			fi ; \
		else \
			$(GITCLONE) $$_gitroot $(PWD)/$*/$$_gitname ; \
			$(MAKE) -s -C $(PWD) $*-deps ; \
		fi ; \
	fi ; \
	cd $(PWD)

vers: $(VER_TARGETS)

%-ver:
	@cd $(PWD)/$* ; \
	_newpkgver=$$(bash -c "source PKGBUILD ; srcdir=$$(pwd) pkgver ;") ; \
	sed --follow-symlinks -i "s/^pkgver=[^ ]*/pkgver=$$_newpkgver/" PKGBUILD ; \
	echo "$*: $$_newpkgver"

%-rel:
	@sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=0/" $(PWD)/$*/PKGBUILD ; \

updateshas: $(SHA_TARGETS)

%-sha:
	@cd $(PWD)/$* && updpkgsums


-include Makefile.mk

firefox-nightly: chroot

