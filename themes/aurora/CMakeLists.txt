cmake_minimum_required(VERSION 3.10)
project(e87n_theme_aurora C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -Wall")

# LVGL 源码目录（默认用仓库里内置的那份）
if(NOT LVGL_DIR)
    set(LVGL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../package/e87n-display/src/lib/lvgl")
endif()
if(NOT EXISTS "${LVGL_DIR}/lvgl.h")
    message(FATAL_ERROR "LVGL_DIR not found: ${LVGL_DIR}")
endif()

# 只要库，不要 demo/example
set(CONFIG_LV_BUILD_DEMOS OFF CACHE BOOL "" FORCE)
set(CONFIG_LV_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(CONFIG_LV_USE_THORVG_INTERNAL OFF CACHE BOOL "" FORCE)
set(CONFIG_LV_USE_THORVG_EXTERNAL OFF CACHE BOOL "" FORCE)

add_subdirectory(${LVGL_DIR} lvgl)

# 用本目录的 lv_conf.h（16bit / fbdev / Montserrat / CJK 字体）
target_include_directories(lvgl PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(lvgl PUBLIC LV_CONF_INCLUDE_SIMPLE)

add_executable(app
    main.c
    e87n_metrics.c
)
target_include_directories(app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(app PRIVATE lvgl m pthread)
