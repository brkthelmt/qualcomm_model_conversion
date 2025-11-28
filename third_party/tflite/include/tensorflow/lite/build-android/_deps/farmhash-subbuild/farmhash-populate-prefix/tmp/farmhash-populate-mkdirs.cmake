# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file LICENSE.rst or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION ${CMAKE_VERSION}) # this file comes with cmake

# If CMAKE_DISABLE_SOURCE_CHANGES is set to true and the source directory is an
# existing directory in our source tree, calling file(MAKE_DIRECTORY) on it
# would cause a fatal error, even though it would be a no-op.
if(NOT EXISTS "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/farmhash")
  file(MAKE_DIRECTORY "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/farmhash")
endif()
file(MAKE_DIRECTORY
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/farmhash-build"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/farmhash-subbuild/farmhash-populate-prefix"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/farmhash-subbuild/farmhash-populate-prefix/tmp"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/farmhash-subbuild/farmhash-populate-prefix/src/farmhash-populate-stamp"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/farmhash-subbuild/farmhash-populate-prefix/src"
  "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/farmhash-subbuild/farmhash-populate-prefix/src/farmhash-populate-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/farmhash-subbuild/farmhash-populate-prefix/src/farmhash-populate-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "/Users/fzoneandonly/Desktop/Code/tensorflow/tensorflow/lite/build-android/_deps/farmhash-subbuild/farmhash-populate-prefix/src/farmhash-populate-stamp${cfgdir}") # cfgdir has leading slash
endif()
