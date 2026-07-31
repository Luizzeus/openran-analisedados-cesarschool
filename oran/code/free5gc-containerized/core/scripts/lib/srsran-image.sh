# shellcheck shell=bash
# Helpers shared by the gNB_* compose wrappers.

ensure_srsran_image() {
  local target_image="${SRSRAN_IMAGE:-srsran-gnb:local}"
  local fallback_image="${SRSRAN_FALLBACK_IMAGE:-open5gs-srsran-cudu-zmq:latest}"
  local context_dir="${SRSRAN_BUILD_CONTEXT:-../core}"
  local dockerfile="${SRSRAN_BUILD_DOCKERFILE:-Dockerfile.srsRAN}"

  export SRSRAN_IMAGE="$target_image"

  if docker image inspect "$target_image" >/dev/null 2>&1; then
    echo "Imagem srsRAN pronta: ${target_image}"
    return 0
  fi

  if docker image inspect "$fallback_image" >/dev/null 2>&1; then
    echo "Reutilizando imagem srsRAN existente: ${fallback_image} -> ${target_image}"
    docker tag "$fallback_image" "$target_image"
    return 0
  fi

  echo "Imagem ${target_image} não encontrada; construindo com ${context_dir}/${dockerfile}..."
  docker build -t "$target_image" -f "${context_dir}/${dockerfile}" "$context_dir"
}
