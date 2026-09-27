#!/usr/bin/env python3
"""Fix PySDL2 dll.py to handle colon-separated PYSDL2_DLL_PATH correctly.

The versioned library search in _finds_libs_at_path calls os.listdir(path)
where path is the full colon-separated search path, causing a FileNotFoundError.
This patch makes it iterate over each subpath individually.
"""
import sys

OLD = """    if sys.platform not in ("win32", "darwin"):
        versioned = []
        files = os.listdir(path)
        for f in files:
            for libname in searchfor:
                dllname = "lib{0}.so".format(libname)
                if dllname in f and not (dllname == f or f.startswith(".")):
                    versioned.append(os.path.join(path, f))
        versioned.sort(key = _so_version_num, reverse = True)
        results = results + versioned"""

NEW = """    if sys.platform not in ("win32", "darwin"):
        versioned = []
        for subpath in str.split(path, os.pathsep):
            if not os.path.isdir(subpath):
                continue
            files = os.listdir(subpath)
            for f in files:
                for libname in searchfor:
                    dllname = "lib{0}.so".format(libname)
                    if dllname in f and not (dllname == f or f.startswith(".")):
                        versioned.append(os.path.join(subpath, f))
        versioned.sort(key = _so_version_num, reverse = True)
        results = results + versioned"""


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <dll.py>", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
    except OSError as e:
        print(f"Error reading {file_path}: {e}", file=sys.stderr)
        sys.exit(1)

    if OLD not in content:
        return

    new_content = content.replace(OLD, NEW)

    try:
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(new_content)
    except OSError as e:
        print(f"Error writing {file_path}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
