# htmlkit

一个基于 [litehtml](https://github.com/litehtml/litehtml) 的轻量级 HTML 渲染库。

## 特性

- 基于 [fontconfig](https://www.freedesktop.org/wiki/Software/fontconfig/) 的字体管理, 支持系统字体和自定义字体
- 提供了 HTML，纯文本，markdown，和 Jinja2 模板渲染的快捷函数
- 支持自定义图片和 CSS 的加载策略
- 支持通过 CSS 控制样式
- 支持自适应控制渲染宽度

## 安装

使用 pip 安装：

```bash
pip install htmlkit
```

或者使用其他 Python 包管理器安装。

## 使用

### 快速开始

```python
import asyncio
from htmlkit import html_to_pic, text_to_pic, md_to_pic

async def main():
    # 渲染 HTML 到图片
    html = "<h1>Hello World</h1><p>This is a test.</p>"
    image_bytes = await html_to_pic(html)
    
    # 保存图片
    with open("output.png", "wb") as f:
        f.write(image_bytes)

# 运行
asyncio.run(main())
```

### 初始化 Fontconfig

在使用前，建议先初始化 fontconfig：

```python
from htmlkit import init_fontconfig

# 使用默认配置初始化
init_fontconfig()

# 或者指定自定义配置
init_fontconfig(
    fontconfig_path="/path/to/fonts",
    fontconfig_file="/path/to/fonts.conf"
)
```

### API

- `html_to_pic(html, **options)` - 将 HTML 渲染为图片
- `debug_html_to_pic(html, **options)` - 渲染 HTML 并返回图片和调试信息
- `text_to_pic(text, css_path, **options)` - 将纯文本渲染为图片
- `md_to_pic(md, css_path, **options)` - 将 Markdown 渲染为图片
- `template_to_html(template_path, template_name, **kwargs)` - 使用 Jinja2 渲染 HTML
- `template_to_pic(template_path, template_name, templates, **options)` - 使用 Jinja2 模板渲染图片

### 配置选项

htmlkit 支持通过 `init_fontconfig()` 函数配置 fontconfig 选项：

```python
from htmlkit import init_fontconfig

init_fontconfig(
    fontconfig_file="/path/to/fonts.conf",  # 覆盖默认的配置文件
    fontconfig_path="/path/to/fonts",       # 覆盖默认的配置目录
    fontconfig_sysroot="/path/to/sysroot",  # 设置 sysroot
    fc_debug="1",                           # 设置 debug 级别
    fc_lang="zh_CN",                        # 设置默认语言
    fontconfig_use_mmap="yes"               # 是否使用 mmap
)
```

更多配置选项请参考 [fontconfig 文档](https://www.freedesktop.org/software/fontconfig/fontconfig-user.html)。

### 构建说明

1. [安装 Xmake](https://xmake.io/zh/guide/quick-start#installation)
1. 初始化环境

   使用 Xmake 时必须激活 Python 虚拟环境，并且安装 `build` 依赖组。

   ```bash
   # 拉取子模块
   git submodule update --init --recursive
   # 创建虚拟环境并安装依赖，同时避免直接构建项目
   uv sync --no-install-workspace
   # 激活虚拟环境，请使用对应 shell 的命令
   source .venv/bin/activate
   # 配置 Xmake 项目并安装依赖（由于有大量依赖需要通过源码编译安装，可能耗时较长）
   xmake config -m releasedbg
   ```

1. 构建并安装

   ```bash
   # 构建
   xmake build
   # 安装
   xmake install
   # 安装到当前虚拟环境
   uv sync --reinstall-package htmlkit
   ```

   如果对 [litehtml](./litehtml) 做了修改，则需要重新构建它：

   ```bash
   xmake require --force litehtml
   # 或者用以下更 dirty 但是快速的方法
   rm -r build
   xmake clean --all
   # 重新构建并安装
   xmake build
   xmake install
   uv sync --reinstall-package htmlkit
   ```

#### 许可证

本项目的 [Python 部分](./nonebot_plugin_htmlkit) 在 MIT 许可证下发布，[C++ 部分](./core) 在 LGPL-3.0-or-later 许可证下发布。
