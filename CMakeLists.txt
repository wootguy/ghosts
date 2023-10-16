cmake_minimum_required(VERSION 3.6)

project(Ghosts)

set(SOURCE_FILES
	src/main.h src/main.cpp
	src/GhostCam.h src/GhostCam.cpp
	src/ghost_utils.h src/ghost_utils.cpp
)

add_library(${PROJECT_NAME} SHARED)
add_subdirectory(mmlib)
mmlib_default_setup()
