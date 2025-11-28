# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file LICENSE.rst or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION ${CMAKE_VERSION}) # this file comes with cmake

# If CMAKE_DISABLE_SOURCE_CHANGES is set to true and the source directory is an
# existing directory in our source tree, calling file(MAKE_DIRECTORY) on it
# would cause a fatal error, even though it would be a no-op.
if(NOT EXISTS "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/abseil-cpp")
  file(MAKE_DIRECTORY "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/abseil-cpp")
endif()
file(MAKE_DIRECTORY
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/abseil-cpp-build"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/tmp"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/src/abseil-cpp-populate-stamp"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/src"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/src/abseil-cpp-populate-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/src/abseil-cpp-populate-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/src/abseil-cpp-populate-stamp${cfgdir}") # cfgdir has leading slash
endif()
