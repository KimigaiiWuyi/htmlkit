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

-- 全局开启 PIC
add_requireconfs("**", { configs = { shared = false, pic = true } })

-- ─────────────────────────────────────────────────────────────────────────────
-- 关键：阻止任何上游包（glib/meson/gettext 等）将 python 作为子依赖拉下来。
-- xmake 的 glib 包在 Linux 上会通过 meson 构建，meson 会声明 python 为
-- build-tool 依赖，从而触发 "install python 3.13.x" 的错误流程。
-- 将 python 标记为 system=true 让 xmake 直接使用宿主 python3，不再自行编译。
-- ─────────────────────────────────────────────────────────────────────────────
add_requireconfs("**.python", { override = true, system = true })
add_requireconfs("python",    { override = true, system = true })

-- 锁定 fribidi 版本，避免 v1.0.16 的构建问题
add_requireconfs("fribidi",   { override = true, version = "v1.0.15" })
add_requireconfs("**.cairo",  { override = true, configs = { xlib = false } })

-- 全局：非系统包优先从 xmake 仓库下载静态库版本
add_requireconfs("**", { override = true, system = false, configs = { shared = false } })

-- python 例外：必须 system=true（上面已覆盖，这里再显式保证不被全局规则覆盖）
add_requireconfs("**.python", { override = true, system = true })
add_requireconfs("python",    { override = true, system = true })

-- 构建工具从 xmake 仓库获取
add_requireconfs("cmake|ninja|meson", { override = true, system = false, configs = { shared = false } })

-- ─────────────────────────────────────────────────────────────────────────────
-- 包依赖定义
-- ─────────────────────────────────────────────────────────────────────────────
add_requires("libffi",     { configs = { shared = false } })
add_requires("libintl",    { configs = { shared = false } })
add_requires("glib",       { configs = { shared = false } })
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
        local incdir = os.iorun("python3 -c \"import sysconfig; print(sysconfig.get_path('include'))\""):trim()
        if incdir and incdir ~= "" then
            target:add("includedirs", incdir)
        end
        target:add("defines", "PY_SSIZE_T_CLEAN")
    end)

    add_files("core/*.cpp")
    add_defines("UNICODE")

    add_packages("pango", "cairo", "zlib", "glib", "harfbuzz", "fribidi")
    add_packages("litehtml", "libjpeg-turbo", "libwebp", "libavif", "giflib", "aklomp-base64", "fmt")

    if is_plat("windows") then
        add_links("Dwrite")
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