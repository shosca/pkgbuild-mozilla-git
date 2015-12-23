REPO=mozilla-git
PWD=$(shell pwd)
DIRS=$(shell ls -d */ | sed -e 's/\///' )
ARCHNSPAWN=arch-nspawn
MKARCHROOT=/usr/bin/mkarchroot -C /usr/share/devtools/pacman-multilib.conf
PKGEXT=pkg.tar.xz
GITFETCH=git fetch --all -p
GITCLONE=git clone --mirror
CHROOTPATH64=/var/chroot64/$(REPO)
MAKECHROOTPKG=/usr/bin/makechrootpkg -c -u -r $(CHROOTPATH64)

TARGETS=$(addsuffix /built, $(DIRS))
PULL_TARGETS=$(addsuffix -pull, $(DIRS))
VER_TARGETS=$(addsuffix -ver, $(DIRS))
SHA_TARGETS=$(addsuffix -sha, $(DIRS))

.PHONY: $(DIRS) checkchroot

all:
	$(MAKE) gitpull
	$(MAKE) build

clean:
	sudo rm -rf */*.log */pkg */src */logpipe* $(CHROOTPATH64)

reset: clean
	sudo rm -f */built ; \
	sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=0/" $(PWD)/**/PKGBUILD ; \

checkchroot:
	@if [ ! -d $(CHROOTPATH64) ]; then \
		echo "Creating working chroot at $(CHROOTPATH64)/root" ; \
		sudo mkdir -p $(CHROOTPATH64) ;\
		[[ ! -f $(CHROOTPATH64)/root/.arch-chroot ]] && sudo $(MKARCHROOT) $(CHROOTPATH64)/root base-devel ; \
		sudo sed -i -e '/^#\[multilib\]/ s,#,,' \
			-i -e '/^\[multilib\]/{$$!N; s,#,,}' $(CHROOTPATH64)/root/etc/pacman.conf ; \
		sudo mkdir -p $(CHROOTPATH64)/root/repo ;\
		echo "# Added by $$PKG" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "COMPRESSXZ=(7z a dummy -txz -si -so)" | sudo tee -a $(CHROOTPATH64)/root/etc/makepkg.conf ; \
		echo 'LANG="en_US.UTF-8"' | sudo tee -a $(CHROOTPATH64)/root/etc/locale.conf ; \
		echo 'LANGUAGE="en_US:en"' | sudo tee -a $(CHROOTPATH64)/root/etc/locale.conf ; \
		sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root /bin/bash -c 'yes | pacman -S gcc-multilib gcc-libs-multilib p7zip' ; \
		sudo bsdtar -czf $(CHROOTPATH64)/root/repo/$(REPO).db.tar.gz -T /dev/null ; \
		sudo ln -sf $(REPO).db.tar.gz $(CHROOTPATH64)/root/repo/$(REPO).db ; \
		echo "[$(REPO)]" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "SigLevel = Never" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
		echo "Server = file:///repo" | sudo tee -a $(CHROOTPATH64)/root/etc/pacman.conf ; \
	fi ; \
	$(MAKE) recreaterepo ; \

resetchroot:
	sudo rm -rf $(CHROOTPATH64) && $(MAKE) checkchroot

recreaterepo:
	@echo "Recreating working repo $(REPO)" ; \
	if ls */*.$(PKGEXT) &> /dev/null ; then \
		sudo cp -f */*.$(PKGEXT) $(CHROOTPATH64)/root/repo ; \
		sudo cp -f */*.$(PKGEXT) /var/cache/pacman/pkg ; \
		sudo repo-add $(CHROOTPATH64)/root/repo/$(REPO).db.tar.gz $(CHROOTPATH64)/root/repo/*.$(PKGEXT) ; \
	fi ; \
	sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root pacman -Syyu --noconfirm ; \

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
	rm -f *.log ; \
	mkdir -p tmp ; mv *$(PKGEXT) tmp ; \
	sudo $(MAKECHROOTPKG) -l $* ; \
	if ! ls *.$(PKGEXT) &> /dev/null ; then \
		mv tmp/*.$(PKGEXT) . && rm -rf tmp ; \
		exit 1 ; \
	fi ; \
	rm -rf tmp ; \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		cd $(PWD)/$*/$$_gitname ; git log -1 | head -n1 > $(PWD)/$*/built ; \
	else \
		touch $(PWD)/$*/built ; \
	fi ; \
	cd $(PWD) ; \
	$(MAKE) recreaterepo ; \
	rm -f $(addsuffix /built, $(shell grep ' $*' Makefile | cut -d':' -f1)) ; \

$(DIRS): checkchroot
	@if [ ! -f $(PWD)/$@/built ]; then \
		_pkgrel=$$(grep -R '^pkgrel' $(PWD)/$@/PKGBUILD | sed -e 's/pkgrel=//' -e "s/'//g" -e 's/"//g') && \
		sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=$$(($$_pkgrel+1))/" $(PWD)/$@/PKGBUILD ; \
		if ! $(MAKE) $@/built ; then \
			sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=$$_pkgrel/" $(PWD)/$@/PKGBUILD ; \
			exit 1 ; \
		fi ; \
	fi ; \
	sudo rm -rf $(CHROOTPATH64)/$@

gitpull: $(PULL_TARGETS)

%-pull:
	@_gitroot=$$(grep -R '^_gitroot' $(PWD)/$*/PKGBUILD | sed -e 's/_gitroot=//' -e "s/'//g" -e 's/"//g') && \
	_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	echo "Pulling $*" ; \
	for f in $(PWD)/$*/*/HEAD; do \
		cd $$(dirname $$f) && $(GITFETCH) ; \
	done ; \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		echo "Updating $$_gitname" ; \
		cd $(PWD)/$*/$$_gitname && \
		if [ -f $(PWD)/$*/built ] && [ "$$(cat $(PWD)/$*/built)" != "$$(git log -1 | head -n1)" ]; then \
			rm -f $(PWD)/$*/built ; \
			$(MAKE) -C $(PWD) $*-ver ; \
			$(MAKE) -C $(PWD) $*-rel ; \
		fi ; \
		cd $(PWD) ; \
	fi

vers: $(VER_TARGETS)

%-ver:
	@cd $(PWD)/$* ; \
	_newpkgver=$$(bash -c "source PKGBUILD ; export srcdir=$$(pwd) ; pkgver") ; \
	sed --follow-symlinks -i "s/^pkgver=[^ ]*/pkgver=$$_newpkgver/" PKGBUILD ; \
	echo "$*: $$_newpkgver"

%-rel:
	@sed --follow-symlinks -i "s/^pkgrel=[^ ]*/pkgrel=0/" $(PWD)/$*/PKGBUILD ; \

updateshas: $(SHA_TARGETS)

%-sha:
	@cd $(PWD)/$* && updpkgsums

-include Makefile.mk

