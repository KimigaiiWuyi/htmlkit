import pytest


@pytest.mark.asyncio
async def test_text_to_pic():
    """测试纯文本转图片功能"""
    from htmlkit import text_to_pic

    text = "Hello, World!\nThis is a test."
    img_bytes = await text_to_pic(text)
    assert img_bytes.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.asyncio
async def test_text_to_pic_jpeg():
    """测试纯文本转 JPEG 图片"""
    from htmlkit import text_to_pic

    text = "Hello, World!"
    img_bytes = await text_to_pic(text, image_format="jpeg", jpeg_quality=90)
    assert img_bytes.startswith(b"\xff\xd8")


@pytest.mark.asyncio
async def test_debug_html_to_pic():
    """测试调试模式渲染"""
    from htmlkit import debug_html_to_pic

    html = "<html><body><h1>Debug Test</h1></body></html>"
    img_bytes, debug_html = await debug_html_to_pic(html)
    assert img_bytes.startswith(b"\x89PNG\r\n\x1a\n")
    assert "Debug Test" in debug_html


@pytest.mark.asyncio
async def test_template_to_html():
    """测试模板渲染为 HTML 字符串"""
    from htmlkit import template_to_html

    html = await template_to_html(
        template_path=[],
        template_name="text.html",
        text="Test Content",
        css="",
    )
    assert "Test Content" in html


@pytest.mark.asyncio
async def test_html_to_pic_with_different_dpi():
    """测试不同 DPI 设置"""
    from htmlkit import html_to_pic

    html = "<html><body><p>DPI Test</p></body></html>"
    img_bytes = await html_to_pic(html, dpi=144.0)
    assert img_bytes.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.asyncio
async def test_html_to_pic_with_custom_size():
    """测试自定义尺寸参数"""
    from htmlkit import html_to_pic

    html = "<html><body><p>Size Test</p></body></html>"
    img_bytes = await html_to_pic(
        html, max_width=400, device_height=300, default_font_size=16.0
    )
    assert img_bytes.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.asyncio
async def test_html_to_pic_refit_false():
    """测试禁用 refit 模式"""
    from htmlkit import html_to_pic

    html = "<html><body><p>No Refit Test</p></body></html>"
    img_bytes = await html_to_pic(html, allow_refit=False)
    assert img_bytes.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.asyncio
async def test_md_to_pic_empty():
    """测试空 markdown 输入应抛出异常"""
    from htmlkit import md_to_pic

    with pytest.raises(Exception, match="md or md_path must be provided"):
        _ = await md_to_pic(md="")


@pytest.mark.asyncio
async def test_none_fetcher():
    """测试 none_fetcher 返回 None"""
    from htmlkit import none_fetcher

    result = await none_fetcher("https://example.com")
    assert result is None


@pytest.mark.asyncio
async def test_data_scheme_img_fetcher():
    """测试 data scheme 图片获取"""
    from htmlkit import data_scheme_img_fetcher

    # Test base64 data scheme
    result = await data_scheme_img_fetcher(
        "data:image/png;base64,iVBORw0KGgo="
    )
    assert result is not None

    # Test non-data scheme URL
    result = await data_scheme_img_fetcher("https://example.com/image.png")
    assert result is None


@pytest.mark.asyncio
async def test_data_scheme_css_fetcher():
    """测试 data scheme CSS 获取"""
    from htmlkit import data_scheme_css_fetcher

    # Test base64 data scheme
    result = await data_scheme_css_fetcher(
        "data:text/css;base64,Ym9keXtiYWNrZ3JvdW5kOnJlZDt9"
    )
    assert result is not None

    # Test plain data scheme
    result = await data_scheme_css_fetcher(
        "data:text/css,body%7Bbackground%3Ared%3B%7D"
    )
    assert result is not None

    # Test non-data scheme URL
    result = await data_scheme_css_fetcher("https://example.com/style.css")
    assert result is None


@pytest.mark.asyncio
async def test_combined_img_fetcher_priority():
    """测试 combined_img_fetcher 优先级：data scheme > file > network"""
    from htmlkit import combined_img_fetcher

    # data scheme 应该优先返回
    result = await combined_img_fetcher("data:image/png;base64,iVBORw0KGgo=")
    assert result is not None

    # 非 data scheme 且非 file scheme，没有 aiohttp 时返回 None
    result = await combined_img_fetcher("https://example.com/image.png")
    # 如果没有 aiohttp 安装，应该返回 None
    assert result is None or isinstance(result, bytes)


@pytest.mark.asyncio
async def test_html_to_pic_with_lang_culture():
    """测试语言和地区设置"""
    from htmlkit import html_to_pic

    html = "<html><body><p>Lang Test</p></body></html>"
    img_bytes = await html_to_pic(html, lang="en", culture="US")
    assert img_bytes.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.asyncio
async def test_html_to_pic_jpeg_quality():
    """测试不同 JPEG 质量设置"""
    from htmlkit import html_to_pic

    html = "<html><body><p>Quality Test</p></body></html>"
    # 低质量
    img_bytes_low = await html_to_pic(html, image_format="jpeg", jpeg_quality=30)
    assert img_bytes_low.startswith(b"\xff\xd8")

    # 高质量
    img_bytes_high = await html_to_pic(html, image_format="jpeg", jpeg_quality=95)
    assert img_bytes_high.startswith(b"\xff\xd8")

    # 低质量文件应该比高质量文件小（通常情况）
    assert len(img_bytes_low) <= len(img_bytes_high)


@pytest.mark.asyncio
async def test_render_empty_html():
    """测试空 HTML 内容"""
    from htmlkit import html_to_pic

    html = "<html><body></body></html>"
    img_bytes = await html_to_pic(html)
    assert img_bytes.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.asyncio
async def test_render_complex_html():
    """测试复杂 HTML 结构"""
    from htmlkit import html_to_pic

    html = """
    <html>
    <head><style>
        .container { padding: 20px; }
        .title { font-size: 24px; color: blue; }
    </style></head>
    <body>
        <div class="container">
            <h1 class="title">Complex Test</h1>
            <ul>
                <li>Item 1</li>
                <li>Item 2</li>
            </ul>
        </div>
    </body>
    </html>
    """
    img_bytes = await html_to_pic(html)
    assert img_bytes.startswith(b"\x89PNG\r\n\x1a\n")
