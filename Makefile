REPO=mozilla-git
PWD=$(shell pwd)
DIRS=$(shell ls -d */ | sed -e 's/\///' )
ARCHNSPAWN=arch-nspawn
MKARCHROOT=/usr/bin/mkarchroot -C /usr/share/devtools/pacman-multilib.conf
PKGEXT=pkg.tar.xz
CHROOTPATH64=/var/chroot64/$(REPO)
LOCKFILE=/tmp/$(REPO)-sync.lock
PACMAN=pacman -q
REPOADD=repo-add -n --nocolor -R

TARGETS=$(addsuffix /built, $(DIRS))
PULL_TARGETS=$(addsuffix -pull, $(DIRS))
SHA_TARGETS=$(addsuffix -sha, $(DIRS))
INFO_TARGETS=$(addsuffix -info, $(DIRS))
BUILD_TARGETS=$(addsuffix -build, $(DIRS))
CHECKVER_TARGETS=$(addsuffix -checkver, $(DIRS))

.PHONY: $(DIRS) chroot

all:
	@$(MAKE) srcpull
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
		sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root /bin/bash -c "yes | $(PACMAN) -Syu ; yes | $(PACMAN) -S gcc-multilib gcc-libs-multilib p7zip && chmod 777 /tmp" ; \
		echo "builduser ALL = NOPASSWD: /usr/bin/pacman" | sudo tee -a $(CHROOTPATH64)/root/etc/sudoers.d/builduser ; \
		echo "builduser:x:$${SUDO_UID:-$$UID}:100:builduser:/:/usr/bin/nologin\n" | sudo tee -a $(CHROOTPATH64)/root/etc/passwd ; \
		sudo mkdir -p $(CHROOTPATH64)/root/build; \
	fi ; \

build: $(DIRS)

check:
	@echo "==> REPO: $(REPO)" ; \
	echo "==> UID: $${SUDO_UID:-$$UID}" ; \
	for d in $(DIRS) ; do \
		if [[ ! -f $$d/built ]]; then \
			$(MAKE) --silent -C $(PWD) $$d-files; \
		fi \
	done

info: $(INFO_TARGETS)

%-info:
	@cd $(PWD)/$* ; \
	makepkg --printsrcinfo | grep depends | while read p; do \
		echo "$*: $$p" ; \
	done ; \

%-chroot: chroot
	@echo "==> Setting up chroot for [$*]" ; \
	sudo rsync -a --delete -q -W -x $(CHROOTPATH64)/root/* $(CHROOTPATH64)/$* ; \

%-sync: %-chroot
	@echo "==> Syncing packages for [$*]" ; \
	if ls */*.$(PKGEXT) &> /dev/null ; then \
		sudo cp -f */*.$(PKGEXT) $(CHROOTPATH64)/$*/repo ; \
		sudo $(REPOADD) $(CHROOTPATH64)/$*/repo/$(REPO).db.tar.gz $(CHROOTPATH64)/$*/repo/*.$(PKGEXT) > /dev/null 2>&1 ; \
	fi ; \

%/built: %-sync
	@echo "==> Building [$*]" ; \
	rm -f *.log ; \
	mkdir -p $(PWD)/$*/tmp ; mv $(PWD)/$*/*$(PKGEXT) $(PWD)/$*/tmp ; \
	sudo mkdir -p $(CHROOTPATH64)/$*/build ; \
	sudo rsync -a --delete -q -W -x $(PWD)/$* $(CHROOTPATH64)/$*/build/ ; \
	_pkgrel=$$(grep '^pkgrel=' $(CHROOTPATH64)/$*/build/$*/PKGBUILD | cut -d'=' -f2 ) ;\
	_pkgrel=$$(($$_pkgrel+1)) ; \
	sed -i "s/^pkgrel=[^ ]*/pkgrel=$$_pkgrel/" $(CHROOTPATH64)/$*/build/$*/PKGBUILD ; \
	sudo systemd-nspawn -q -D $(CHROOTPATH64)/$* /bin/bash -c 'yes | $(PACMAN) -Syu && chown builduser -R /build && cd /build/$* && sudo -u builduser makepkg -L --noconfirm --holdver --nocolor -sf'; \
	_pkgver=$$(bash -c "cd $(PWD)/$* ; source PKGBUILD ; if type -t pkgver | grep -q '^function$$' 2>/dev/null ; then srcdir=$$(pwd) pkgver ; fi") ; \
	if [ -z "$$_pkgver" ] ; then \
		_pkgver=$$(grep '^pkgver=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
	fi ; \
	_pkgnames=$$(grep -Pzo "pkgname=\((?s)(.*?)\)" $(PWD)/$*/PKGBUILD | sed -e "s/\|'\|\"\|(\|)\|.*=//g") ; \
	if [ -z "$$_pkgnames" ] ; then \
		_pkgnames=$$(grep '^pkgname=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
	fi ; \
	for pkgname in $$_pkgnames; do \
		if ! ls $(CHROOTPATH64)/$*/build/$*/$$pkgname-*$$_pkgver-$$_pkgrel-*$(PKGEXT) 1> /dev/null 2>&1; then \
			echo "==> Could not find $(CHROOTPATH64)/$*/build/$*/$$pkgname-*$$_pkgver-$$_pkgrel-*$(PKGEXT)" ; \
			rm -f $(PWD)/$*/*.$(PKGEXT) ; \
			mv $(PWD)/$*/tmp/*.$(PKGEXT) $(PWD)/$*/ && rm -rf $(PWD)/$*/tmp ; \
			exit 1; \
		else \
			cp $(CHROOTPATH64)/$*/build/$*/$$pkgname-*$$_pkgver-*$(PKGEXT) $(PWD)/$*/ ; \
		fi ; \
	done ; \
	cp $(CHROOTPATH64)/$*/build/$*/*.log $(PWD)/$*/ ; \
    cp $(CHROOTPATH64)/$*/build/$*/PKGBUILD $(PWD)/$*/PKGBUILD ; \
	rm -rf $(PWD)/$*/tmp ; \
	touch $(PWD)/$*/built

$(DIRS): chroot
	@if [ ! -f $(PWD)/$@/built ]; then \
		if ! $(MAKE) $@/built ; then \
			exit 1 ; \
		fi ; \
	fi ; \
	sudo rm -rf $(CHROOTPATH64)/$@ $(CHROOTPATH64)/$@.lock

%-deps:
	@echo "==> Marking dependencies for rebuild [$*]" ; \
	rm -f $(PWD)/$*/built ; \
	for dep in $$(grep ' $* ' $(PWD)/Makefile | cut -d':' -f1) ; do \
		$(MAKE) -s -C $(PWD) $$dep-deps ; \
	done ; \


srcpull: $(PULL_TARGETS)

%-vcs:
	@_gitroot=$$(grep '^_gitroot' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") && \
	_hgroot=$$(grep '^_hgroot' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") && \
	if [ ! -z "$$_gitroot" ] ; then \
		_gitname=$$(grep '^_gitname' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") && \
		if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
			for f in $(PWD)/$*/*/HEAD; do \
				git --git-dir=$$(dirname $$f) remote update --prune ; \
			done ; \
		else \
			git clone --mirror $$_gitroot $(PWD)/$*/$$_gitname ; \
		fi ; \
	elif [ ! -z "$$_hgroot" ] ; then \
		_hgname=$$(grep '^_hgname' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") && \
		if [ -d $(PWD)/$*/$$_hgname/.hg ]; then \
			for f in $(PWD)/$*/*/.hg; do \
				hg --cwd=$$(dirname $$f) pull ; \
			done ; \
		else \
			 hg clone -U $$_hgroot $(PWD)/$*/$$_hgname ; \
		fi ; \
	fi ; \

%-pull: %-vcs
	@_pkgver=$$(bash -c "cd $(PWD)/$* ; source PKGBUILD ; if type -t pkgver | grep -q '^function$$' 2>/dev/null ; then pkgver ; fi") ; \
	if [ ! -z "$$_pkgver" ] ; then \
		echo "==> Updating pkgver [$*]" ; \
		sed -i "s/^pkgver=[^ ]*/pkgver=$$_pkgver/" $(PWD)/$*/PKGBUILD ; \
	else \
		_pkgver=$$(grep '^pkgver=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
	fi ; \
	if [ ! -z "$$_pkgver" ] ; then \
		_pkgnames=$$(grep -Pzo "pkgname=\((?s)(.*?)\)" $(PWD)/$*/PKGBUILD | sed -e "s/\|'\|\"\|(\|)\|.*=//g") ; \
		if [ -z "$$_pkgnames" ] ; then \
			_pkgnames=$$(grep '^pkgname=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
		fi ; \
		for pkgname in $$_pkgnames; do \
			if ! ls $(PWD)/$*/$$pkgname-*$$_pkgver-*$(PKGEXT) 1> /dev/null 2>&1; then \
				echo "==> Updating pkgrel [$*]" ; \
				sed -i "s/^pkgrel=[^ ]*/pkgrel=0/" $(PWD)/$*/PKGBUILD ; \
				$(MAKE) -s -C $(PWD) $*-deps ; \
				break ; \
			fi ; \
		done ; \
	fi ; \

checkvers: $(CHECKVER_TARGETS)

%-checkver:
	@_pkgver=$$(bash -c "cd $(PWD)/$* ; source PKGBUILD ; if type -t pkgver | grep -q '^function$$' 2>/dev/null ; then pkgver ; fi") ; \
	if [ ! -z "$$_pkgver" ] ; then \
		echo "==> Updating pkgver [$*]" ; \
		sed -i "s/^pkgver=[^ ]*/pkgver=$$_pkgver/" $(PWD)/$*/PKGBUILD ; \
	else \
		_pkgver=$$(grep '^pkgver=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
	fi ; \
	echo "==> Package [$*]: $$_pkgver" ; \
	if [ ! -z "$$_pkgver" ] ; then \
		_pkgnames=$$(grep -Pzo "pkgname=\((?s)(.*?)\)" $(PWD)/$*/PKGBUILD | sed -e "s/\|'\|\"\|(\|)\|.*=//g") ; \
		if [ -z "$$_pkgnames" ] ; then \
			_pkgnames=$$(grep '^pkgname=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
		fi ; \
		for pkgname in $$_pkgnames; do \
			if ! ls $(PWD)/$*/$$pkgname-*$$_pkgver-*$(PKGEXT) 1> /dev/null 2>&1; then \
				echo "==> Updating pkgrel [$*]" ; \
				sed -i "s/^pkgrel=[^ ]*/pkgrel=0/" $(PWD)/$*/PKGBUILD ; \
				break ; \
			fi ; \
		done ; \
	fi ; \

%-files:
	@_pkgver=$$(grep '^pkgver=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
	_pkgrel=$$(grep '^pkgrel=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
	_fullver="$$_pkgver-$$_pkgrel" ; \
	_pkgnames=$$(grep -Pzo "pkgname=\((?s)(.*?)\)" $(PWD)/$*/PKGBUILD | sed -e "s/\|'\|\"\|(\|)\|.*=//g") ; \
	if [ -z "$$_pkgnames" ] ; then \
		_pkgnames=$$(grep '^pkgname=' $(PWD)/$*/PKGBUILD | sed -e "s/'\|\"\|.*=//g") ; \
	fi ; \
	for _pkgname in $$_pkgnames; do \
		echo "==> Rebuild $*: $$_pkgname-$$_fullver" ; \
	done ; \

updateshas: $(SHA_TARGETS)

%-sha:
	@cd $(PWD)/$* && updpkgsums


-include Makefile.mk

firefox-nightly: chroot
