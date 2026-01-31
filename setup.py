import json
import os
from pathlib import Path
from shutil import copyfile
from subprocess import check_call, check_output
import sys
import sysconfig
from shutil import copyfile
from setuptools import Extension, setup
from setuptools.command.build_ext import build_ext, get_abi3_suffix
from setuptools.command.egg_info import egg_info
from setuptools.command.sdist import sdist


def get_submodules(ref="HEAD", re_update=False):
    lock = Path("./gitmodules.lock")
    if lock.exists() and not re_update:
        with lock.open("r") as f:
            return json.load(f)
    out = check_output(["git", "ls-tree", ref], text=True)
    submods = []
    for line in out.splitlines():
        mode, type_, commit, path = line.split(None, 3)
        if mode == "160000" and type_ == "commit":
            url = check_output(
                ["git", "config", "-f", ".gitmodules", f"submodule.{path}.url"],
                text=True,
            ).strip()
            submods.append([path, url, commit])
    with lock.open("w") as f:
        json.dump(submods, f, indent=2)
    return submods


def ensure_submodules(cmd):
    for path, url, commit in get_submodules():
        subdir = Path(path)
        if not subdir.exists():
            cmd.announce(f"Cloning {url} into {path} @ {commit}", level=20)
            check_call(["git", "clone", url, path])
        check_call(["git", "-C", path, "checkout", commit])


class EggInfo(egg_info):
    def find_sources(self):
        super().find_sources()
        get_submodules()
        self.filelist.recursive_include("repo", "*.lua")
        self.filelist.include("core/**")
        self.filelist.extend(["xmake.lua", "gitmodules.lock"])


class SDist(sdist):
    def make_release_tree(self, base_dir, files):
        super().make_release_tree(base_dir, files)
        # if bindist exists, copy it to source dist for faster local installation
        if Path("bindist").exists():
            self.copy_tree(Path("bindist"), str(Path(base_dir) / "bindist"))
            get_submodules(re_update=True)  # ensure submodules are correct


EXT_NAME = "htmlkit.core"


class XmakeBuildExt(build_ext):
    def build_extensions(self):
        build_target = Path(self.build_lib) / "htmlkit"
        build_target.mkdir(parents=True, exist_ok=True)
        bindist_dir = Path("bindist")
        core_dylib = bindist_dir / "core.dylib"
        if not core_dylib.exists():
            ensure_submodules(self)
            config_mode = os.environ.get("XMAKE_CONFIG_MODE", "releasedbg")

            xmake_path = os.path.expanduser("~/.local/bin/xmake")

            # 如果绝对路径不存在，再尝试从 PATH 找
            if not os.path.exists(xmake_path):
                from shutil import which
                xmake_path = which("xmake") or "xmake"

            print(f"DEBUG: Using xmake at: {xmake_path}")

            # 打印 xmake 路径和版本
            print(f"Using xmake at: {xmake_path}")
            check_call([xmake_path, "--version"])

            # 配置命令
            config_cmd = [
                xmake_path,
                "config",
                "-D",
                "-m",
                config_mode,
                "-y",
                "--ldflags=-lpthread",
                "--cxflags=-pthread",
                "--cflags=-pthread"
            ]

            if sys.platform == "darwin":
                target_minver = os.environ.get("MACOSX_DEPLOYMENT_TARGET", "12.0")
                config_cmd += [f"--target_minver={target_minver}"]
            check_call(config_cmd)

            # 构建 core
            check_call([xmake_path, "build", "-vD", "core"])
            check_call([xmake_path, "install"])

        dylib_target = build_target.joinpath("core.so").with_suffix(get_abi3_suffix())
        copyfile(core_dylib, dylib_target)


ext_modules = [
    Extension(
        EXT_NAME,
        sources=[],
        py_limited_api=not sysconfig.get_config_var("Py_GIL_DISABLED"),
    )
]

setup(
    cmdclass={
        "egg_info": EggInfo,
        "sdist": SDist,
        "build_ext": XmakeBuildExt,
    },
    ext_modules=ext_modules,
    packages=["htmlkit"],
    package_data={"htmlkit": ["templates/*"]},
    options={
        "bdist_wheel": {
            "py_limited_api": None
            if sysconfig.get_config_var("Py_GIL_DISABLED")
            else "cp312"
            if sys.version_info >= (3, 12)
            else "cp310",
        }
    },
)