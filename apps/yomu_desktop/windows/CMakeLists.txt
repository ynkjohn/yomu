# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(yomu_desktop LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "yomu_desktop")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# --- Yomu: ship JRE 21 + PWA next to the executable (Release/install layout) ---
# Runtime: {exeDir}/jre/bin/java.exe  and  {exeDir}/pwa/index.html
# windows/ -> yomu_desktop/ -> apps/ -> monorepo root
set(YOMU_VENDOR_JRE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../packages/yomu_suwayomi/vendor/jre21")
set(YOMU_PWA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../apps/yomu_mobile_pwa")

if(EXISTS "${YOMU_VENDOR_JRE_DIR}/bin/java.exe")
  install(DIRECTORY "${YOMU_VENDOR_JRE_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/jre"
    COMPONENT Runtime
    USE_SOURCE_PERMISSIONS)
  message(STATUS "Yomu: bundling JRE from ${YOMU_VENDOR_JRE_DIR}")
else()
  # Debug may still run with monorepo vendor / YOMU_JAVA_HOME; Release must ship JRE.
  message(WARNING "Yomu: vendor JRE missing at ${YOMU_VENDOR_JRE_DIR}")
  if(CMAKE_BUILD_TYPE STREQUAL "Release" OR ("${CMAKE_CONFIGURATION_TYPES}" MATCHES "Release"))
    # Multi-config generators evaluate install at build time — gate Release install:
    install(CODE "
      if(NOT EXISTS \"${YOMU_VENDOR_JRE_DIR}/bin/java.exe\")
        if(\"\${CMAKE_INSTALL_CONFIG_NAME}\" STREQUAL \"Release\" OR \"\${CMAKE_INSTALL_CONFIG_NAME}\" STREQUAL \"Profile\")
          message(FATAL_ERROR \"Yomu Release/Profile requires packaged JRE at ${YOMU_VENDOR_JRE_DIR}/bin/java.exe — run tool/fetch_jre21_windows.ps1\")
        endif()
      endif()
      " COMPONENT Runtime)
  endif()
endif()

if(EXISTS "${YOMU_PWA_DIR}/index.html")
  install(DIRECTORY "${YOMU_PWA_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/pwa"
    COMPONENT Runtime
    FILES_MATCHING
      PATTERN "*.html"
      PATTERN "*.js"
      PATTERN "*.mjs"
      PATTERN "*.webmanifest"
      PATTERN "*.css"
      PATTERN "*.svg"
      PATTERN "*.png"
      PATTERN "*.ico"
      PATTERN "*.json"
      PATTERN "*.woff*"
      PATTERN "*.map"
    )
  message(STATUS "Yomu: bundling PWA from ${YOMU_PWA_DIR}")
else()
  message(WARNING "Yomu: PWA missing at ${YOMU_PWA_DIR}")
  install(CODE "
    if(NOT EXISTS \"${YOMU_PWA_DIR}/index.html\")
      if(\"\${CMAKE_INSTALL_CONFIG_NAME}\" STREQUAL \"Release\" OR \"\${CMAKE_INSTALL_CONFIG_NAME}\" STREQUAL \"Profile\")
        message(FATAL_ERROR \"Yomu Release requires PWA at ${YOMU_PWA_DIR}/index.html\")
      endif()
    endif()
    " COMPONENT Runtime)
endif()

