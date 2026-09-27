#!/usr/bin/env python3
"""Replace all occurrences of a string in a file, in-place.

Usage: replace_string_in_file.py <file> <old_string> <new_string>
"""
import sys


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <file> <old_string> <new_string>", file=sys.stderr)
        sys.exit(1)

    file_path, old_string, new_string = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError as e:
        print(f"Error reading {file_path}: {e}", file=sys.stderr)
        sys.exit(1)

    if old_string not in content:
        return

    new_content = content.replace(old_string, new_string)

    try:
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(new_content)
    except OSError as e:
        print(f"Error writing {file_path}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
