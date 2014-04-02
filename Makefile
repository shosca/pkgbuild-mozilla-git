REPO=mozilla-git
PWD=$(shell pwd)
DIRS=$(shell ls -d */ | sed -e 's/\///' )
ARCHNSPAWN=arch-nspawn
MKARCHROOT=/usr/bin/mkarchroot -C /usr/share/devtools/pacman-multilib.conf
MAKECHROOTPKG=/usr/bin/makechrootpkg -c -u -r
PKGEXT=pkg.tar.xz
GITFETCH=git fetch --all -p
GITCLONE=git clone --mirror
CHROOTPATH64=/var/chroot64/$(REPO)

TARGETS=$(addsuffix /built, $(DIRS))
PULL_TARGETS=$(addsuffix -pull, $(DIRS))
VER_TARGETS=$(addsuffix -ver, $(DIRS))
SHA_TARGETS=$(addsuffix -sha, $(DIRS))

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
		sudo mkdir -p $(CHROOTPATH64)/root/repo ;\
		echo "# Added by $$PKG" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "[$(REPO)]" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "SigLevel = Never" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "Server = file:///repo" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "COMPRESSXZ=(7z a dummy -txz -si -so)" | sudo tee -a $(CHROOTPATH64)/root/etc/makepkg.conf ; \
		$(MAKE) recreaterepo ; \
		sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root pacman \
			-Syyu --noconfirm ; \
		sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root \
			/bin/bash -c 'yes | pacman -S gcc-multilib gcc-libs-multilib p7zip' ; \
	fi

resetchroot:
	sudo rm -rf $(CHROOTPATH64) && $(MAKE) checkchroot

recreaterepo:
	echo "Recreating working repo $(REPO)" ; \
	if ls */*.$(PKGEXT) &> /dev/null ; then \
		sudo cp -f */*.$(PKGEXT) $(CHROOTPATH64)/root/repo ; \
		sudo repo-add $(CHROOTPATH64)/root/repo/$(REPO).db.tar.gz $(CHROOTPATH64)/root/repo/*.$(PKGEXT) ; \
	fi ; \

build: $(DIRS)

test:
	@echo "REPO    : $(REPO)" ; \
	echo "DIRS    : $(DIRS)" ; \
	echo "PKGEXT  : $(PKGEXT)" ; \
	echo "GITFETCH: $(GITFETCH)" ; \
	echo "GITCLONE: $(GITCLONE)"

%/built:
	@_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	cd $* ; \
	rm -f *$(PKGEXT) *.log ; \
	sudo $(MAKECHROOTPKG) $(CHROOTPATH64) || exit 1 && \
	sudo rm -f $(addsuffix *, $(addprefix $(CHROOTPATH64)/root/repo/, $(shell grep -R '^pkgname' $*/PKGBUILD | sed -e 's/pkgname=//' -e 's/(//g' -e 's/)//g' -e "s/'//g" -e 's/"//g'))) ; \
	sudo cp *.$(PKGEXT) $(CHROOTPATH64)/root/repo/ && \
	cp $(CHROOTPATH64)/$$USER/startdir/PKGBUILD . && \
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
		_pkgrel=$$(grep -R '^pkgrel' $(PWD)/$@/PKGBUILD | sed -e 's/pkgrel=//' -e "s/'//g" -e 's/"//g') && \
		sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=$$(($$_pkgrel+1))/" $(PWD)/$@/PKGBUILD ; \
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
			_newpkgver="r$$(git --git-dir=$(PWD)/$*/$$_gitname rev-list --count HEAD).$$(git --git-dir=$(PWD)/$*/$$_gitname rev-parse --short HEAD)" ; \
			sed --follow-symlinks -i "s/^pkgver=[^ ]*/pkgver=$$_newpkgver/" $(PWD)/$*/PKGBUILD ; \
			sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=0/" $(PWD)/$*/PKGBUILD ; \
		fi ; \
		cd $(PWD) ; \
	fi

vers: $(VER_TARGETS)

%-ver:
	@_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	if [ -d $(PWD)/$*/$$_gitname ]; then \
		_newpkgver="r$$(git --git-dir=$(PWD)/$*/$$_gitname rev-list --count HEAD).$$(git --git-dir=$(PWD)/$*/$$_gitname rev-parse --short HEAD)" ; \
		sed --follow-symlinks -i "s/^pkgver=[^ ]*/pkgver=$$_newpkgver/" $(PWD)/$*/PKGBUILD ; \
		echo "$* r$$(git --git-dir=$(PWD)/$*/$$_gitname rev-list --count HEAD).$$(git --git-dir=$(PWD)/$*/$$_gitname rev-parse --short HEAD)" ; \
	fi

updateshas: $(SHA_TARGETS)

%-sha:
	@cd $(PWD)/$* && updpkgsums

-include Makefile.mk
