# Graft C++ Example
# Demonstrates fetching and building multiple C++ libraries
#
# Libraries included:
# - Header-only: nlohmann/json, cpp-httplib, Aurora Units
# - Compiled: fmt, Catch2, yaml-cpp, SQLiteCpp
# - Tool: CMake (downloaded, used to build other libraries)
#
# Each dependency sets only its existence probe (NAME_TGT, relative to the install
# dir) and its source. DIR (defaults to $b/<name>-<version>), TAR, and the git
# clone scratch dir are filled in by graft, so there is no per-dependency
# boilerplate. Because DIR carries the version, bumping a NAME_COMMIT re-fetches
# into a fresh dir and rebuilds everything downstream.

b := bin
GRAFT_CACHE ?= .cache

MAKEFLAGS := -j 8

all: $b/test

# Bootstrap graft on first build (clone the pinned tag), then include it — nothing
# is vendored. Override to test against a local checkout: make GRAFT_URL=../.. GRAFT_VER=main
GRAFT_URL ?= https://github.com/DESX/graft.git
GRAFT_VER ?= v1.9.0
$(GRAFT_CACHE)/graft-$(GRAFT_VER)/graft.mk:; @git clone -q --depth=1 -b $(GRAFT_VER) $(GRAFT_URL) $(dir $@)
include $(GRAFT_CACHE)/graft-$(GRAFT_VER)/graft.mk

#-------------------------------------------------------------------------------
# CMAKE (latest sometimes required by other libs)
#-------------------------------------------------------------------------------
CMAKE_TGT     := bin/cmake
CMAKE_TAR_URL := https://github.com/Kitware/CMake/releases/download/v4.2.1/cmake-4.2.1-linux-x86_64.tar.gz
$(eval $(call GRAFT_FETCH,CMAKE))

CMAKE := $(CMAKE_TGT)
cmake: $(CMAKE_TGT)

#-------------------------------------------------------------------------------
# Aurora Units
#-------------------------------------------------------------------------------
AU_TGT        := README.md
AU_COMMIT     := 0.5.0
AU_GIT_URL    := https://github.com/aurora-opensource/au.git
AU_PRE_UNPACK  = $(CMAKE) -Wno-dev -S $(AU_TMP) -B $(AU_TMP)/build && $(CMAKE) --build $(AU_TMP)/build -j 8 --target au
AU_EXTRA      := $(CMAKE)
$(eval $(call GRAFT_FETCH,AU))

au: $(AU_TGT)
AU_INC := -I$(AU_DIR)

#-------------------------------------------------------------------------------
# nlohmann/json (header-only)
#-------------------------------------------------------------------------------
JSON_TGT     := README.md
JSON_COMMIT  := v3.11.3
JSON_GIT_URL := https://github.com/nlohmann/json.git
$(eval $(call GRAFT_FETCH,JSON))

JSON_INC := -I$(JSON_DIR)/single_include

#-------------------------------------------------------------------------------
# fmt
#-------------------------------------------------------------------------------
FMT_TGT        := README.md
FMT_COMMIT     := 12.1.0
FMT_GIT_URL    := https://github.com/fmtlib/fmt.git
FMT_PRE_UNPACK  = $(CMAKE) -S $(FMT_TMP) -B $(FMT_TMP)/build && $(CMAKE) --build $(FMT_TMP)/build -j 8 --target fmt
FMT_EXTRA      := $(CMAKE)
$(eval $(call GRAFT_FETCH,FMT))

FMT_LIB := $(FMT_DIR)/build/libfmt.a
FMT_INC := -I$(FMT_DIR)/include
$(FMT_LIB): $(FMT_TGT)

#-------------------------------------------------------------------------------
# Catch2
#-------------------------------------------------------------------------------
CATCH2_TGT        := README.md
CATCH2_COMMIT     := v3.11.0
CATCH2_GIT_URL    := https://github.com/catchorg/Catch2.git
CATCH2_PRE_UNPACK  = $(CMAKE) -S $(CATCH2_TMP) -B $(CATCH2_TMP)/build && $(CMAKE) --build $(CATCH2_TMP)/build -j 8 --target Catch2WithMain
CATCH2_EXTRA      := $(CMAKE)
$(eval $(call GRAFT_FETCH,CATCH2))

CATCH2_LIB := $(CATCH2_DIR)/build/src/libCatch2Main.a $(CATCH2_DIR)/build/src/libCatch2.a
CATCH2_INC := -I$(CATCH2_DIR)/src -I$(CATCH2_DIR)/build/generated-includes
$(CATCH2_LIB): $(CATCH2_TGT)

#-------------------------------------------------------------------------------
# yaml-cpp
#-------------------------------------------------------------------------------
YAMLCPP_TGT        := README.md
YAMLCPP_COMMIT     := 0.8.0
YAMLCPP_GIT_URL    := https://github.com/jbeder/yaml-cpp.git
YAMLCPP_PRE_UNPACK  = $(CMAKE) -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -S $(YAMLCPP_TMP) -B $(YAMLCPP_TMP)/build && $(CMAKE) --build $(YAMLCPP_TMP)/build -j 8
YAMLCPP_EXTRA      := $(CMAKE)
$(eval $(call GRAFT_FETCH,YAMLCPP))

YAMLCPP_LIB := $(YAMLCPP_DIR)/build/libyaml-cpp.a
YAMLCPP_INC := -I$(YAMLCPP_DIR)/include
$(YAMLCPP_LIB): $(YAMLCPP_TGT)

#-------------------------------------------------------------------------------
# SQLiteCpp (bundles SQLite)
#-------------------------------------------------------------------------------
SQLITECPP_TGT        := README.md
SQLITECPP_COMMIT     := 3.3.2
SQLITECPP_GIT_URL    := https://github.com/SRombauts/SQLiteCpp.git
SQLITECPP_PRE_UNPACK  = $(CMAKE) -S $(SQLITECPP_TMP) -B $(SQLITECPP_TMP)/build -DSQLITECPP_INTERNAL_SQLITE=ON && $(CMAKE) --build $(SQLITECPP_TMP)/build -j 8
SQLITECPP_EXTRA      := $(CMAKE)
$(eval $(call GRAFT_FETCH,SQLITECPP))

SQLITECPP_LIB := $(SQLITECPP_DIR)/build/libSQLiteCpp.a $(SQLITECPP_DIR)/build/sqlite3/libsqlite3.a
SQLITECPP_INC := -I$(SQLITECPP_DIR)/include
$(SQLITECPP_LIB): $(SQLITECPP_TGT)

#-------------------------------------------------------------------------------
# cpp-httplib (header-only, with SSL)
#-------------------------------------------------------------------------------
HTTPLIB_TGT     := README.md
HTTPLIB_COMMIT  := v0.18.1
HTTPLIB_GIT_URL := https://github.com/yhirose/cpp-httplib.git
$(eval $(call GRAFT_FETCH,HTTPLIB))

HTTPLIB_INC := -I$(HTTPLIB_DIR) -DCPPHTTPLIB_OPENSSL_SUPPORT

#-------------------------------------------------------------------------------
# Test app
#-------------------------------------------------------------------------------
LIBS := $(FMT_LIB) $(CATCH2_LIB) $(YAMLCPP_LIB) $(SQLITECPP_LIB)
INCS := $(CATCH2_INC) $(FMT_INC) $(AU_INC) $(JSON_INC) $(YAMLCPP_INC) $(SQLITECPP_INC) $(HTTPLIB_INC)
HEADER_DEPS := $(AU_TGT) $(JSON_TGT) $(HTTPLIB_TGT)

$b/test: main.cpp $(LIBS) | $b $(HEADER_DEPS)
	g++ -std=c++17 -o $@ $^ $(INCS) -pthread -ldl -lssl -lcrypto

go: $b/test
	$b/test

watch:
	echo main.cpp | tr ' ' '\n' | entr make go

clean:
	rm -rf $b

clean-all:
	rm -rf $b $(GRAFT_CACHE)

DIRS := $b $(GRAFT_CACHE) $(CMAKE_DIR) $(AU_DIR) $(JSON_DIR) $(FMT_DIR) \
        $(CATCH2_DIR) $(YAMLCPP_DIR) $(SQLITECPP_DIR) $(HTTPLIB_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))
