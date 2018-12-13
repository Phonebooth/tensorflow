#!/bin/bash

set -ex

export OS=$(uname)
if [ "${OS}" = "Linux" ]; then
    export DS_ROOT_TASK=$(/usr/bin/realpath "${HOME}")

    BAZEL_URL=https://github.com/bazelbuild/bazel/releases/download/0.15.2/bazel-0.15.2-installer-linux-x86_64.sh
    BAZEL_SHA256=13eae0f09565cf17fc1c9ce1053b9eac14c11e726a2215a79ebaf5bdbf435241

    CUDA_URL=https://developer.nvidia.com/compute/cuda/9.0/Prod/local_installers/cuda_9.0.176_384.81_linux-run
    CUDA_SHA256=96863423feaa50b5c1c5e1b9ec537ef7ba77576a3986652351ae43e66bcd080c

    # From https://gitlab.com/nvidia/cuda/blob/centos7/9.0/devel/cudnn7/Dockerfile
    CUDNN_URL=http://developer.download.nvidia.com/compute/redist/cudnn/v7.2.1/cudnn-9.0-linux-x64-v7.2.1.38.tgz
    CUDNN_SHA256=cf007437b9ac6250ec63b89c25f248d2597fdd01369c80146567f78e75ce4e37

    NCCL_URL=https://s3.amazonaws.com/pytorch/nccl_2.2.13-1%2Bcuda9.0_x86_64.txz
    NCCL_SHA256=5ae976f47f9dd1caf4f5fa0da51be9ecbdeed54065d1b654ce308cc803e0af0d

    ANDROID_NDK_URL=https://dl.google.com/android/repository/android-ndk-r18b-linux-x86_64.zip
    ANDROID_NDK_SHA256=4f61cbe4bbf6406aa5ef2ae871def78010eed6271af72de83f8bd0b07a9fd3fd

    ANDROID_SDK_URL=https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip
    ANDROID_SDK_SHA256=92ffee5a1d98d856634e8b71132e8a95d96c83a63fde1099be3d86df3106def9

elif [ "${OS}" = "Darwin" ]; then
    if [ -z "${TASKCLUSTER_TASK_DIR}" -o -z "${TASKCLUSTER_ARTIFACTS}" ]; then
        echo "Inconsistent OSX setup: missing some vars."
        echo "TASKCLUSTER_TASK_DIR=${TASKCLUSTER_TASK_DIR}"
        echo "TASKCLUSTER_ARTIFACTS=${TASKCLUSTER_ARTIFACTS}"
        exit 1
    fi;

    export DS_ROOT_TASK=${TASKCLUSTER_TASK_DIR}

    BAZEL_URL=https://github.com/bazelbuild/bazel/releases/download/0.15.2/bazel-0.15.2-installer-darwin-x86_64.sh
    BAZEL_SHA256=84ee271274e7c8904a48f7894fe0569174d162c7428a19dda57fc6a6c95c628b
fi;

# /tmp/artifacts for docker-worker on linux,
# and task subdir for generic-worker on osx
export TASKCLUSTER_ARTIFACTS=${TASKCLUSTER_ARTIFACTS:-/tmp/artifacts}

### Define variables that needs to be exported to other processes

PATH=${DS_ROOT_TASK}/bin:$PATH
if [ "${OS}" = "Darwin" ]; then
    PATH=${DS_ROOT_TASK}/homebrew/bin/:${DS_ROOT_TASK}/homebrew/opt/node@8/bin:$PATH
fi;
export PATH

if [ "${OS}" = "Linux" ]; then
    export LD_LIBRARY_PATH=${DS_ROOT_TASK}/DeepSpeech/CUDA/lib64/:${DS_ROOT_TASK}/DeepSpeech/CUDA/lib64/stubs/:$LD_LIBRARY_PATH
    export ANDROID_SDK_HOME=${DS_ROOT_TASK}/DeepSpeech/Android/SDK/
    export ANDROID_NDK_HOME=${DS_ROOT_TASK}/DeepSpeech/Android/android-ndk-r18b/
fi;

export TF_ENABLE_XLA=0
if [ "${OS}" = "Linux" ]; then
    TF_NEED_JEMALLOC=1
elif [ "${OS}" = "Darwin" ]; then
    TF_NEED_JEMALLOC=0
fi;
export TF_NEED_JEMALLOC
export TF_NEED_OPENCL_SYCL=0
export TF_NEED_MKL=0
export TF_NEED_VERBS=0
export TF_NEED_MPI=0
export TF_NEED_IGNITE=0
export TF_NEED_GDR=0
export TF_NEED_NGRAPH=0
export TF_DOWNLOAD_CLANG=0
export TF_SET_ANDROID_WORKSPACE=0
export TF_NEED_TENSORRT=0
export GCC_HOST_COMPILER_PATH=/usr/bin/gcc
export PYTHON_BIN_PATH=/usr/bin/python2.7

## Below, define or export some build variables

# Enable some SIMD support. Limit ourselves to what Tensorflow needs.
# Also ensure to not require too recent CPU: AVX2/FMA introduced by:
#  - Intel with Haswell (2013)
#  - AMD with Excavator (2015)
# For better compatibility, AVX ony might be better.
#
# Build for generic amd64 platforms, no device-specific optimization
# See https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html for targetting specific CPUs
CC_OPT_FLAGS="-mtune=generic -march=x86-64 -msse -msse2 -msse3 -msse4.1 -msse4.2 -mavx"
BAZEL_OPT_FLAGS=""
for flag in ${CC_OPT_FLAGS};
do
    BAZEL_OPT_FLAGS="${BAZEL_OPT_FLAGS} --copt=${flag}"
done;

export CC_OPT_FLAGS

if [ "${OS}" = "Darwin" ]; then
    BAZEL_OUTPUT_CACHE_DIR="${DS_ROOT_TASK}/.bazel_cache/"
    BAZEL_OUTPUT_CACHE_INSTANCE="${BAZEL_OUTPUT_CACHE_DIR}/output/"
    mkdir -p ${BAZEL_OUTPUT_CACHE_INSTANCE} || true

    # We need both to ensure stable path ; default value for output_base is some
    # MD5 value.
    BAZEL_OUTPUT_USER_ROOT="--output_user_root ${BAZEL_OUTPUT_CACHE_DIR} --output_base ${BAZEL_OUTPUT_CACHE_INSTANCE}"
    export BAZEL_OUTPUT_USER_ROOT
fi;

### Define build parameters/env variables that we will re-ues in sourcing scripts.
TF_CUDA_FLAGS="TF_CUDA_CLANG=0 TF_CUDA_VERSION=9.0 TF_CUDNN_VERSION=7 CUDA_TOOLKIT_PATH=${DS_ROOT_TASK}/DeepSpeech/CUDA CUDNN_INSTALL_PATH=${DS_ROOT_TASK}/DeepSpeech/CUDA TF_NCCL_VERSION=2.2 NCCL_INSTALL_PATH=${DS_ROOT_TASK}/DeepSpeech/CUDA TF_CUDA_COMPUTE_CAPABILITIES=\"3.0,3.5,3.7,5.2,6.0,6.1\""
BAZEL_ARM_FLAGS="--config=rpi3 --config=rpi3_opt"
BAZEL_ARM64_FLAGS="--config=rpi3-armv8 --config=rpi3-armv8_opt"
BAZEL_ANDROID_ARM_FLAGS="--config=android --config=android_arm --action_env ANDROID_NDK_API_LEVEL=21 --cxxopt=-std=c++11 --copt=-D_GLIBCXX_USE_C99"
BAZEL_ANDROID_ARM64_FLAGS="--config=android --config=android_arm64 --action_env ANDROID_NDK_API_LEVEL=21 --cxxopt=-std=c++11 --copt=-D_GLIBCXX_USE_C99"
BAZEL_CUDA_FLAGS="--config=cuda"
BAZEL_EXTRA_FLAGS="--copt=-fvisibility=hidden"

### Define build targets that we will re-ues in sourcing scripts.
BUILD_TARGET_LIB_CPP_API="//tensorflow:libtensorflow_cc.so"
BUILD_TARGET_GRAPH_TRANSFORMS="//tensorflow/tools/graph_transforms:transform_graph"
BUILD_TARGET_GRAPH_SUMMARIZE="//tensorflow/tools/graph_transforms:summarize_graph"
BUILD_TARGET_GRAPH_BENCHMARK="//tensorflow/tools/benchmark:benchmark_model"
BUILD_TARGET_CONVERT_MMAP="//tensorflow/contrib/util:convert_graphdef_memmapped_format"
BUILD_TARGET_TOCO="//tensorflow/contrib/lite/toco:toco"
BUILD_TARGET_LITE_BENCHMARK="//tensorflow/contrib/lite/tools/benchmark:benchmark_model"
BUILD_TARGET_LITE_LIB="//tensorflow/contrib/lite/experimental/c:libtensorflowlite_c.so"
