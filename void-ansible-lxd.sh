TMPC=void-$(uuidgen)

USAGE="USAGE: $0 [-l libc] [image name]"

while getopts l: o; do
	case "$o" in
	l)
		TARGETLIBC="$OPTARG"
		;;
	*)
		echo $USAGE
		exit 1
		;;
	esac
done
shift $(($OPTIND - 1))

if [ -n "$1" ]; then
	IMAGENAME="$1"
fi

TARGETLIBC=${TARGETLIBC:-glibc}

case "$TARGETLIBC" in
	glibc)
		BASEIMAGE=images:voidlinux/current
		;;
	musl)
		BASEIMAGE=images:voidlinux/current/musl
		;;
	*)
		echo Invalid libc: $TARGETLIBC
		exit 1
esac

IMAGENAME=${IMAGENAME:-void-ansible-${TARGETLIBC}}

echo "Creating base image $TMPC (from $BASEIMAGE)"
lxc launch $BASEIMAGE $TMPC

lxc file push ${PWD}/id_rsa.pub $TMPC/tmp/id_rsa.pub

(
cat << EOF
#!/bin/sh

# Waiting for internet ...
while :; do
	ping -W1 -c1 linuxcontainers.org >/dev/null 2>&1 && break
	sleep 1
done

ln -s /etc/sv/sshd /var/service/
xbps-install -Syu
xbps-install -Sy python3

useradd -G wheel maintenance
mkdir -p /home/maintenance/.ssh
cp /tmp/id_rsa.pub /home/maintenance/.ssh/authorized_keys
chown -R maintenance:maintenance /home/maintenance/.ssh/authorized_keys
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

xbps-remove --clean-cache
rm /tmp/id_rsa.pub /tmp/init.sh
EOF
) | lxc file push - "${TMPC}/tmp/init.sh" --mode=0755
lxc exec "${TMPC}" -- /tmp/init.sh

lxc stop --force $TMPC
lxc publish $TMPC --alias $IMAGENAME
lxc delete --force $TMPC
