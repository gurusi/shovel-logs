NAME=shovel-logs
VERSION=0.16
PACKAGE=$(NAME)_$(VERSION).deb

.PHONY: package

package:
	# NOTE: if you'd like to debug the package creation process, give give
	# --debug-workspace switch to fpm and inspect the build directories (in
	#  /tmp/package-*)
	fpm \
		--force \
		-s dir -t deb -n$(NAME) -v$(VERSION) --architecture=all \
		--exclude *.swp \
		--config-files=./etc/guru/ \
		--depends=libguru \
		./bin/=/usr/bin ./etc/=/etc

# vim: set ts=4 noet cc=80:
