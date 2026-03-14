FROM automaticrippingmachine/automatic-ripping-machine:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV NEEDRESTART_MODE=a

# Update all packages first
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get dist-upgrade -y

# Upgrade to Ubuntu 24.04
RUN apt-get install -y ubuntu-release-upgrader-core && \
    sed -i 's/Prompt=lts/Prompt=normal/' /etc/update-manager/release-upgrades && \
    echo 'DPkg::options { "--force-confdef"; "--force-confold"; }' >> /etc/apt/apt.conf.d/local && \
    do-release-upgrade -f DistUpgradeViewNonInteractive

# Restore custom udev that gets deleted during Ubuntu upgrade
RUN cp /opt/arm/scripts/docker/custom_udev /etc/init.d/udev && \
    chmod +x /etc/init.d/udev

# Install MakeMKV from source since the latest version in Ubuntu 24.04 is too old
RUN cd /tmp && \
    wget https://www.makemkv.com/download/makemkv-bin-1.18.3.tar.gz && \
    wget https://www.makemkv.com/download/makemkv-oss-1.18.3.tar.gz && \
    tar xzf makemkv-bin-1.18.3.tar.gz && \
    tar xzf makemkv-oss-1.18.3.tar.gz && \
    apt-get update && \
    apt-get install -y build-essential pkg-config libc6-dev libssl-dev libexpat1-dev libavcodec-dev libgl1-mesa-dev qtbase5-dev zlib1g-dev && \
    cd makemkv-oss-1.18.3 && ./configure && make && make install && \
    cd ../makemkv-bin-1.18.3 && mkdir -p tmp && touch tmp/eula_accepted && make && make install && \
    mv /usr/local/bin/makemkvcon /usr/local/bin/makemkvcon.old && \
    mv /usr/local/lib/libmakemkv.so.1 /usr/local/lib/libmakemkv.so.1.old && \
    mv /usr/local/lib/libdriveio.so.0 /usr/local/lib/libdriveio.so.0.old

# Reinstall ARM Python dependencies
RUN pip3 install --break-system-packages --ignore-installed \
    bcrypt requests argparse colorama flake8 waitress \
    flask flask-cors flask-login flask-migrate flask-sqlalchemy flask-wtf \
    apprise alembic sqlalchemy psutil pydvdid python-magic pyudev pyyaml \
    xmltodict eyed3 musicbrainzngs discid prettytable werkzeug wtforms \
    netifaces

# Install Intel drivers, MFX libraries, HandBrake, and dependencies
RUN apt-get update && \
    apt-get install -y \
    intel-media-va-driver-non-free \
    libmfx1 libmfx-dev \
    handbrake-cli \
    libvpx9 libmp3lame0 libopus0 libnuma1 \
    && cd /tmp && \
    wget http://archive.ubuntu.com/ubuntu/pool/universe/x/x264/libx264-163_0.163.3060+git5db6aa6-2build1_amd64.deb && \
    dpkg -i libx264-163_0.163.3060+git5db6aa6-2build1_amd64.deb && \
    rm -rf /var/lib/apt/lists/* && \
    mv /usr/local/bin/HandBrakeCLI /usr/local/bin/HandBrakeCLI.old && \
    ln -s /usr/bin/HandBrakeCLI /usr/local/bin/HandBrakeCLI

ENV LIBVA_DRIVER_NAME=iHD
ENV LIBVA_DRI_DEVICE=/dev/dri/renderD129
EXPOSE 8080
CMD ["/sbin/my_init"]
WORKDIR /home/arm
