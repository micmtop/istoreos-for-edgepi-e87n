cmake_minimum_required(VERSION 3.10)
project(e87n-display)

# Set policy to allow to run the target_link_libraries cmd on targets that are
# build in another directory.
cmake_policy(SET CMP0079 NEW)

set(CMAKE_C_STANDARD 99) # LVGL officially supports C99 and above
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(EXECUTABLE_OUTPUT_PATH ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall")

set(LIBDIR lib)
set(PRJ_MAIN "e87n-display" CACHE STRING "Name of the main executable target")

# ---- LVGL build options (keep minimal; no demos/examples/thorvg/python)
set(LV_BUILD_SET_CONFIG_OPTS OFF CACHE BOOL "create CMAKE variables from lv_conf_internal.h" FORCE)
set(CONFIG_LV_BUILD_DEMOS OFF CACHE BOOL "Build demos" FORCE)
set(CONFIG_LV_BUILD_EXAMPLES OFF CACHE BOOL "Build examples" FORCE)
set(CONFIG_LV_USE_THORVG_INTERNAL OFF CACHE BOOL "Use the internal version of ThorVG" FORCE)
set(CONFIG_LV_USE_THORVG_EXTERNAL OFF CACHE BOOL "Use ThorVG as an external library" FORCE)

add_subdirectory(${LIBDIR}/lvgl)
add_subdirectory(${LIBDIR}/ui)

# LVGL needs libm + pthread
target_link_libraries(lvgl PUBLIC m pthread)

# 收集数据模块源文件
file(GLOB DATA_SOURCES ${PROJECT_SOURCE_DIR}/data/*.c)
file(GLOB UI_SOURCES ${PROJECT_SOURCE_DIR}/ui/*.c)
file(GLOB UTILS_SOURCES ${PROJECT_SOURCE_DIR}/utils/*.c)

# 创建工具库
add_library(utils STATIC ${UTILS_SOURCES})
target_include_directories(utils PUBLIC
    ${PROJECT_SOURCE_DIR}
)

# 创建数据模块库
add_library(data_manager STATIC ${DATA_SOURCES})
target_include_directories(data_manager PUBLIC
    ${PROJECT_SOURCE_DIR}
    ${PROJECT_SOURCE_DIR}/lib
)
target_link_libraries(data_manager PUBLIC lvgl utils)

# 创建 UI 刷新器库
add_library(ui_refresher STATIC ${UI_SOURCES})
target_include_directories(ui_refresher PUBLIC
    ${PROJECT_SOURCE_DIR}
    ${PROJECT_SOURCE_DIR}/lib
)
target_link_libraries(ui_refresher PUBLIC lvgl data_manager)

add_executable(${PRJ_MAIN}
    ${PROJECT_SOURCE_DIR}/main.c
)
target_include_directories(${PRJ_MAIN} PRIVATE
    ${PROJECT_SOURCE_DIR}
    ${PROJECT_SOURCE_DIR}/lib
)
target_link_libraries(${PRJ_MAIN}
                              lvgl
                              ui
                              data_manager
                              ui_refresher
                              utils
                              m
                              pthread)

install(TARGETS ${PRJ_MAIN} RUNTIME DESTINATION bin)