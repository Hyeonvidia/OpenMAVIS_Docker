# =============================================================================
# openmavis  —  upstream OpenMAVIS built unmodified on the latest Ubuntu LTS
#
#   base  ->  pangolin  ->  openmavis (final)
#
# The OpenMAVIS source is cloned from GitHub at a pinned commit and built with
# its own bundled (modified) DBoW2 / g2o / Sophus, exactly as upstream build.sh
# does.  Nothing in the upstream tree is edited: every adaptation to the newer
# toolchain is a CMake cache/flag override passed on the command line, and is
# listed below where it is made.
#
# Layer structure follows ORB_SLAM3_Remastered/docker (base / thirdparty / dev).
# =============================================================================
ARG UBUNTU_VERSION=26.04

# -----------------------------------------------------------------------------
# base: OS + toolchain + system libraries (apt only)
# -----------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Seoul

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        pkg-config \
        git \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# OpenMAVIS needs: OpenCV >= 4.4, Eigen >= 3.1, boost_serialization, libcrypto.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libeigen3-dev \
        libopencv-dev \
        libboost-serialization-dev \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Pangolin build deps (GL + X11/EGL/Wayland windowing), plus Xvfb so the
# viewer, which multi_inertial_euroc always opens, has a display to draw on.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libegl1-mesa-dev \
        libglew-dev \
        libepoxy-dev \
        libwayland-dev \
        libxkbcommon-dev \
        wayland-protocols \
        libx11-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxcursor-dev \
        libxi-dev \
        libxext-dev \
        libjpeg-dev \
        libpng-dev \
        xvfb \
        x11-utils \
        mesa-utils \
    && rm -rf /var/lib/apt/lists/*

# Dataset conversion (rosbags) and trajectory evaluation (evo).  numpy/OpenCV
# come from apt; the pure-Python packages go into a venv that can see them.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
        python3-numpy \
        python3-opencv \
        python3-yaml \
        python3-scipy \
        python3-matplotlib \
    && rm -rf /var/lib/apt/lists/*

ARG ROSBAGS_VERSION=0.11.8
ARG EVO_VERSION=1.38.0
RUN python3 -m venv --system-site-packages /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir \
        "rosbags==${ROSBAGS_VERSION}" \
        "evo==${EVO_VERSION}"
ENV PATH=/opt/venv/bin:${PATH}

# -----------------------------------------------------------------------------
# pangolin: latest release tag, installed to /usr/local
# -----------------------------------------------------------------------------
FROM base AS pangolin

ARG PANGOLIN_TAG=v0.9.6
ARG JOBS=8
# Camera/vendor video backends and ffmpeg are off: dataset replay reads PNGs
# through OpenCV, and the vendor SDKs do not exist for linux/arm64.
RUN git clone --depth 1 --branch ${PANGOLIN_TAG} \
        https://github.com/stevenlovegrove/Pangolin.git /src/Pangolin \
    && cmake -S /src/Pangolin -B /build/Pangolin -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TOOLS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTS=OFF \
        -DBUILD_PANGOLIN_PYTHON=OFF \
        -DBUILD_PANGOLIN_FFMPEG=OFF \
        -DBUILD_PANGOLIN_REALSENSE=OFF \
        -DBUILD_PANGOLIN_REALSENSE2=OFF \
        -DBUILD_PANGOLIN_OPENNI=OFF \
        -DBUILD_PANGOLIN_OPENNI2=OFF \
        -DBUILD_PANGOLIN_LIBDC1394=OFF \
        -DBUILD_PANGOLIN_TELICAM=OFF \
        -DBUILD_PANGOLIN_PLEORA=OFF \
        -DBUILD_PANGOLIN_DEPTHSENSE=OFF \
        -DBUILD_PANGOLIN_LIBUVC=OFF \
    && cmake --build /build/Pangolin -j ${JOBS} \
    && cmake --install /build/Pangolin \
    && ldconfig \
    && rm -rf /build/Pangolin /src/Pangolin

# -----------------------------------------------------------------------------
# openmavis: pinned upstream commit, built the way build.sh builds it
# -----------------------------------------------------------------------------
FROM pangolin AS openmavis

ARG OPENMAVIS_REPO=https://github.com/MAVIS-SLAM/OpenMAVIS.git
ARG OPENMAVIS_COMMIT=b13b1c20e84efa4bb63564e26308541af70d03f2
ARG JOBS=8

RUN git clone ${OPENMAVIS_REPO} /opt/OpenMAVIS \
    && git -C /opt/OpenMAVIS checkout --detach ${OPENMAVIS_COMMIT} \
    && git -C /opt/OpenMAVIS rev-parse HEAD > /opt/OpenMAVIS.commit

WORKDIR /opt/OpenMAVIS

# Toolchain overrides (command-line only, no source edits):
#  * CMAKE_POLICY_VERSION_MINIMUM=3.5 — CMake 4 refuses cmake_minimum_required
#    below 3.5; upstream declares 2.8.
#  * -std=gnu++14 in CMAKE_CXX_FLAGS_RELEASE — upstream hard-codes -std=c++11
#    into CMAKE_CXX_FLAGS; the release flags are emitted after it, so the
#    later -std wins.  C++14 is the newest standard the upstream code accepts
#    (LoopClosing.cc increments `bool mnFullBAIdx`, which C++17 removed), and
#    Pangolin 0.9.6's public headers compile under it.  GNU mode keeps
#    libstdc++'s allocator value_type static_assert off, which ORB-SLAM3's
#    KeyFrameAndPose map would trip under strict -std=c++NN.
#    -O3 -DNDEBUG is the CMake default being replaced, kept identical.
ARG CXX_STD_FLAGS="-O3 -DNDEBUG -std=gnu++14"
ARG CMAKE_COMPAT="-DCMAKE_POLICY_VERSION_MINIMUM=3.5"

# Thirdparty/DBoW2 and Thirdparty/g2o (the bundled ORB-SLAM3 forks).
# Sophus is header-only for OpenMAVIS; build.sh only builds its tests, which
# carry -Werror and are not needed, so that step is skipped.
RUN cmake -S Thirdparty/DBoW2 -B Thirdparty/DBoW2/build ${CMAKE_COMPAT} \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build Thirdparty/DBoW2/build -j ${JOBS}

RUN cmake -S Thirdparty/g2o -B Thirdparty/g2o/build ${CMAKE_COMPAT} \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build Thirdparty/g2o/build -j ${JOBS}

RUN tar -xf Vocabulary/ORBvoc.txt.tar.gz -C Vocabulary

RUN cmake -S . -B build ${CMAKE_COMPAT} \
        -DCMAKE_BUILD_TYPE=Release \
        "-DCMAKE_CXX_FLAGS_RELEASE=${CXX_STD_FLAGS}" \
    && cmake --build build -j ${JOBS}

ENV LD_LIBRARY_PATH=/opt/OpenMAVIS/lib:/opt/OpenMAVIS/Thirdparty/DBoW2/lib:/opt/OpenMAVIS/Thirdparty/g2o/lib
RUN if ldd Examples/Multi-Inertial/multi_inertial_euroc | grep 'not found'; then exit 1; fi

# Watching the viewer from macOS (docker/run_gui.sh), as in
# ORB_SLAM3_Remastered/docs/VIEWER.md:
#  * Xephyr — nested X server.  Mesa cannot present straight to XQuartz (no
#    MIT-SHM across the VM boundary, one "Failed to attach to x11 shm" per
#    frame, window stays blank); it presents to Xephyr locally, and Xephyr
#    repaints its window on XQuartz with plain XPutImage.
#  * x11vnc — exports the Xvfb screen to macOS Screen Sharing instead.
#  * xdotool — no window manager runs, so it places and focuses the windows.
#  * x11-apps / imagemagick — xwd screenshots for checking what is on screen.
RUN apt-get update && apt-get install -y --no-install-recommends \
        xserver-xephyr \
        x11vnc \
        xdotool \
        x11-apps \
        imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Pangolin picked Wayland as its default window backend (libwayland-dev is
# present); the container has an X server (Xvfb or XQuartz), not a compositor.
ENV PANGOLIN_WINDOW_URI=x11://
ENV XVFB_RESOLUTION=1600x1200x24
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
