--[[
Copyright (C) 2025 NoneBot

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, see <https://www.gnu.org/licenses/>.
]]
add_rules("mode.debug", "mode.release", "mode.releasedbg")

set_license("LGPL-3.0-or-later")

add_repositories("my-repo repo")

add_requires("libintl", {configs = {shared = false}})
add_requires("litehtml", {configs = {utf8 = true}})
add_requires("pango", {configs = {shared = false}})
add_requires("libjpeg-turbo", "libwebp", "giflib", "aklomp-base64", "fmt")
-- 显式声明 zlib 静态链接，防止 manylinux wheel 中符号被链接器优化掉
add_requires("zlib", {configs = {shared = false}})
set_languages("c++17")
add_requires("libavif", {configs = { aom = true }})
add_requires("cairo", {configs = { xlib = false }})
add_requireconfs("**.cairo", { override = true, configs = { xlib = false } })
-- 锁定 fribidi 版本，避免 v1.0.16 的构建问题
add_requireconfs("fribidi", { override = true, version = "v1.0.15" })
add_requires("python", { system = true, version = ">=3.10", configs = { headeronly = not is_plat("windows"), shared = true } })
add_requireconfs("**.python", { override = true, configs = { headeronly = true, shared = true } })
add_requireconfs("**|python|cmake|ninja|meson", { override = true, system = false, configs = { shared = false } })


function require_htmlkit()
    if is_plat("linux") then
        if is_arch("x86_64") then
            add_linkorders("pangocairo-1.0", "pango-1.0")
            add_linkorders("pangoft2-1.0", "pango-1.0")
        else
            add_linkorders("pangocairo-1.0", "pangoft2-1.0", "pango-1.0")
        end
    end
    add_packages("litehtml", "cairo", "pango", "libjpeg-turbo", "libwebp", "libavif", "giflib", "aklomp-base64", "fmt")
    -- 显式添加 zlib 包，防止链接器因 --as-needed / gc-sections 将其优化掉
    add_packages("zlib")
    add_packages("python", { links = {} })
    add_files("core/*.cpp")
    add_defines("UNICODE", "PY_SSIZE_T_CLEAN")
    if is_plat("windows") then
        add_links("Dwrite")
    end
    if is_plat("macosx") then
        -- Pango CoreText backend needs CoreText (and CoreGraphics/CoreFoundation for related symbols)
        add_frameworks("CoreText", "CoreGraphics", "CoreFoundation")
        add_ldflags("-undefined", "dynamic_lookup", {force = true})
        add_shflags("-undefined", "dynamic_lookup", {force = true})
    end
    if is_plat("linux") then
        -- 精确强制保留运行时需要的符号，防止链接器因 --as-needed / gc-sections 优化掉
        -- add_packages("zlib", "pango") 已负责链接 -lz / -lpangoft2-1.0，此处仅保留 -u 强制符号
        add_ldflags("-Wl,-u,deflateInit2_", {force = true})
        add_ldflags("-Wl,-u,pango_fc_font_create_base_metrics_for_context", {force = true})
    end
end

target("core")
    set_kind("shared")
    set_prefixname("")
    if is_plat("windows") then
        set_extension(".dll")
    elseif is_plat("macosx") then
        set_extension(".dylib")
    else
        set_extension(".so")
    end
    set_installdir("bindist")
    set_prefixdir("/", {bindir = ".", libdir = ".", includedir = "."})
    require_htmlkit()
    on_load(function (target)
        import("core.project.project")
        local python_version = project.required_packages().python:version()
        if (python_version:prerelease()[1] or ""):find("t") then
            target:add("defines", "Py_GIL_DISABLED=1")
        elseif python_version:ge("3.12") then
            target:add("defines", "Py_LIMITED_API=0x030C0000") -- Python 3.12
        else
            target:add("defines", "Py_LIMITED_API=0x030A0000") -- Python 3.10
        end
    end)
