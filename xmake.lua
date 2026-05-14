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
set_languages("c11", "cxx17")

add_rules("mode.debug", "mode.release", "mode.releasedbg")
set_license("LGPL-3.0-or-later")
add_repositories("my-repo repo")

if is_plat("linux") then
    add_requireconfs("glib", { configs = { libintl = true } })
end

add_requireconfs("python", "**.python", { system = true, override = true })
add_requireconfs("cmake", "ninja", "meson", { system = true, override = true })
add_requireconfs("**", { system = false, configs = { shared = false, pic = true } })

-- 其他包规则保持不变
add_requireconfs("fribidi", { override = true, version = "v1.0.15" })
add_requireconfs("**.cairo",  { override = true, configs = { xlib = false } })

add_requireconfs("cmake|ninja|meson", { override = true, system = false, configs = { shared = false } })

-- 包依赖定义
add_requires("libintl", { configs = { shared = false } })
add_requires("libiconv", { configs = { shared = false } })
add_requires("libffi",     { configs = { shared = false } })
-- add_requires("glib",       { configs = { shared = false } })
add_requires("harfbuzz",   { configs = { shared = false } })
add_requires("fribidi",    { configs = { shared = false } })
add_requires("litehtml",   { configs = { utf8 = true } })
add_requires("pango",      { configs = { shared = false, fontconfig = true, freetype = true } })
add_requires("cairo",      { configs = { shared = false, xlib = false } })
add_requires("zlib", "libjpeg-turbo", "libwebp", "libavif", "giflib", "aklomp-base64", "fmt")
add_requires("libavif",    { configs = { aom = true } })

-- ─────────────────────────────────────────────────────────────────────────────
-- Target
-- ─────────────────────────────────────────────────────────────────────────────
target("core")
    set_kind("shared")
    set_prefixname("")
    if is_plat("windows") then set_extension(".dll")
    elseif is_plat("macosx") then set_extension(".dylib")
    else set_extension(".so") end

    set_installdir("bindist")
    set_prefixdir("/", { bindir = ".", libdir = ".", includedir = "." })

    -- 手动注入 Python 头文件（由 cibuildwheel venv 提供的 python3）
    on_load(function(target)
        import("lib.detect.find_tool")
        
        -- 尝试寻找 python，cibuildwheel 环境下通常直接用 'python' 或 'python3'
        local python = find_tool("python") or find_tool("python3")
        
        if python then
            -- 获取头文件路径
            local incdir = os.iorunv(python.program, {"-c", "import sysconfig; print(sysconfig.get_path('include'))"}):trim()
            -- 获取库文件路径 (Windows 编译必须链接 python3x.lib)
            local libdir = os.iorunv(python.program, {"-c", "import sysconfig; print(sysconfig.get_path('stdlib'))"}):trim()
            
            if incdir and incdir ~= "" then
                target:add("includedirs", incdir)
            end

            if is_plat("windows") then
                local libpath = path.join(path.directory(libdir), "libs")
                target:add("linkdirs", libpath)
                -- 动态获取库名：python310, python313, python313t 等
                local py_lib = os.iorunv(python.program, { "-c", [[import sys; import os; v=sys.version_info; t='t' if 't' in os.path.basename(sys.executable) else ''; print(f'python{v[0]}{v[1]}{t}')]] }):trim()
                target:add("links", py_lib)
            end
        end
        
        target:add("defines", "PY_SSIZE_T_CLEAN")
    end)

    add_files("core/*.cpp")
    add_defines("UNICODE")

    add_packages("pango", "cairo", "glib", "harfbuzz", "fribidi")
    add_packages("litehtml", "libjpeg-turbo", "libwebp", "libavif", "giflib", "aklomp-base64", "fmt")
    add_packages("libintl", "libiconv", "libffi", "zlib")

    if is_plat("windows") then
        add_links("Dwrite", "User32", "Gdi32")
    end
    if is_plat("macosx") then
        add_frameworks("CoreText", "CoreGraphics", "CoreFoundation")
        add_ldflags("-undefined", "dynamic_lookup", { force = true })
        add_shflags("-undefined", "dynamic_lookup", { force = true })
    end
    if is_plat("linux") then
        on_config(function(target)
            local ldflags = {
                "-Wl,--allow-multiple-definition",
                "-Wl,-u,pango_fc_font_create_base_metrics_for_context",
                "-Wl,-u,pango_renderer_draw_glyph_item",
                "-Wl,-u,g_direct_hash",
                "-Wl,-u,ffi_type_double",
                "-Wl,-u,deflateInit2_",
                "-Wl,--whole-archive"
            }

            local function add_whole_lib(pkgname, libnames)
                local pkg = target:pkg(pkgname)
                if pkg then
                    for _, name in ipairs(libnames) do
                        local f = path.join(pkg:installdir(), "lib", name)
                        if not os.isfile(f) then f = path.join(pkg:installdir(), "lib64", name) end
                        if os.isfile(f) then table.insert(ldflags, f) end
                    end
                end
            end

            add_whole_lib("pango",    { "libpango-1.0.a", "libpangoft2-1.0.a", "libpangocairo-1.0.a" })
            add_whole_lib("cairo",    { "libcairo.a" })
            add_whole_lib("harfbuzz", { "libharfbuzz.a" })

            table.insert(ldflags, "-Wl,--no-whole-archive")
            target:add("ldflags", table.concat(ldflags, " "), { force = true })
            target:add("shflags", table.concat(ldflags, " "), { force = true })
        end)
    end