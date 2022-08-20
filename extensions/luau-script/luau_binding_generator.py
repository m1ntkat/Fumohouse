# Mirrors a lot of what the godot-cpp binder does.
# Some code is similar or the same.

import json
from pathlib import Path

from bindgen.stack_ops import generate_stack_ops
from bindgen.builtins import generate_luau_builtins
from bindgen.classes import generate_luau_classes
from bindgen.ptrcall import generate_ptrcall


def scons_emit_files(target, source, env):
    files = [
        # Builtins
        env.File("gen/src/luagd_builtins.gen.cpp"),

        # Classes
        env.File("gen/src/luagd_classes.gen.cpp"),

        # Stack
        env.File("gen/include/luagd_bindings_stack.gen.h"),
        env.File("gen/src/luagd_bindings_stack.gen.cpp"),

        # Ptrcall
        env.File("gen/include/luagd_ptrcall.gen.h"),
        env.File("gen/src/luagd_ptrcall.gen.cpp"),
    ]

    env.Clean(files, target)

    return target + files, source


def scons_generate_bindings(target, source, env):
    api_filepath = str(source[0])
    output_dir = target[0].abspath

    # Load JSON
    api = None

    with open(api_filepath) as api_file:
        api = json.load(api_file)

    # Initialize output folders
    src_dir = Path(output_dir) / "gen" / "src"
    src_dir.mkdir(parents=True, exist_ok=True)

    include_dir = Path(output_dir) / "gen" / "include"
    include_dir.mkdir(parents=True, exist_ok=True)

    # Codegen
    generate_stack_ops(src_dir, include_dir, api)
    generate_ptrcall(src_dir, include_dir)

    generate_luau_builtins(src_dir, api["builtin_classes"])
    generate_luau_classes(src_dir, api["classes"])

    return None
