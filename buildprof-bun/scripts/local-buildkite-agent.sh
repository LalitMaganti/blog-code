#!/usr/bin/env bash
set -euo pipefail

: "${BUILDPROF_ARTIFACT_ROOT:?BUILDPROF_ARTIFACT_ROOT must be set}"
: "${BUILDKITE_STEP_KEY:?BUILDKITE_STEP_KEY must be set}"

if [[ $# -lt 3 ]]; then
  echo "unsupported buildkite-agent invocation: $*" >&2
  exit 2
fi

command=$1
subcommand=$2

if [[ $command == meta-data && $subcommand == set ]]; then
  metadata_dir="$BUILDPROF_ARTIFACT_ROOT/.metadata"
  mkdir -p "$metadata_dir"
  key=$3
  value=${4-}
  printf '%s\n' "$value" >"$metadata_dir/$key"
  exit 0
fi

if [[ $command != artifact ]]; then
  echo "unsupported buildkite-agent invocation: $*" >&2
  exit 2
fi

case "$subcommand" in
  upload)
    IFS=';' read -r -a paths <<<"$3"
    step_dir="$BUILDPROF_ARTIFACT_ROOT/$BUILDKITE_STEP_KEY"
    mkdir -p "$step_dir"
    for path in "${paths[@]}"; do
      if [[ ! -e $path ]]; then
        echo "artifact does not exist: $path" >&2
        exit 1
      fi
      mkdir -p "$step_dir/$(dirname "$path")"
      cp --archive --reflink=auto "$path" "$step_dir/$path"
    done
    ;;
  download)
    destination=$4
    shift 4
    source_step=
    while (($#)); do
      case "$1" in
        --step)
          source_step=$2
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ -z $source_step ]]; then
      echo "artifact download requires --step" >&2
      exit 2
    fi
    source_dir="$BUILDPROF_ARTIFACT_ROOT/$source_step"
    if [[ ! -d $source_dir ]]; then
      echo "artifact step does not exist: $source_step" >&2
      exit 1
    fi
    mkdir -p "$destination"
    cp --archive --reflink=auto "$source_dir/." "$destination/"
    ;;
  *)
    echo "unsupported artifact command: $2" >&2
    exit 2
    ;;
esac
