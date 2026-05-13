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

-- 1. 模式匹配修复：使用 ** 确保对子依赖生效
add_requires("libintl", {configs = {shared = false}})
add_requires("litehtml", {configs = {utf8 = true}})
add_requires("pango", {configs = {shared = false}})
add_requires("libjpeg-turbo", "libwebp", "giflib", "aklomp-base64", "fmt")
add_requires("zlib", {configs = {shared = false}})
set_languages("c++17")
add_requires("libavif", {configs = { aom = true }})
add_requires("cairo", {configs = { xlib = false }})

-- 修复 glob 模式
add_requireconfs("**.cairo", { override = true, configs = { xlib = false } })
add_requireconfs("**.fribidi", { override = true, version = "1.0.15" })
add_requireconfs("**.python", { override = true, configs = { headeronly = true, shared = true } })
add_requireconfs("**|python|cmake|ninja|meson", { override = true, system = false, configs = { shared = false } })

function require_htmlkit()
    if is_plat("linux") then
        -- 2. 核心修复：使用逗号分隔的单条指令强制链接顺序
        -- 这样做可以绕过 xmake 对 add_links 的重新排序
        add_shflags("-Wl,--no-as-needed", {force = true})
        add_shflags("-Wl,--whole-archive,-lz,-lpangoft2-1.0,--no-whole-archive", {force = true})

        if is_arch("x86_64") then
            add_linkorders("pangocairo-1.0", "pango-1.0")
            add_linkorders("pangoft2-1.0", "pango-1.0")
        else
            add_linkorders("pangocairo-1.0", "pangoft2-1.0", "pango-1.0")
        end
    end

    -- 依然保留 add_packages，为了让 xmake 自动处理头文件路径和库搜索路径(-L)
    add_packages("litehtml", "cairo", "pango", "libjpeg-turbo", "libwebp", "libavif", "giflib", "aklomp-base64", "fmt", "zlib")
    add_packages("python", { links = {} })
    
    add_files("core/*.cpp")
    add_defines("UNICODE", "PY_SSIZE_T_CLEAN")

    if is_plat("windows") then
        add_links("Dwrite")
    end
    if is_plat("macosx") then
        add_frameworks("CoreText", "CoreGraphics", "CoreFoundation")
        add_ldflags("-undefined", "dynamic_lookup", {force = true})
        add_shflags("-undefined", "dynamic_lookup", {force = true})
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
