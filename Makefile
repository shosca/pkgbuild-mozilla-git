REPO=mozilla-git
PWD=$(shell pwd)
DIRS=firefox-nightly
DATE=$(shell date +"%Y%m%d")
TIME=$(shell date +"%H%M")
ARCHNSPAWN=arch-nspawn
MKARCHROOT=/usr/bin/mkarchroot
MAKECHROOTPKG=/usr/bin/makechrootpkg -c -u -r
PKGEXT=pkg.tar.xz
GITFETCH=git fetch --all -p
GITCLONE=git clone --mirror
CHROOTPATH64=/var/chroot64/$(REPO)

TARGETS=$(addsuffix /built, $(DIRS))
PULL_TARGETS=$(addsuffix -pull, $(DIRS))
VER_TARGETS=$(addsuffix -ver, $(DIRS))

.PHONY: $(DIRS) checkchroot

all:
	$(MAKE) gitpull
	$(MAKE) build

clean:
	sudo rm -rf */*.log */pkg */src */logpipe*

reset: clean
	sudo rm -f */built

checkchroot:
	@if [ ! -d $(CHROOTPATH64) ]; then \
		echo "Creating working chroot at $(CHROOTPATH64)/root" ; \
		sudo mkdir -p $(CHROOTPATH64) ;\
		[[ ! -f $(CHROOTPATH64)/root/.arch-chroot ]] && sudo $(MKARCHROOT) $(CHROOTPATH64)/root base-devel ; \
		sudo sed -i -e '/^#\[multilib\]/ s,#,,' \
			-i -e '/^\[multilib\]/{$$!N; s,#,,}' $(CHROOTPATH64)/root/etc/pacman.conf ; \
		sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root pacman \
			-Syyu --noconfirm ; \
		sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root \
			/bin/bash -c 'yes | pacman -S gcc-multilib gcc-libs-multilib p7zip' ; \
		sudo mkdir -p $(CHROOTPATH64)/root/repo ;\
		echo "# Added by $$PKG" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "[$(REPO)]" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "SigLevel = Never" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "Server = file:///repo" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "COMPRESSXZ=(7z a dummy -txz -si -so)" | sudo tee -a $(CHROOTPATH64)/root/etc/makepkg.conf ; \
		echo "Recreating working repo $(REPO)" ; \
		if ls */*.$(PKGEXT) &> /dev/null ; then \
			sudo cp -f */*.$(PKGEXT) $(CHROOTPATH64)/root/repo ; \
			sudo repo-add $(CHROOTPATH64)/root/repo/$(REPO).db.tar.gz $(CHROOTPATH64)/root/repo/*.$(PKGEXT) ; \
		fi \
	fi

resetchroot:
	sudo rm -rf $(CHROOTPATH64) && $(MAKE) checkchroot

build:
	@$(MAKE) $(DIRS);

test:
	@echo "REPO    : $(REPO)" ; \
	echo "DIRS    : $(DIRS)" ; \
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
	sudo $(MAKECHROOTPKG) $(CHROOTPATH64) || exit 1 && \
	sudo rm -f $(addsuffix *, $(addprefix $(CHROOTPATH64)/root/repo/, $(shell grep -R '^pkgname' $*/PKGBUILD | sed -e 's/pkgname=//' -e 's/(//g' -e 's/)//g' -e "s/'//g" -e 's/"//g'))) ; \
	sudo cp *.$(PKGEXT) $(CHROOTPATH64)/root/repo/ ; \
	for f in *.$(PKGEXT) ; do \
		sudo repo-add $(CHROOTPATH64)/root/repo/$(REPO).db.tar.gz $(CHROOTPATH64)/root/repo/"$$f" ; \
	done ; \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		cd $(PWD)/$*/$$_gitname ; git log -1 | head -n1 > $(PWD)/$*/built ; \
	else \
		touch $(PWD)/$*/built ; \
	fi ; \
	cd $(PWD) ; \
	rm -f $(addsuffix /built, $(shell grep ' $*' Makefile | cut -d':' -f1)) ; \

$(DIRS): checkchroot
	@if [ ! -f $(PWD)/$@/built ]; then \
		$(MAKE) $@/built ; \
	fi

gitpull: $(PULL_TARGETS)

%-pull:
	@_gitroot=$$(grep -R '^_gitroot' $(PWD)/$*/PKGBUILD | sed -e 's/_gitroot=//' -e "s/'//g" -e 's/"//g') && \
	_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	echo "Pulling $*" ; \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		echo "Updating $$_gitname" ; \
		cd $(PWD)/$*/$$_gitname && \
		$(GITFETCH) && \
		if [ -f $(PWD)/$*/built ] && [ "$$(cat $(PWD)/$*/built)" != "$$(git log -1 | head -n1)" ]; then \
			rm -f $(PWD)/$*/built ; \
		fi ; \
		cd $(PWD) ; \
	fi

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

-include Makefile.mk
