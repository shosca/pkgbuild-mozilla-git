REPO=mozilla-git
PWD=$(shell pwd)
DIRS=$(shell ls -d */ | sed -e 's/\///' )
ARCHNSPAWN=arch-nspawn
MKARCHROOT=/usr/bin/mkarchroot -C /usr/share/devtools/pacman-multilib.conf
PKGEXT=pkg.tar.xz
GITFETCH=git remote update --prune
GITCLONE=git clone --mirror
CHROOTPATH64=/var/chroot64/$(REPO)
MAKECHROOTPKG=OPTIND=--holdver /usr/bin/makechrootpkg -c -u -r $(CHROOTPATH64)
LOCKFILE=$(CHROOTPATH64)/sync.lock

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

checkchroot: emptyrepo recreaterepo syncrepos

buildchroot:
	@if [ ! -d $(CHROOTPATH64) ]; then \
		echo "Creating working chroot at $(CHROOTPATH64)/root" ; \
		sudo mkdir -p $(CHROOTPATH64) ;\
		[[ ! -f $(CHROOTPATH64)/root/.arch-chroot ]] && sudo $(MKARCHROOT) $(CHROOTPATH64)/root base-devel ; \
		$(MAKE) installdeps ; \
	fi ; \

configchroot: buildchroot emptyrepo
	@sudo cp $(PWD)/pacman.conf $(CHROOTPATH64)/root/etc/pacman.conf ;\
	sudo cp $(PWD)/makepkg.conf $(CHROOTPATH64)/root/etc/makepkg.conf ;\
	sudo cp $(PWD)/locale.conf $(CHROOTPATH64)/root/etc/locale.conf ;\

emptyrepo: buildchroot
	@sudo mkdir -p $(CHROOTPATH64)/root/repo/ ; \
	sudo bsdtar -czf $(CHROOTPATH64)/root/repo/$(REPO).db.tar.gz -T /dev/null ; \
	sudo ln -sf $(REPO).db.tar.gz $(CHROOTPATH64)/root/repo/$(REPO).db ; \

installdeps: buildchroot syncrepos
	@sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root /bin/bash -c 'pacman -Sy ; yes | pacman -S gcc-multilib gcc-libs-multilib p7zip' ; \

recreaterepo: buildchroot emptyrepo
	@echo "Recreating working repo $(REPO)" ; \
	if [[ -f $(LOCKFILE) ]]; then \
		while [[ -f $(LOCKFILE) ]]; do sleep 3; done \
	fi ; \
	sudo touch $(LOCKFILE) ; \
	sudo mkdir -p $(CHROOTPATH64)/root/repo ;\
	sudo cp $(PWD)/pacman.conf $(CHROOTPATH64)/root/etc/pacman.conf ;\
	if ls */*.$(PKGEXT) &> /dev/null ; then \
		sudo cp -f */*.$(PKGEXT) $(CHROOTPATH64)/root/repo ; \
		sudo cp -f */*.$(PKGEXT) /var/cache/pacman/pkg ; \
		sudo repo-add $(CHROOTPATH64)/root/repo/$(REPO).db.tar.gz $(CHROOTPATH64)/root/repo/*.$(PKGEXT) ; \
	fi ; \
	sudo rm $(LOCKFILE) ; \

syncrepos: buildchroot recreaterepo
	@if [[ -f $(LOCKFILE) ]]; then \
		while [[ -f $(LOCKFILE) ]]; do sleep 3; done \
	else \
		sudo touch $(LOCKFILE) ; \
		sudo $(ARCHNSPAWN) $(CHROOTPATH64)/root pacman -Syu --noconfirm ; \
		sudo rm $(LOCKFILE) ; \
	fi ; \

resetchroot:
	sudo rm -rf $(CHROOTPATH64) && $(MAKE) checkchroot


build: $(DIRS)

test:
	@echo "REPO    : $(REPO)" ; \
	echo "DIRS    : $(DIRS)" ; \
	echo "PKGEXT  : $(PKGEXT)" ; \
	echo "GITFETCH: $(GITFETCH)" ; \
	echo "GITCLONE: $(GITCLONE)" ; \
	for d in $(DIRS) ; do \
		if [[ ! -f $$d/built ]]; then \
			_newpkgver=$$(bash -c "source $$d/PKGBUILD ; srcdir="$$(pwd)/$$d" pkgver ;") ; \
			echo "$$d: $$_newpkgver" ; \
		fi \
	done

%/built:
	@_gitname=$$(grep -R '^_gitname' $(PWD)/$*/PKGBUILD | sed -e 's/_gitname=//' -e "s/'//g" -e 's/"//g') && \
	cd $* ; \
	rm -f *.log ; \
	mkdir -p $(PWD)/$*/tmp ; mv $(PWD)/$*/*$(PKGEXT) $(PWD)/$*/tmp ; \
	sudo $(MAKECHROOTPKG) -l $* ; \
	if ! ls *.$(PKGEXT) &> /dev/null ; then \
		mv $(PWD)/$*/tmp/*.$(PKGEXT) $(PWD)/$*/ && rm -rf $(PWD)/$*/tmp ; \
		exit 1 ; \
	fi ; \
	rm -rf $(PWD)/$*/tmp ; \
	if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		cd $(PWD)/$*/$$_gitname ; git log -1 | head -n1 > $(PWD)/$*/built ; \
	else \
		touch $(PWD)/$*/built ; \
	fi ; \
	cd $(PWD) ; \
	rm -f $(addsuffix /built, $(shell grep ' $* ' Makefile | cut -d':' -f1)) ; \

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
	if [ ! -z "$$_gitroot" ] ; then \
	  if [ -f $(PWD)/$*/$$_gitname/HEAD ]; then \
		  for f in $(PWD)/$*/*/HEAD; do \
			  cd $$(dirname $$f) && $(GITFETCH) ; \
		  done ; \
		  cd $(PWD)/$*/$$_gitname && \
		  if [ -f $(PWD)/$*/built ] && [ "$$(cat $(PWD)/$*/built)" != "$$(git log -1 | head -n1)" ]; then \
			  rm -f $(PWD)/$*/built ; \
			  $(MAKE) -s -C $(PWD) $*-ver ; \
			  $(MAKE) -s -C $(PWD) $*-rel ; \
		  fi ; \
	  else \
		  $(GITCLONE) $$_gitroot $(PWD)/$*/$$_gitname ; \
		  rm -f $(PWD)/$*/built ; \
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

firefox-nightly: syncrepos

