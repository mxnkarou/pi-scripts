#!/bin/bash

# echo "$pass" | sudo -S ./build.sh
# echo "$pass" | sudo -S ./build.sh --clean

# Builds a Raspbian lite image with some customizations include default locale, username, pwd, host name, boot setup customize etc.
# Must be run on Debian Buster or Ubuntu Xenial and requires some "horsepower".

SECONDS=0
clean=false

while [[ $# -ge 1 ]]; do
    i="$1"
    case $i in
        -c|--clean)
            clean=true
            shift
            ;;
        *)
            echo "Unrecognized option $1"
            exit 1
            ;;
    esac
    shift
done

read -r -t 2 -d $'\0' pi_pwd

if [ -z "$pi_pwd" ]; then
  echo "Pi user password is required (pass via stdin)" >&2
  exit 1
fi

# Script is in /boot/setup, switch to non-root pi-gen path per install script. Assuming default pi user.
pushd /home/pi/pi-gen

# setup environment variables to tweak config. SD card write script will prompt for WIFI creds.
cat > config <<EOL
export IMG_NAME=edge-raspbian
export RELEASE=buster
export DEPLOY_ZIP=1
export LOCALE_DEFAULT=en_US.UTF-8
export TARGET_HOSTNAME=edge-dev-pi
export KEYBOARD_KEYMAP=us
export KEYBOARD_LAYOUT="English (US)"
export TIMEZONE_DEFAULT=America/New_York
export FIRST_USER_NAME=iot
export FIRST_USER_PASS="${pi_pwd}"
export ENABLE_SSH=1
EOL

# Skip stages 3-5, only want Raspbian lite
touch ./stage3/SKIP ./stage4/SKIP ./stage5/SKIP
touch ./stage4/SKIP_IMAGES ./stage5/SKIP_IMAGES

pushd stage2

# don't need NOOBS
rm -f EXPORT_NOOBS || true

# ----- Begin Stage 02, Step 04 - IoT Edge Install Prereqs Step -----
step="04-edge-install-prereq"
if [ -d "$step" ]; then rm -Rf $step; fi
mkdir $step && pushd $step

cat > 00-run-chroot.sh <<RUN
#!/bin/bash
echo "Installing repository configuration"
curl https://packages.microsoft.com/config/debian/stretch/multiarch/prod.list > ./microsoft-prod.list
cp -v ./microsoft-prod.list /etc/apt/sources.list.d/
rm -v -f ./microsoft-prod.list

echo "Installing the Microsoft GPG public key"
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
cp -v ./microsoft.gpg /etc/apt/trusted.gpg.d/
rm -v -f microsoft.gpg

echo "Update package lists"
apt-get update
RUN

chmod +x 00-run-chroot.sh

cat > 01-packages <<RUN
moby-engine moby-cli libssl1.0.2
RUN

popd
# ----- End Stage 02, Step 04 - IoT Edge Install Prereqs Step -----

# ----- Begin Stage 02, Step 05 - IoT Edge Install Step -----
step="05-edge-install"
if [ -d "$step" ]; then rm -Rf $step; fi
mkdir $step && pushd $step

cat > 01-packages <<RUN
iotedge
RUN

popd
# ----- End Stage 02, Step 05 - IoT Edge Install Step -----

popd # stage 02

# run build
if [ "$clean" = true ] ; then
    echo "Running build with clean to rebuild last stage"
    CLEAN=1 ./build.sh
else
    echo "Running build"
    ./build.sh
fi

exitCode=$?

duration=$SECONDS
echo "Build process completed in $(($duration / 60)) minutes"

if [ $exitCode -ne 0 ]; then
    echo "Custom Raspbian lite build failed with exit code ${exitCode}" ; exit -1
fi

ls ./deploy

# On another machine, copy generated zip over:
# scp 'pi@raspberrypi.local:~/pi-gen/deploy/*zip' ~/temp
#
# Then run sd-card-write-mac.sh to write that image to SD card for PI use.
# Finally store / upload image to artifact repository (Nexus, Proget etc.)