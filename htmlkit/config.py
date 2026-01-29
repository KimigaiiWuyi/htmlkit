from contextlib import contextmanager
import os
from typing import get_type_hints

from pydantic import BaseModel, Field


class FcConfig(BaseModel):
    """Fontconfig 配置选项

    参考 https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user
    """

    fontconfig_file: str | None = Field(default=None, description="覆盖默认的配置文件")
    fontconfig_path: str | None = Field(default=None, description="覆盖默认的配置目录")
    fontconfig_sysroot: str | None = Field(
        default=None, description="覆盖默认的 sysroot"
    )
    fc_debug: str | None = Field(default=None, description="设置 debug 级别")
    fcdbg_match_filter: str | None = Field(
        default=None, description="当 FC_DEBUG 设置了 MATCH2 时，过滤 debug 输出"
    )
    fc_lang: str | None = Field(
        default=None, description="设置默认语言，否则从 LOCALE 环境变量获取"
    )
    fontconfig_use_mmap: str | None = Field(
        default=None, description="是否使用 mmap(2) 读取字体缓存"
    )


@contextmanager
def set_fc_environ(config: FcConfig):
    old_values = {}
    # Get field names from the model's __annotations__ or model_fields if available
    try:
        from pydantic import BaseModel
        if hasattr(config, 'model_fields'):
            field_names = config.model_fields.keys()
        else:
            field_names = get_type_hints(type(config)).keys()
    except:
        field_names = get_type_hints(type(config)).keys()
    
    for field_name in field_names:
        value = getattr(config, field_name)
        if value is not None:
            env_name = field_name.upper()
            old_values[env_name] = os.environ.get(env_name)
            os.environ[env_name] = value
    try:
        yield
    finally:
        for name, value in old_values.items():
            if value is None:
                del os.environ[name]
            else:
                os.environ[name] = value
