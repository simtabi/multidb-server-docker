#!/usr/bin/env bash
# verify: every engine image and the cli image build for this architecture
# tags: build
# phase: 2

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need_docker

built=0
for engine in pg mysql mariadb cli; do
    dockerfile="$DBTK_ROOT/images/$engine/Dockerfile"
    if [[ ! -f "$dockerfile" ]]; then
        vfail "images/$engine/Dockerfile does not exist yet"
    fi

    img="$(image_name "$engine")"
    vinfo "building $img"
    if ! docker build -t "$img" "$DBTK_ROOT/images/$engine" >/tmp/dbtk-build-$engine.log 2>&1; then
        printf '      build failed; last 25 lines:\n' >&2
        tail -25 "/tmp/dbtk-build-$engine.log" >&2
        vfail "images/$engine failed to build"
    fi
    (( built++ )) || true
done

vinfo "$built image(s) built on $(uname -m)"
