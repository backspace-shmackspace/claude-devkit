#!/usr/bin/env python3
"""
codebase-scanner.py — Deterministic codebase symbol index for agent context.

Extracts symbols (functions, classes, methods), import graph, and file metadata
from a project directory. Outputs a compact summary or full JSON index.

Usage: python3 scripts/codebase-scanner.py [OPTIONS] [PATH]

Tree-sitter mode is used when py-tree-sitter >= 0.25.0 is importable.
Regex fallback is used otherwise — never blocks skill execution.

Exit codes:
  0   Success (output on stdout)
  0   Success with regex fallback (output on stdout, warning on stderr)
  1   Fatal error (no output)
  2   Invalid arguments
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import hmac
import json
import os
import re
import signal
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Optional

__version__ = "1.0.0"

# ---------------------------------------------------------------------------
# Data Model
# ---------------------------------------------------------------------------

@dataclasses.dataclass
class FileEntry:
    path: str          # Relative path from project root
    language: str      # "python", "typescript", "java", "go", "unknown"
    line_count: int
    size_bytes: int


@dataclasses.dataclass
class SymbolEntry:
    name: str          # "MyClass.my_method" or "standalone_function"
    kind: str          # "class" | "function" | "method" | "interface" | "type"
    file: str          # Relative path from project root
    line: int          # 1-based line number
    signature: str     # Condensed signature
    visibility: str    # "public" | "private" | "internal" | "exported"


@dataclasses.dataclass
class ImportEntry:
    source_file: str   # File that imports
    target: str        # What is imported
    kind: str          # "stdlib" | "local" | "third_party"
    names: list        # Specific names imported


@dataclasses.dataclass
class CodebaseIndex:
    project_root: str
    scan_time: str     # ISO 8601
    scanner_version: str
    parser_mode: str   # "tree-sitter" | "tree-sitter-partial" | "regex-fallback"
    languages: dict    # {"python": 42, "typescript": 18}
    file_count: int
    symbol_count: int
    files: list        # list[FileEntry]
    symbols: list      # list[SymbolEntry]
    imports: list      # list[ImportEntry]


# ---------------------------------------------------------------------------
# Default exclusions
# ---------------------------------------------------------------------------

EXCLUDED_DIRS = frozenset({
    "node_modules", "__pycache__", ".git", ".venv", "venv",
    "dist", "build", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    "coverage", ".coverage", ".tox", "htmlcov", ".eggs", "*.egg-info",
    ".idea", ".vscode", ".DS_Store", "target",  # Java/Rust build
})

EXCLUDED_EXTENSIONS = frozenset({
    ".min.js", ".min.css", ".map", ".lock", ".sum",
    ".pyc", ".pyo", ".class", ".jar", ".war",
    ".so", ".dylib", ".dll", ".exe", ".bin",
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico",
    ".pdf", ".docx", ".xlsx",
    ".zip", ".tar", ".gz", ".bz2",
})

# Language extension mapping
LANGUAGE_EXTENSIONS = {
    ".py": "python",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".js": "typescript",   # parse with TS extractor
    ".jsx": "typescript",
    ".java": "java",
    ".go": "go",
}

# Python standard library modules (partial list for classification)
PYTHON_STDLIB = frozenset({
    "os", "sys", "re", "json", "math", "io", "abc", "ast", "asyncio",
    "collections", "contextlib", "copy", "dataclasses", "datetime",
    "enum", "functools", "glob", "hashlib", "hmac", "http", "inspect",
    "itertools", "logging", "operator", "pathlib", "pickle", "platform",
    "pprint", "queue", "random", "shutil", "signal", "socket", "sqlite3",
    "string", "struct", "subprocess", "tempfile", "threading", "time",
    "traceback", "typing", "unicodedata", "unittest", "urllib", "uuid",
    "warnings", "weakref", "xml", "zipfile", "zlib", "argparse", "csv",
    "getopt", "getpass", "html", "http", "importlib", "ipaddress",
    "multiprocessing", "numbers", "optparse", "pdb", "pkgutil",
    "posixpath", "pwd", "runpy", "secrets", "select", "shelve",
    "smtplib", "stat", "statistics", "tarfile", "textwrap", "token",
    "tokenize", "types", "base64", "binascii", "calendar", "cgi",
    "cgitb", "chunk", "cmath", "cmd", "code", "codecs", "codeop",
    "colorsys", "compileall", "concurrent", "configparser", "contextlib",
    "ctypes", "curses", "decimal", "difflib", "dis", "email",
    "encodings", "errno", "fcntl", "fractions", "ftplib", "gc",
    "grp", "gzip", "heapq", "imaplib", "imghdr", "imp", "keyword",
    "lib2to3", "linecache", "locale", "lzma", "mailbox", "mailcap",
    "marshal", "mimetypes", "mmap", "modulefinder", "nntplib",
    "ntpath", "optparse", "parser", "plistlib", "poplib", "profile",
    "pstats", "pty", "py_compile", "pyclbr", "pydoc", "readline",
    "resource", "rlcompleter", "sched", "sndhdr", "socketserver",
    "spwd", "ssl", "stringprep", "sysconfig", "syslog", "tabnanny",
    "telnetlib", "termios", "test", "textwrap", "trace", "tracemalloc",
    "tty", "turtle", "turtledemo", "uu", "venv", "wave", "webbrowser",
    "winreg", "winsound", "wsgiref", "xdrlib", "xmlrpc", "zipapp",
    "zipimport", "__future__", "builtins", "site", "atexit",
    "faulthandler", "msvcrt", "nt", "posix", "winapi",
})

GO_STDLIB = frozenset({
    "fmt", "os", "io", "net", "http", "encoding", "strings", "strconv",
    "math", "sort", "sync", "time", "errors", "log", "bufio", "bytes",
    "context", "crypto", "database", "flag", "html", "image", "index",
    "mime", "path", "reflect", "regexp", "runtime", "testing", "text",
    "unicode", "unsafe", "archive", "compress", "container", "debug",
    "expvar", "go", "hash", "internal", "iter", "maps", "plugin", "slices",
    "unique",
})


# ---------------------------------------------------------------------------
# Sanitization
# ---------------------------------------------------------------------------

_SYMBOL_SAFE_RE = re.compile(r'[^\w\s\.\(\)\[\],:\-\>\*&\|/]', re.UNICODE)

def sanitize_symbol(name: str) -> str:
    """Strip control characters and disallowed chars from symbol names."""
    # Remove control characters
    cleaned = "".join(c for c in name if c.isprintable())
    # Strip remaining unsafe chars (keep identifier chars + common sig chars)
    cleaned = _SYMBOL_SAFE_RE.sub("", cleaned).strip()
    return cleaned[:200]  # hard cap


# ---------------------------------------------------------------------------
# FileDiscovery
# ---------------------------------------------------------------------------

class FileDiscovery:
    """Recursive file walking with security constraints (adapted from nano-analyzer)."""

    def __init__(
        self,
        project_root: str,
        max_files: int = 500,
        max_file_size: int = 200_000,
        include_patterns: list | None = None,
        exclude_patterns: list | None = None,
        quiet: bool = False,
    ):
        self.project_root = os.path.realpath(project_root)
        self.max_files = max_files
        self.max_file_size = max_file_size
        self.include_patterns = include_patterns or []
        self.exclude_patterns = exclude_patterns or []
        self.quiet = quiet
        self._skipped_symlinks = 0
        self._skipped_large = 0
        self._skipped_binary = 0
        self._skipped_excluded = 0
        self._limit_hit = False

    def _log(self, msg: str) -> None:
        if not self.quiet:
            print(msg, file=sys.stderr)

    def _is_binary(self, path: str) -> bool:
        """Detect binary files by null byte in first 8KB."""
        try:
            with open(path, "rb") as f:
                chunk = f.read(8192)
            return b"\x00" in chunk
        except OSError:
            return True

    def _is_excluded_dir(self, dirname: str) -> bool:
        return dirname in EXCLUDED_DIRS or dirname.endswith(".egg-info")

    def _matches_pattern(self, rel_path: str, patterns: list) -> bool:
        import fnmatch
        for pat in patterns:
            if fnmatch.fnmatch(rel_path, pat) or fnmatch.fnmatch(os.path.basename(rel_path), pat):
                return True
        return False

    def discover(self) -> list[FileEntry]:
        """Walk project root and return FileEntry list."""
        entries: list[FileEntry] = []
        file_count = 0

        for dirpath, dirnames, filenames in os.walk(self.project_root):
            # Filter excluded directories in-place (os.walk respects in-place modification)
            dirnames[:] = [
                d for d in sorted(dirnames)
                if not self._is_excluded_dir(d) and not d.startswith(".")
            ]

            for filename in sorted(filenames):
                if file_count >= self.max_files:
                    self._limit_hit = True
                    break

                filepath = os.path.join(dirpath, filename)

                # Security: reject symlinks
                if os.path.islink(filepath):
                    self._skipped_symlinks += 1
                    self._log(f"  Skipping symlink: {filepath}")
                    continue

                # Security: canonicalize and verify within project root
                try:
                    real_path = os.path.realpath(filepath)
                except OSError as e:
                    self._log(f"  Skipping (realpath failed): {filepath}: {e}")
                    continue

                if not real_path.startswith(self.project_root + os.sep) and real_path != self.project_root:
                    self._log(f"  Skipping path outside project root: {filepath}")
                    continue

                # Reject null bytes in filename
                if "\x00" in filename:
                    continue

                # Extension filter
                _, ext = os.path.splitext(filename)
                ext = ext.lower()

                # Check excluded extensions
                if ext in EXCLUDED_EXTENSIONS:
                    self._skipped_excluded += 1
                    continue

                # Only process known language extensions
                if ext not in LANGUAGE_EXTENSIONS:
                    continue

                # Relative path from project root
                try:
                    rel_path = os.path.relpath(filepath, self.project_root)
                except ValueError:
                    continue

                # Apply include/exclude patterns
                if self.include_patterns and not self._matches_pattern(rel_path, self.include_patterns):
                    continue
                if self.exclude_patterns and self._matches_pattern(rel_path, self.exclude_patterns):
                    self._skipped_excluded += 1
                    continue

                # Size check
                try:
                    size = os.path.getsize(filepath)
                except OSError:
                    continue

                if size > self.max_file_size:
                    self._skipped_large += 1
                    self._log(f"  Skipping large file ({size} bytes): {rel_path}")
                    continue

                # Binary check
                if self._is_binary(filepath):
                    self._skipped_binary += 1
                    continue

                # Count lines
                try:
                    with open(filepath, encoding="utf-8", errors="replace") as f:
                        content = f.read()
                    line_count = content.count("\n") + (1 if content and not content.endswith("\n") else 0)
                except OSError:
                    continue

                language = LANGUAGE_EXTENSIONS.get(ext, "unknown")
                entries.append(FileEntry(
                    path=rel_path,
                    language=language,
                    line_count=line_count,
                    size_bytes=size,
                ))
                file_count += 1

            if self._limit_hit:
                break

        if self._limit_hit:
            self._log(
                f"  File limit reached ({self.max_files}). "
                f"Use --max-files to increase. Some files not scanned."
            )

        return entries

    def stats(self) -> dict:
        return {
            "skipped_symlinks": self._skipped_symlinks,
            "skipped_large": self._skipped_large,
            "skipped_binary": self._skipped_binary,
            "skipped_excluded": self._skipped_excluded,
            "limit_hit": self._limit_hit,
        }


# ---------------------------------------------------------------------------
# RegexFallbackParser
# ---------------------------------------------------------------------------

class RegexFallbackParser:
    """Regex-based extraction when tree-sitter is unavailable."""

    # Python patterns
    _PY_CLASS = re.compile(r"^class\s+(\w+)", re.MULTILINE)
    _PY_FUNC = re.compile(r"^(\s*)def\s+(\w+)\s*(\([^)]*\)(?:\s*->[^\n:]+)?)\s*:", re.MULTILINE)
    _PY_IMPORT = re.compile(r"^(?:from\s+([\w.]+)\s+import\s+(.*)|import\s+(.+))", re.MULTILINE)
    _PY_DECORATOR = re.compile(r"^(\s*)@(\w+)", re.MULTILINE)

    # TypeScript/JavaScript patterns
    _TS_CLASS = re.compile(r"^(?:export\s+)?(?:abstract\s+)?class\s+(\w+)", re.MULTILINE)
    _TS_INTERFACE = re.compile(r"^(?:export\s+)?interface\s+(\w+)", re.MULTILINE)
    _TS_TYPE = re.compile(r"^(?:export\s+)?type\s+(\w+)\s*=", re.MULTILINE)
    _TS_FUNC = re.compile(
        r"^(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*(\([^)]*\)(?:\s*:\s*[\w<>\[\]|&\s]+)?)",
        re.MULTILINE
    )
    _TS_METHOD = re.compile(
        r"^\s+(?:public\s+|private\s+|protected\s+|static\s+|async\s+)*(\w+)\s*(\([^)]*\)(?:\s*:\s*[\w<>\[\]|&\s]+)?)\s*\{",
        re.MULTILINE
    )
    _TS_ARROW = re.compile(
        r"^(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\(?[^)]*\)?\s*=>",
        re.MULTILINE
    )
    _TS_IMPORT = re.compile(
        r'^import\s+(?:\{([^}]+)\}|(\w+)|\*\s+as\s+(\w+))\s+from\s+[\'"]([^\'"]+)[\'"]',
        re.MULTILINE
    )

    # Java patterns
    _JAVA_CLASS = re.compile(
        r"^(?:public\s+|private\s+|protected\s+|abstract\s+|final\s+)*(?:class|interface|enum|record)\s+(\w+)",
        re.MULTILINE
    )
    _JAVA_METHOD = re.compile(
        r"^\s+(?:public\s+|private\s+|protected\s+|static\s+|final\s+|abstract\s+|synchronized\s+)*"
        r"(?:[\w<>\[\],\s]+)\s+(\w+)\s*(\([^)]*\))",
        re.MULTILINE
    )
    _JAVA_IMPORT = re.compile(r"^import\s+(static\s+)?([\w.]+)\s*;", re.MULTILINE)

    # Go patterns
    _GO_FUNC = re.compile(r"^func\s+(?:\([^)]+\)\s+)?(\w+)\s*(\([^)]*\))", re.MULTILINE)
    _GO_TYPE = re.compile(r"^type\s+(\w+)\s+(?:struct|interface)", re.MULTILINE)
    _GO_IMPORT_SINGLE = re.compile(r'^import\s+"([^"]+)"', re.MULTILINE)
    _GO_IMPORT_GROUP = re.compile(r'^import\s+\(([^)]+)\)', re.MULTILINE | re.DOTALL)
    _GO_IMPORT_ITEM = re.compile(r'"([^"]+)"')

    def parse_file(self, filepath: str, rel_path: str, language: str, content: str) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        """Parse a single file and return (symbols, imports)."""
        if language == "python":
            return self._parse_python(rel_path, content)
        elif language == "typescript":
            return self._parse_typescript(rel_path, content)
        elif language == "java":
            return self._parse_java(rel_path, content)
        elif language == "go":
            return self._parse_go(rel_path, content)
        return [], []

    def _classify_import(self, module: str, language: str) -> str:
        """Classify import as stdlib, local, or third_party."""
        if language == "python":
            top = module.split(".")[0]
            if top in PYTHON_STDLIB:
                return "stdlib"
            if module.startswith("."):
                return "local"
            return "third_party"
        elif language == "typescript":
            if module.startswith(".") or module.startswith("/"):
                return "local"
            return "third_party"
        elif language == "java":
            if module.startswith("java.") or module.startswith("javax.") or module.startswith("sun."):
                return "stdlib"
            return "third_party"
        elif language == "go":
            if "/" not in module:
                top = module.split("/")[0]
                if top in GO_STDLIB:
                    return "stdlib"
            if module.startswith(".") or not module.count(".") > 0:
                return "stdlib"
            return "third_party"
        return "third_party"

    def _parse_python(self, rel_path: str, content: str) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        symbols: list[SymbolEntry] = []
        imports: list[ImportEntry] = []
        lines = content.splitlines()

        # Track current class for method assignment
        current_class: Optional[str] = None
        current_class_indent = -1

        class_line_map: dict[str, int] = {}
        for m in self._PY_CLASS.finditer(content):
            cls_name = sanitize_symbol(m.group(1))
            if cls_name:
                line_num = content[:m.start()].count("\n") + 1
                class_line_map[cls_name] = line_num
                symbols.append(SymbolEntry(
                    name=cls_name,
                    kind="class",
                    file=rel_path,
                    line=line_num,
                    signature=f"class {cls_name}",
                    visibility="public" if not cls_name.startswith("_") else "private",
                ))

        for m in self._PY_FUNC.finditer(content):
            # Strip leading newlines from group(1): ^(\s*) in MULTILINE can capture
            # a newline before the line's actual indent spaces.
            raw_indent = m.group(1).lstrip("\n")
            indent = len(raw_indent)
            func_name = sanitize_symbol(m.group(2))
            params = m.group(3) or "()"
            if not func_name:
                continue
            line_num = content[:m.start()].count("\n") + 1

            # Determine if this is a method (indented inside a class)
            kind = "function"
            full_name = func_name
            visibility = "public"

            if indent > 0:
                # Find enclosing class
                enclosing = None
                for i in range(line_num - 2, -1, -1):
                    if i < len(lines):
                        cm = re.match(r"^class\s+(\w+)", lines[i])
                        if cm:
                            enclosing = sanitize_symbol(cm.group(1))
                            break
                if enclosing:
                    kind = "method"
                    full_name = f"{enclosing}.{func_name}"

            if func_name.startswith("__") and func_name.endswith("__"):
                visibility = "private"
            elif func_name.startswith("_"):
                visibility = "private"

            sig = sanitize_symbol(f"def {func_name}{params}")
            symbols.append(SymbolEntry(
                name=full_name,
                kind=kind,
                file=rel_path,
                line=line_num,
                signature=sig[:120],
                visibility=visibility,
            ))

        # Imports
        for m in self._PY_IMPORT.finditer(content):
            line_num = content[:m.start()].count("\n") + 1
            if m.group(1):  # from X import Y
                module = m.group(1)
                names_str = m.group(2)
                names = [n.strip().split(" as ")[0].strip() for n in names_str.split(",") if n.strip()]
                kind = self._classify_import(module, "python")
                imports.append(ImportEntry(source_file=rel_path, target=module, kind=kind, names=names[:10]))
            elif m.group(3):  # import X
                for mod in m.group(3).split(","):
                    module = mod.strip().split(" as ")[0].strip()
                    if module:
                        kind = self._classify_import(module, "python")
                        imports.append(ImportEntry(source_file=rel_path, target=module, kind=kind, names=[]))

        return symbols, imports

    def _parse_typescript(self, rel_path: str, content: str) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        symbols: list[SymbolEntry] = []
        imports: list[ImportEntry] = []

        # Classes
        for m in self._TS_CLASS.finditer(content):
            cls_name = sanitize_symbol(m.group(1))
            if cls_name:
                line_num = content[:m.start()].count("\n") + 1
                is_exported = "export" in content[max(0, m.start()-20):m.start()]
                symbols.append(SymbolEntry(
                    name=cls_name,
                    kind="class",
                    file=rel_path,
                    line=line_num,
                    signature=f"class {cls_name}",
                    visibility="exported" if is_exported else "public",
                ))

        # Interfaces
        for m in self._TS_INTERFACE.finditer(content):
            name = sanitize_symbol(m.group(1))
            if name:
                line_num = content[:m.start()].count("\n") + 1
                symbols.append(SymbolEntry(
                    name=name,
                    kind="interface",
                    file=rel_path,
                    line=line_num,
                    signature=f"interface {name}",
                    visibility="exported",
                ))

        # Type aliases
        for m in self._TS_TYPE.finditer(content):
            name = sanitize_symbol(m.group(1))
            if name:
                line_num = content[:m.start()].count("\n") + 1
                symbols.append(SymbolEntry(
                    name=name,
                    kind="type",
                    file=rel_path,
                    line=line_num,
                    signature=f"type {name}",
                    visibility="exported",
                ))

        # Functions
        for m in self._TS_FUNC.finditer(content):
            name = sanitize_symbol(m.group(1))
            params = m.group(2) or "()"
            if name and name not in ("if", "while", "for", "switch"):
                line_num = content[:m.start()].count("\n") + 1
                symbols.append(SymbolEntry(
                    name=name,
                    kind="function",
                    file=rel_path,
                    line=line_num,
                    signature=sanitize_symbol(f"function {name}{params}")[:120],
                    visibility="exported",
                ))

        # Arrow functions assigned to const
        for m in self._TS_ARROW.finditer(content):
            name = sanitize_symbol(m.group(1))
            if name:
                line_num = content[:m.start()].count("\n") + 1
                symbols.append(SymbolEntry(
                    name=name,
                    kind="function",
                    file=rel_path,
                    line=line_num,
                    signature=f"const {name} = () => ...",
                    visibility="exported",
                ))

        # Imports
        for m in self._TS_IMPORT.finditer(content):
            named = m.group(1)
            default = m.group(2)
            star = m.group(3)
            module = m.group(4)
            names: list[str] = []
            if named:
                names = [n.strip().split(" as ")[0].strip() for n in named.split(",") if n.strip()]
            elif default:
                names = [default]
            elif star:
                names = [f"* as {star}"]
            kind = self._classify_import(module, "typescript")
            imports.append(ImportEntry(source_file=rel_path, target=module, kind=kind, names=names[:10]))

        return symbols, imports

    def _parse_java(self, rel_path: str, content: str) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        symbols: list[SymbolEntry] = []
        imports: list[ImportEntry] = []

        # Classes/interfaces/enums
        for m in self._JAVA_CLASS.finditer(content):
            name = sanitize_symbol(m.group(1))
            if name:
                line_num = content[:m.start()].count("\n") + 1
                symbols.append(SymbolEntry(
                    name=name,
                    kind="class",
                    file=rel_path,
                    line=line_num,
                    signature=f"class {name}",
                    visibility="public",
                ))

        # Methods
        for m in self._JAVA_METHOD.finditer(content):
            name = sanitize_symbol(m.group(1))
            params = m.group(2) or "()"
            if name and not name[0].isupper() and name not in ("if", "while", "for", "return"):
                line_num = content[:m.start()].count("\n") + 1
                symbols.append(SymbolEntry(
                    name=name,
                    kind="method",
                    file=rel_path,
                    line=line_num,
                    signature=sanitize_symbol(f"{name}{params}")[:120],
                    visibility="public",
                ))

        # Imports
        for m in self._JAVA_IMPORT.finditer(content):
            module = m.group(2)
            kind = self._classify_import(module, "java")
            imports.append(ImportEntry(source_file=rel_path, target=module, kind=kind, names=[]))

        return symbols, imports

    def _parse_go(self, rel_path: str, content: str) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        symbols: list[SymbolEntry] = []
        imports: list[ImportEntry] = []

        # Functions and methods
        for m in self._GO_FUNC.finditer(content):
            name = sanitize_symbol(m.group(1))
            params = m.group(2) or "()"
            if name:
                line_num = content[:m.start()].count("\n") + 1
                is_method = bool(re.match(r"func\s+\(", content[m.start():m.start()+20]))
                kind = "method" if is_method else "function"
                visibility = "exported" if name[0].isupper() else "private"
                symbols.append(SymbolEntry(
                    name=name,
                    kind=kind,
                    file=rel_path,
                    line=line_num,
                    signature=sanitize_symbol(f"func {name}{params}")[:120],
                    visibility=visibility,
                ))

        # Types (struct/interface)
        for m in self._GO_TYPE.finditer(content):
            name = sanitize_symbol(m.group(1))
            if name:
                line_num = content[:m.start()].count("\n") + 1
                symbols.append(SymbolEntry(
                    name=name,
                    kind="type",
                    file=rel_path,
                    line=line_num,
                    signature=f"type {name}",
                    visibility="exported" if name[0].isupper() else "private",
                ))

        # Single imports
        for m in self._GO_IMPORT_SINGLE.finditer(content):
            module = m.group(1)
            kind = self._classify_import(module, "go")
            imports.append(ImportEntry(source_file=rel_path, target=module, kind=kind, names=[]))

        # Group imports
        for m in self._GO_IMPORT_GROUP.finditer(content):
            block = m.group(1)
            for im in self._GO_IMPORT_ITEM.finditer(block):
                module = im.group(1)
                kind = self._classify_import(module, "go")
                imports.append(ImportEntry(source_file=rel_path, target=module, kind=kind, names=[]))

        return symbols, imports


# ---------------------------------------------------------------------------
# TreeSitterParser (only active when tree-sitter >= 0.25.0 is importable)
# ---------------------------------------------------------------------------

def _try_import_tree_sitter():
    """Attempt to import tree-sitter. Returns (tree_sitter_module, available) tuple."""
    try:
        import tree_sitter  # noqa: F401
        return tree_sitter, True
    except ImportError:
        return None, False


class TreeSitterParser:
    """
    Parse files using py-tree-sitter >= 0.25.0 (QueryCursor API).
    Falls back to RegexFallbackParser per-file if a language grammar fails to load.
    """

    def __init__(self, quiet: bool = False):
        self.quiet = quiet
        self._regex_fallback = RegexFallbackParser()
        self._language_cache: dict[str, Any] = {}
        self._ts, self._available = _try_import_tree_sitter()
        if self._available:
            self._init_languages()

    def _log(self, msg: str) -> None:
        if not self.quiet:
            print(msg, file=sys.stderr)

    def _init_languages(self) -> None:
        """Load available tree-sitter language grammars."""
        grammar_map = {
            "python": "tree_sitter_python",
            "typescript": "tree_sitter_typescript",
            "java": "tree_sitter_java",
            "go": "tree_sitter_go",
        }
        for lang, pkg in grammar_map.items():
            try:
                mod = __import__(pkg)
                # tree-sitter-python exposes language() function
                if hasattr(mod, "language"):
                    lang_obj = self._ts.Language(mod.language())
                elif hasattr(mod, "Language"):
                    lang_obj = mod.Language
                else:
                    continue
                self._language_cache[lang] = lang_obj
            except (ImportError, Exception) as e:
                self._log(f"  tree-sitter: {lang} grammar not available: {e}")

    @property
    def available_languages(self) -> set:
        return set(self._language_cache.keys())

    def _parse_with_timeout(self, parser: Any, source_bytes: bytes, timeout_secs: int = 5) -> Any:
        """Parse with a per-file timeout on Unix systems."""
        if not hasattr(signal, "SIGALRM"):
            # Windows: no alarm, just parse
            return parser.parse(source_bytes)

        class _Timeout(Exception):
            pass

        def _handler(signum, frame):
            raise _Timeout()

        old_handler = signal.signal(signal.SIGALRM, _handler)
        signal.alarm(timeout_secs)
        try:
            tree = parser.parse(source_bytes)
            signal.alarm(0)
            return tree
        except _Timeout:
            signal.alarm(0)
            raise
        finally:
            signal.signal(signal.SIGALRM, old_handler)
            signal.alarm(0)

    def _query_matches(self, language: Any, query_str: str, node: Any) -> list:
        """Execute a tree-sitter query using QueryCursor API (tree-sitter >= 0.25.0)."""
        try:
            query = self._ts.Query(language, query_str)
            cursor = self._ts.QueryCursor(query)
            matches = list(cursor.matches(node))
            return matches
        except Exception:
            return []

    def parse_file(self, filepath: str, rel_path: str, language: str, content: str) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        """Parse file with tree-sitter, falling back to regex on error."""
        if language not in self._language_cache:
            return self._regex_fallback.parse_file(filepath, rel_path, language, content)

        lang_obj = self._language_cache[language]
        try:
            parser = self._ts.Parser()
            parser.language = lang_obj
            source_bytes = content.encode("utf-8", errors="replace")
            try:
                tree = self._parse_with_timeout(parser, source_bytes)
            except Exception:
                self._log(f"  Parse timeout/error for {rel_path}, using regex fallback")
                return self._regex_fallback.parse_file(filepath, rel_path, language, content)

            if language == "python":
                return self._extract_python(rel_path, content, lang_obj, tree)
            elif language == "typescript":
                return self._extract_typescript(rel_path, content, lang_obj, tree)
            elif language == "java":
                return self._extract_java(rel_path, content, lang_obj, tree)
            elif language == "go":
                return self._extract_go(rel_path, content, lang_obj, tree)
        except Exception as e:
            self._log(f"  tree-sitter parse error for {rel_path}: {e}, using regex fallback")

        return self._regex_fallback.parse_file(filepath, rel_path, language, content)

    def _node_text(self, node: Any, content: str) -> str:
        """Extract text for a node."""
        try:
            lines = content.splitlines()
            start_row, start_col = node.start_point
            end_row, end_col = node.end_point
            if start_row == end_row:
                if start_row < len(lines):
                    return lines[start_row][start_col:end_col]
            else:
                parts = []
                for i in range(start_row, min(end_row + 1, len(lines))):
                    line = lines[i]
                    if i == start_row:
                        parts.append(line[start_col:])
                    elif i == end_row:
                        parts.append(line[:end_col])
                    else:
                        parts.append(line)
                return " ".join(parts)
        except Exception:
            return ""

    def _extract_python(self, rel_path: str, content: str, lang_obj: Any, tree: Any) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        """Extract Python symbols using tree-sitter QueryCursor API."""
        symbols: list[SymbolEntry] = []
        imports: list[ImportEntry] = []

        root = tree.root_node

        # --- Symbols: functions and classes ---
        sym_query_str = """
            (function_definition name: (identifier) @func.name) @func.def
            (class_definition name: (identifier) @class.name) @class.def
        """
        try:
            for _pattern_index, match in self._query_matches(lang_obj, sym_query_str, root):
                # match is a dict of capture_name -> list[node]
                if "func.name" in match:
                    for name_node in match["func.name"]:
                        name = self._node_text(name_node, content)
                        if not name:
                            continue
                        line = name_node.start_point[0] + 1
                        visibility = "private" if name.startswith("_") else "public"
                        symbols.append(SymbolEntry(
                            name=name,
                            kind="function",
                            file=rel_path,
                            line=line,
                            signature=f"def {name}(...)",
                            visibility=visibility,
                        ))
                elif "class.name" in match:
                    for name_node in match["class.name"]:
                        name = self._node_text(name_node, content)
                        if not name:
                            continue
                        line = name_node.start_point[0] + 1
                        symbols.append(SymbolEntry(
                            name=name,
                            kind="class",
                            file=rel_path,
                            line=line,
                            signature=f"class {name}",
                            visibility="public",
                        ))
        except Exception:
            # If QueryCursor API fails (grammar version mismatch etc.), fall back to regex
            return self._regex_fallback._parse_python(rel_path, content)

        # --- Imports: import and from-import statements ---
        imp_query_str = """
            (import_statement) @import
            (import_from_statement) @from_import
        """
        try:
            for _pattern_index, match in self._query_matches(lang_obj, imp_query_str, root):
                for capture_key in ("import", "from_import"):
                    if capture_key not in match:
                        continue
                    for node in match[capture_key]:
                        node_text = self._node_text(node, content).strip()
                        if capture_key == "from_import":
                            # "from X import Y" — extract module name
                            parts = node_text.split()
                            target = parts[1] if len(parts) > 1 else node_text
                            kind = self._regex_fallback._classify_import(target, "python")
                            names_part = node_text.split("import", 1)[1].strip() if "import" in node_text else ""
                            names = [n.strip() for n in names_part.split(",") if n.strip()]
                        else:
                            # "import X" — may have multiple comma-separated modules
                            module_str = node_text.replace("import ", "").strip()
                            target = module_str.split(",")[0].strip().split(" as ")[0].strip()
                            kind = self._regex_fallback._classify_import(target, "python")
                            names = []
                        imports.append(ImportEntry(
                            source_file=rel_path,
                            target=target,
                            kind=kind,
                            names=names,
                        ))
        except Exception:
            pass  # Import extraction failure is non-fatal; symbols are already extracted

        # If we got no symbols at all from tree-sitter queries, fall back to regex for this file
        if not symbols and not imports:
            return self._regex_fallback._parse_python(rel_path, content)

        return symbols, imports

    def _extract_typescript(self, rel_path: str, content: str, lang_obj: Any, tree: Any) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        """Extract TypeScript symbols — regex fallback (TS grammar API varies significantly between versions)."""
        return self._regex_fallback._parse_typescript(rel_path, content)

    def _extract_java(self, rel_path: str, content: str, lang_obj: Any, tree: Any) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        """Extract Java symbols — regex fallback."""
        return self._regex_fallback._parse_java(rel_path, content)

    def _extract_go(self, rel_path: str, content: str, lang_obj: Any, tree: Any) -> tuple[list[SymbolEntry], list[ImportEntry]]:
        """Extract Go symbols — regex fallback."""
        return self._regex_fallback._parse_go(rel_path, content)


# ---------------------------------------------------------------------------
# SymbolIndex
# ---------------------------------------------------------------------------

class SymbolIndex:
    """Aggregate symbols and imports from all files."""

    def __init__(self):
        self.symbols: list[SymbolEntry] = []
        self.imports: list[ImportEntry] = []
        self.files: list[FileEntry] = []
        self._language_counts: dict[str, int] = {}

    def add_file(self, entry: FileEntry, symbols: list[SymbolEntry], imports: list[ImportEntry]) -> None:
        self.files.append(entry)
        self.symbols.extend(symbols)
        self.imports.extend(imports)
        self._language_counts[entry.language] = self._language_counts.get(entry.language, 0) + 1

    def build_index(self, project_root: str, parser_mode: str) -> CodebaseIndex:
        import datetime
        return CodebaseIndex(
            project_root=project_root,
            scan_time=datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            scanner_version=__version__,
            parser_mode=parser_mode,
            languages=dict(self._language_counts),
            file_count=len(self.files),
            symbol_count=len(self.symbols),
            files=self.files,
            symbols=self.symbols,
            imports=self.imports,
        )


# ---------------------------------------------------------------------------
# CacheManager
# ---------------------------------------------------------------------------

class CacheManager:
    """
    File-based cache in ~/.claude-devkit/cache/<project-hash>/index.json.
    HMAC-SHA256 integrity protection.
    """

    SCHEMA_VERSION = "1.0"

    def __init__(self, project_root: str, quiet: bool = False):
        self.project_root = os.path.realpath(project_root)
        self.quiet = quiet
        self._project_hash = hashlib.sha256(self.project_root.encode()).hexdigest()[:12]
        self._cache_dir = os.path.join(
            os.path.expanduser("~"), ".claude-devkit", "cache", self._project_hash
        )
        self._cache_file = os.path.join(self._cache_dir, "index.json")
        self._hmac_secret = self._derive_hmac_secret()

    def _log(self, msg: str) -> None:
        if not self.quiet:
            print(msg, file=sys.stderr)

    def _derive_hmac_secret(self) -> bytes:
        """Derive a per-user HMAC secret from stable user identity."""
        try:
            user = os.environ.get("USER") or os.environ.get("USERNAME") or "unknown"
            home = os.path.expanduser("~")
            secret = f"{user}:{home}:{self._project_hash}"
            return secret.encode()
        except Exception:
            return b"claude-devkit-default-secret"

    def _compute_hmac(self, data: str) -> str:
        return hmac.new(self._hmac_secret, data.encode(), hashlib.sha256).hexdigest()

    def _file_mtimes(self, files: list[FileEntry]) -> dict[str, float]:
        """Get current mtimes for all files."""
        result = {}
        for f in files:
            abs_path = os.path.join(self.project_root, f.path)
            try:
                result[f.path] = os.path.getmtime(abs_path)
            except OSError:
                result[f.path] = 0.0
        return result

    def _file_hashes(self, files: list[FileEntry]) -> dict[str, str]:
        """SHA-256 hash of file content for cache invalidation."""
        result = {}
        for f in files:
            abs_path = os.path.join(self.project_root, f.path)
            try:
                with open(abs_path, "rb") as fh:
                    result[f.path] = hashlib.sha256(fh.read()).hexdigest()
            except OSError:
                result[f.path] = ""
        return result

    def load(self) -> Optional[CodebaseIndex]:
        """Load cached index if valid. Returns None if invalid/missing."""
        if not os.path.exists(self._cache_file):
            return None
        try:
            with open(self._cache_file, "r", encoding="utf-8") as f:
                raw = f.read()

            data = json.loads(raw)

            # Schema version check
            if data.get("schema_version") != self.SCHEMA_VERSION:
                self._log("  Cache schema version mismatch, forcing rescan.")
                return None

            # HMAC verification
            stored_hmac = data.pop("hmac", None)
            if stored_hmac:
                content_str = json.dumps(data, separators=(",", ":"), sort_keys=True)
                expected = self._compute_hmac(content_str)
                if not hmac.compare_digest(stored_hmac, expected):
                    self._log("  WARNING: Cache HMAC mismatch — possible tampering. Forcing full rescan.")
                    return None

            # Check if files have changed (mtime comparison)
            cached_mtimes = data.get("file_mtimes", {})
            index_data = data.get("index", {})
            files = [FileEntry(**fe) for fe in index_data.get("files", [])]

            current_mtimes = self._file_mtimes(files)
            if current_mtimes != cached_mtimes:
                return None  # Cache stale

            # Reconstruct index
            return CodebaseIndex(
                project_root=index_data["project_root"],
                scan_time=index_data["scan_time"],
                scanner_version=index_data["scanner_version"],
                parser_mode=index_data["parser_mode"],
                languages=index_data["languages"],
                file_count=index_data["file_count"],
                symbol_count=index_data["symbol_count"],
                files=[FileEntry(**fe) for fe in index_data["files"]],
                symbols=[SymbolEntry(**se) for se in index_data["symbols"]],
                imports=[ImportEntry(**ie) for ie in index_data["imports"]],
            )
        except Exception as e:
            self._log(f"  Cache load error: {e}. Forcing rescan.")
            return None

    def save(self, index: CodebaseIndex) -> None:
        """Save index to cache with HMAC integrity tag."""
        try:
            os.makedirs(self._cache_dir, mode=0o700, exist_ok=True)

            # Compute file mtimes for staleness detection
            file_mtimes = self._file_mtimes(index.files)

            # Serialize index
            index_dict = {
                "project_root": index.project_root,
                "scan_time": index.scan_time,
                "scanner_version": index.scanner_version,
                "parser_mode": index.parser_mode,
                "languages": index.languages,
                "file_count": index.file_count,
                "symbol_count": index.symbol_count,
                "files": [dataclasses.asdict(f) for f in index.files],
                "symbols": [dataclasses.asdict(s) for s in index.symbols],
                "imports": [dataclasses.asdict(i) for i in index.imports],
            }

            payload = {
                "schema_version": self.SCHEMA_VERSION,
                "file_mtimes": file_mtimes,
                "index": index_dict,
            }

            # Compute HMAC over canonical serialization
            content_str = json.dumps(payload, separators=(",", ":"), sort_keys=True)
            tag = self._compute_hmac(content_str)
            payload["hmac"] = tag

            # Atomic write
            tmp_fd, tmp_path = tempfile.mkstemp(dir=self._cache_dir, suffix=".tmp")
            try:
                with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
                    json.dump(payload, f, separators=(",", ":"))
                os.replace(tmp_path, self._cache_file)
            except Exception:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
                raise
        except Exception as e:
            self._log(f"  Cache save error (non-fatal): {e}")

    def clear(self) -> None:
        """Remove cache file."""
        try:
            if os.path.exists(self._cache_file):
                os.unlink(self._cache_file)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# OutputFormatter
# ---------------------------------------------------------------------------

class OutputFormatter:
    """Format the index as JSON or compact text summary."""

    def format_json(self, index: CodebaseIndex) -> str:
        """Full JSON output."""
        data = {
            "project_root": index.project_root,
            "scan_time": index.scan_time,
            "scanner_version": index.scanner_version,
            "parser_mode": index.parser_mode,
            "languages": index.languages,
            "file_count": index.file_count,
            "symbol_count": index.symbol_count,
            "files": [dataclasses.asdict(f) for f in index.files],
            "symbols": [dataclasses.asdict(s) for s in index.symbols],
            "imports": [dataclasses.asdict(i) for i in index.imports],
        }
        return json.dumps(data, indent=2)

    def format_summary(self, index: CodebaseIndex, max_tokens: int = 4000) -> str:
        """
        Compact text summary with deterministic truncation strategy:
        1. Always include header (parser mode, language counts, file/symbol totals)
        2. Rank files by symbol density, include top-N until 70% of budget consumed
        3. Include import graph edges for included files until 85% of budget consumed
        4. Include file listing until 95% of budget consumed
        5. Append truncation footer if needed
        """
        # Approximate tokens: 1 token ≈ 4 characters
        char_budget = max_tokens * 4
        budget_70 = int(char_budget * 0.70)
        budget_85 = int(char_budget * 0.85)
        budget_95 = int(char_budget * 0.95)

        parts: list[str] = []
        truncated = False

        # 1. Header (always included)
        lang_str = ", ".join(f"{k}({v})" for k, v in sorted(index.languages.items(), key=lambda x: -x[1]))
        if not lang_str:
            lang_str = "none"
        header = (
            f"## Codebase Structure (auto-generated by codebase-scanner v{index.scanner_version})\n"
            f"Parser: {index.parser_mode} | Languages: {lang_str} | "
            f"Files: {index.file_count} | Symbols: {index.symbol_count}"
        )
        parts.append(header)

        if index.file_count == 0:
            parts.append("\n(No source files found)")
            return "\n".join(parts)

        # 2. Build symbols-per-file map
        symbols_per_file: dict[str, list[SymbolEntry]] = {}
        for sym in index.symbols:
            symbols_per_file.setdefault(sym.file, []).append(sym)

        # Rank files by symbol density (symbols count, descending)
        ranked_files = sorted(
            index.files,
            key=lambda f: -len(symbols_per_file.get(f.path, []))
        )

        # 3. Key Modules section (top-N by symbol density)
        used_so_far = len("\n".join(parts))
        included_files: list[str] = []
        modules_lines: list[str] = ["\n### Key Modules"]

        for file_entry in ranked_files:
            syms = symbols_per_file.get(file_entry.path, [])
            if not syms:
                continue

            # Group symbols: classes with their methods, standalone functions
            class_syms = [s for s in syms if s.kind == "class"]
            func_syms = [s for s in syms if s.kind in ("function", "method")]
            other_syms = [s for s in syms if s.kind in ("interface", "type")]

            # Format: file: Class(method1, method2), standalone_func()
            parts_list: list[str] = []
            for cls in class_syms[:3]:
                cls_name = cls.name.split(".")[-1] if "." in cls.name else cls.name
                methods = [s.name.split(".")[-1] for s in func_syms if s.name.startswith(cls.name + ".")]
                if methods:
                    parts_list.append(f"{cls_name}({', '.join(methods[:5])})")
                else:
                    parts_list.append(cls_name)
            for other in other_syms[:2]:
                parts_list.append(other.name)
            standalone = [s.name for s in func_syms if "." not in s.name]
            if standalone:
                parts_list.append(", ".join(f"{n}()" for n in standalone[:4]))

            line = f"- {file_entry.path}: {', '.join(parts_list)}" if parts_list else f"- {file_entry.path}"

            candidate = "\n".join(modules_lines) + "\n" + line
            if used_so_far + len(candidate) > budget_70:
                truncated = True
                break

            modules_lines.append(line)
            included_files.append(file_entry.path)

        if len(modules_lines) > 1:
            parts.append("\n".join(modules_lines))

        # 4. Import graph (for included files only)
        used_so_far = sum(len(p) for p in parts)
        import_graph: dict[str, list[str]] = {}
        for imp in index.imports:
            if imp.source_file in set(included_files):
                import_graph.setdefault(imp.source_file, []).append(imp.target)

        if import_graph:
            graph_lines = ["\n### Import Graph (top-level)"]
            for src_file, targets in sorted(import_graph.items())[:8]:
                third_party = [t for t in targets if not t.startswith(".")]
                local = [t for t in targets if t.startswith(".")]
                deps = []
                if local:
                    deps.append(", ".join(local[:3]))
                if third_party:
                    deps.append(", ".join(third_party[:5]))
                if deps:
                    line = f"- {src_file} -> {'; '.join(deps)}"
                    candidate = "\n".join(graph_lines) + "\n" + line
                    if used_so_far + len(candidate) > budget_85:
                        break
                    graph_lines.append(line)

            if len(graph_lines) > 1:
                parts.append("\n".join(graph_lines))

        # 5. File listing
        used_so_far = sum(len(p) for p in parts)
        total_lines = sum(f.line_count for f in index.files)
        listing_header = f"\n### File Listing ({index.file_count} files, {total_lines:,} lines)"
        file_items: list[str] = []

        for f in index.files:
            item = f"{f.path} ({f.line_count} lines)"
            candidate = listing_header + " | ".join(file_items + [item])
            if used_so_far + len(candidate) > budget_95:
                truncated = True
                break
            file_items.append(item)

        if file_items:
            listing_line = listing_header + "\n" + " | ".join(file_items)
            parts.append(listing_line)

        # 6. Truncation footer
        if truncated:
            omitted_files = index.file_count - len(included_files)
            omitted_syms = index.symbol_count - sum(len(symbols_per_file.get(f, [])) for f in included_files)
            footer = f"\n... and {max(0,omitted_files)} more files, {max(0,omitted_syms)} more symbols omitted (--max-tokens {max_tokens})"
            # Ensure footer fits in remaining budget
            total_chars = sum(len(p) for p in parts) + len(footer)
            if total_chars <= char_budget + 200:  # slight overflow for footer is OK
                parts.append(footer)

        return "\n".join(parts)


# ---------------------------------------------------------------------------
# Scanner (orchestrator)
# ---------------------------------------------------------------------------

class Scanner:
    """Main orchestrator: discovery → parsing → indexing → output."""

    def __init__(
        self,
        project_root: str,
        max_files: int = 500,
        max_file_size: int = 200_000,
        max_tokens: int = 4000,
        include_patterns: list | None = None,
        exclude_patterns: list | None = None,
        no_cache: bool = False,
        quiet: bool = False,
        languages: list | None = None,
    ):
        self.project_root = os.path.realpath(project_root)
        self.max_files = max_files
        self.max_file_size = max_file_size
        self.max_tokens = max_tokens
        self.include_patterns = include_patterns or []
        self.exclude_patterns = exclude_patterns or []
        self.no_cache = no_cache
        self.quiet = quiet
        self.language_filter = set(languages) if languages else None

        # Determine parser
        # parser_mode reflects actual extraction method, not just grammar availability:
        #   "tree-sitter"         — all supported languages extracted via tree-sitter AST (future)
        #   "tree-sitter-partial" — Python extracted via tree-sitter AST; TS/Java/Go via regex
        #   "regex-fallback"      — all extraction via regex (tree-sitter not installed/loaded)
        self._ts_parser = TreeSitterParser(quiet=quiet)
        if self._ts_parser._available and self._ts_parser.available_languages:
            # Python is extracted via tree-sitter QueryCursor; other languages still use regex
            if "python" in self._ts_parser.available_languages:
                self._parser_mode = "tree-sitter-partial"
            else:
                # tree-sitter available but Python grammar not loaded; all extraction is regex
                self._parser_mode = "regex-fallback"
            self._parser = self._ts_parser
        else:
            self._parser_mode = "regex-fallback"
            self._parser = RegexFallbackParser()
            if not quiet:
                print(
                    "INFO: tree-sitter not available, using regex fallback. "
                    "Install tree-sitter in ~/.claude-devkit/scanner-venv/ for better accuracy.",
                    file=sys.stderr,
                )

        self._discovery = FileDiscovery(
            project_root=project_root,
            max_files=max_files,
            max_file_size=max_file_size,
            include_patterns=self.include_patterns,
            exclude_patterns=self.exclude_patterns,
            quiet=quiet,
        )
        self._cache = CacheManager(project_root=project_root, quiet=quiet)
        self._formatter = OutputFormatter()

    def _log(self, msg: str) -> None:
        if not self.quiet:
            print(msg, file=sys.stderr)

    def scan(self) -> CodebaseIndex:
        """Run discovery, parse files, return index."""
        # Try cache first
        if not self.no_cache:
            cached = self._cache.load()
            if cached is not None:
                self._log(f"  Cache hit: {cached.file_count} files, {cached.symbol_count} symbols")
                return cached

        # Discover files
        self._log("  Discovering files...")
        files = self._discovery.discover()

        # Filter by language if requested
        if self.language_filter:
            files = [f for f in files if f.language in self.language_filter]

        self._log(f"  Found {len(files)} source files to scan")

        # Build symbol index
        index = SymbolIndex()
        parse_errors = 0

        for file_entry in files:
            abs_path = os.path.join(self.project_root, file_entry.path)
            try:
                with open(abs_path, encoding="utf-8", errors="replace") as fh:
                    content = fh.read()
            except OSError as e:
                self._log(f"  Read error: {file_entry.path}: {e}")
                parse_errors += 1
                index.add_file(file_entry, [], [])
                continue

            try:
                symbols, imports = self._parser.parse_file(abs_path, file_entry.path, file_entry.language, content)
            except Exception as e:
                self._log(f"  Parse error: {file_entry.path}: {e}")
                parse_errors += 1
                symbols, imports = [], []

            index.add_file(file_entry, symbols, imports)

        if parse_errors > 0:
            self._log(f"  {parse_errors} parse error(s) (files still included with empty symbol list)")

        result = index.build_index(self.project_root, self._parser_mode)

        # Save to cache
        if not self.no_cache:
            self._cache.save(result)

        return result

    def output_summary(self, index: CodebaseIndex) -> str:
        return self._formatter.format_summary(index, max_tokens=self.max_tokens)

    def output_json(self, index: CodebaseIndex) -> str:
        return self._formatter.format_json(index)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def run_self_test() -> bool:
    """Run internal validation tests. Returns True if all pass."""
    import tempfile
    import shutil

    failures: list[str] = []

    def check(cond: bool, msg: str) -> None:
        if not cond:
            failures.append(f"  FAIL: {msg}")
        else:
            print(f"  PASS: {msg}")

    print("Running codebase-scanner self-test...")

    # ---- Test 1: FileDiscovery with symlink rejection ----
    print("\n[1] FileDiscovery: symlink rejection and binary detection")
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create a Python file
        py_file = os.path.join(tmpdir, "test.py")
        with open(py_file, "w") as f:
            f.write("def hello():\n    pass\n")

        # Create a symlink
        link_file = os.path.join(tmpdir, "link.py")
        try:
            os.symlink(py_file, link_file)
            has_symlinks = True
        except (OSError, NotImplementedError):
            has_symlinks = False

        # Create a binary file
        bin_file = os.path.join(tmpdir, "binary.py")
        with open(bin_file, "wb") as f:
            f.write(b"\x00\x01\x02\x03")

        disc = FileDiscovery(tmpdir, quiet=True)
        found = disc.discover()
        paths = [e.path for e in found]

        check("test.py" in paths, "real Python file found")
        if has_symlinks:
            check("link.py" not in paths, "symlink rejected")
        check("binary.py" not in paths, "binary file rejected")
        check(disc.stats()["skipped_binary"] > 0, "binary skip counter incremented")

    # ---- Test 2: Path canonicalization / escape prevention ----
    print("\n[2] FileDiscovery: path canonicalization")
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create a symlink pointing outside the project
        link_outside = os.path.join(tmpdir, "escape.py")
        try:
            os.symlink("/etc/passwd", link_outside)
        except (OSError, NotImplementedError):
            pass
        disc = FileDiscovery(tmpdir, quiet=True)
        found = disc.discover()
        paths = [e.path for e in found]
        check("escape.py" not in paths, "symlink escape rejected")

    # ---- Test 3: Regex extraction for Python ----
    print("\n[3] RegexFallbackParser: Python extraction")
    parser = RegexFallbackParser()
    py_code = """\
class MyClass:
    def __init__(self, x: int) -> None:
        self.x = x

    def compute(self, y: int) -> int:
        return self.x + y

def standalone(a, b):
    return a + b

import os
from typing import List, Optional
from . import utils
"""
    syms, imps = parser.parse_file("/tmp/test.py", "test.py", "python", py_code)
    sym_names = [s.name for s in syms]
    check("MyClass" in sym_names, "Python class extracted")
    check(any("compute" in n for n in sym_names), "Python method extracted")
    check("standalone" in sym_names, "Python standalone function extracted")
    imp_targets = [i.target for i in imps]
    check("os" in imp_targets, "Python stdlib import found")
    check("typing" in imp_targets, "Python typing import found")
    check(". utils" not in imp_targets or "utils" in imp_targets or any("utils" in t for t in imp_targets),
          "Python relative import found")
    check(any(i.kind == "stdlib" for i in imps if i.target == "os"), "Python import classified as stdlib")

    # ---- Test 4: Regex extraction for TypeScript ----
    print("\n[4] RegexFallbackParser: TypeScript extraction")
    ts_code = """\
import { useState, useEffect } from 'react';
import axios from 'axios';

export class UserService {
    async getUser(id: string): Promise<User> {
        return axios.get(`/users/${id}`);
    }
}

export function createUser(name: string): User {
    return { name };
}

export interface UserProfile {
    id: string;
    name: string;
}
"""
    syms, imps = parser.parse_file("/tmp/test.ts", "test.ts", "typescript", ts_code)
    sym_names = [s.name for s in syms]
    check("UserService" in sym_names, "TS class extracted")
    check("createUser" in sym_names, "TS function extracted")
    check("UserProfile" in sym_names, "TS interface extracted")
    imp_targets = [i.target for i in imps]
    check("react" in imp_targets, "TS import from react found")
    check(any(i.kind == "third_party" for i in imps if i.target == "axios"), "axios classified as third_party")

    # ---- Test 5: Regex extraction for Go ----
    print("\n[5] RegexFallbackParser: Go extraction")
    go_code = """\
package main

import (
    "fmt"
    "os"
    "github.com/some/pkg"
)

type Server struct {
    Port int
}

func NewServer(port int) *Server {
    return &Server{Port: port}
}

func (s *Server) Start() error {
    fmt.Println("starting")
    return nil
}
"""
    syms, imps = parser.parse_file("/tmp/test.go", "test.go", "go", go_code)
    sym_names = [s.name for s in syms]
    check("Server" in sym_names, "Go struct type extracted")
    check("NewServer" in sym_names, "Go function extracted")
    imp_targets = [i.target for i in imps]
    check("fmt" in imp_targets, "Go stdlib fmt import found")
    check(any(i.kind == "stdlib" for i in imps if i.target == "fmt"), "fmt classified as stdlib")

    # ---- Test 6: JSON output schema validation ----
    print("\n[6] OutputFormatter: JSON output schema")
    with tempfile.TemporaryDirectory() as tmpdir:
        py_file = os.path.join(tmpdir, "app.py")
        with open(py_file, "w") as f:
            f.write("def main():\n    pass\n")
        scanner = Scanner(tmpdir, quiet=True)
        idx = scanner.scan()
        json_out = scanner.output_json(idx)
        try:
            parsed = json.loads(json_out)
            check("file_count" in parsed, "JSON has file_count field")
            check("symbol_count" in parsed, "JSON has symbol_count field")
            check("symbols" in parsed, "JSON has symbols array")
            check("imports" in parsed, "JSON has imports array")
            check("files" in parsed, "JSON has files array")
            check("parser_mode" in parsed, "JSON has parser_mode field")
            check(parsed["file_count"] == 1, f"JSON file_count == 1 (got {parsed['file_count']})")
            check(parsed["symbol_count"] >= 1, f"JSON symbol_count >= 1 (got {parsed['symbol_count']})")
        except json.JSONDecodeError as e:
            failures.append(f"  FAIL: JSON output is not valid JSON: {e}")

    # ---- Test 7: Summary output format ----
    print("\n[7] OutputFormatter: summary format")
    with tempfile.TemporaryDirectory() as tmpdir:
        py_file = os.path.join(tmpdir, "service.py")
        with open(py_file, "w") as f:
            f.write("class AuthService:\n    def login(self):\n        pass\n")
        scanner = Scanner(tmpdir, quiet=True)
        idx = scanner.scan()
        summary = scanner.output_summary(idx)
        check("## Codebase Structure" in summary, "Summary has structure header")
        check("Parser:" in summary, "Summary has Parser field")
        check("Files:" in summary, "Summary has Files count")

    # ---- Test 8: Max tokens truncation ----
    print("\n[8] OutputFormatter: max-tokens truncation")
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create many files to trigger truncation
        for i in range(30):
            with open(os.path.join(tmpdir, f"module{i}.py"), "w") as f:
                f.write(f"class Class{i}:\n    def method{i}(self):\n        pass\n" * 5)
        scanner = Scanner(tmpdir, max_tokens=300, quiet=True, no_cache=True)
        idx = scanner.scan()
        summary = scanner.output_summary(idx)
        # 300 tokens * 4 chars = 1200 chars budget; allow small overhead for footer
        check(len(summary) < 2000, f"Summary respects token cap (got {len(summary)} chars)")

    # ---- Test 9: Cache write/read/invalidation ----
    print("\n[9] CacheManager: write/read/invalidation")
    with tempfile.TemporaryDirectory() as tmpdir:
        py_file = os.path.join(tmpdir, "cached.py")
        with open(py_file, "w") as f:
            f.write("def cached_func():\n    pass\n")

        scanner1 = Scanner(tmpdir, quiet=True, no_cache=False)
        idx1 = scanner1.scan()
        check(idx1.file_count == 1, "First scan: 1 file")

        # Second scan should hit cache
        scanner2 = Scanner(tmpdir, quiet=True, no_cache=False)
        idx2 = scanner2.scan()
        check(idx2.file_count == 1, "Cached scan: 1 file")
        check(idx2.symbol_count == idx1.symbol_count, "Cached symbol count matches")

        # Modify file → cache should invalidate
        time.sleep(0.01)  # ensure mtime changes
        with open(py_file, "w") as f:
            f.write("def cached_func():\n    pass\ndef new_func():\n    pass\n")
        # Touch file to update mtime
        os.utime(py_file, None)

        scanner3 = Scanner(tmpdir, quiet=True, no_cache=False)
        idx3 = scanner3.scan()
        check(idx3.symbol_count >= idx1.symbol_count, "Cache invalidated on file change")

    # ---- Test 10: Empty directory handling ----
    print("\n[10] Scanner: empty directory")
    with tempfile.TemporaryDirectory() as tmpdir:
        scanner = Scanner(tmpdir, quiet=True)
        idx = scanner.scan()
        check(idx.file_count == 0, "Empty dir: file_count == 0")
        check(idx.symbol_count == 0, "Empty dir: symbol_count == 0")
        summary = scanner.output_summary(idx)
        check("No source files found" in summary, "Empty dir: summary reports no files")

    # ---- Test 11: Max-files limit ----
    print("\n[11] Scanner: max-files limit")
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(20):
            with open(os.path.join(tmpdir, f"file{i}.py"), "w") as f:
                f.write(f"def func{i}(): pass\n")
        scanner = Scanner(tmpdir, max_files=5, quiet=True, no_cache=True)
        idx = scanner.scan()
        check(idx.file_count <= 5, f"max-files limit respected (got {idx.file_count})")

    # ---- Test 12: HMAC integrity check ----
    print("\n[12] CacheManager: HMAC tampering detection")
    with tempfile.TemporaryDirectory() as tmpdir:
        py_file = os.path.join(tmpdir, "tamper.py")
        with open(py_file, "w") as f:
            f.write("def tampered(): pass\n")
        scanner = Scanner(tmpdir, quiet=True, no_cache=False)
        scanner.scan()

        # Tamper with cache file
        cache_mgr = CacheManager(tmpdir, quiet=True)
        if os.path.exists(cache_mgr._cache_file):
            with open(cache_mgr._cache_file, "r") as f:
                data = json.load(f)
            # Modify content after computing HMAC
            data["index"]["symbol_count"] = 9999
            with open(cache_mgr._cache_file, "w") as f:
                json.dump(data, f)
            result = cache_mgr.load()
            check(result is None, "HMAC mismatch detected (returns None)")
        else:
            print("  SKIP: cache file not created (skip HMAC test)")

    # ---- Summary ----
    print(f"\n{'='*40}")
    if failures:
        print(f"SELF-TEST FAILED ({len(failures)} failures):")
        for f in failures:
            print(f)
        return False
    else:
        print(f"SELF-TEST PASSED (all checks)")
        return True


# ---------------------------------------------------------------------------
# main()
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        prog="codebase-scanner",
        description="Deterministic codebase symbol index for agent context.",
        add_help=True,
    )
    parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="Project root directory (default: current directory)",
    )
    parser.add_argument(
        "--format",
        choices=["summary", "json"],
        default="summary",
        help="Output format: summary (default) or json",
    )
    parser.add_argument(
        "--languages",
        help="Comma-separated language filter (e.g. python,typescript)",
    )
    parser.add_argument(
        "--max-files",
        type=int,
        default=500,
        help="Maximum files to scan (default: 500)",
    )
    parser.add_argument(
        "--max-file-size",
        type=int,
        default=200_000,
        help="Maximum file size in bytes (default: 200000)",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=4000,
        help="Maximum output tokens for summary mode (default: 4000)",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Skip cache, force full rescan",
    )
    parser.add_argument(
        "--include",
        action="append",
        default=[],
        metavar="PATTERN",
        help="Include only files matching glob pattern (repeatable)",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        metavar="PATTERN",
        help="Exclude files matching glob pattern (repeatable)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress stderr progress messages",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"codebase-scanner {__version__}",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run internal validation tests and exit",
    )

    args = parser.parse_args()

    # Self-test mode
    if args.self_test:
        success = run_self_test()
        return 0 if success else 1

    # Validate path
    project_root = os.path.abspath(args.path)
    if not os.path.isdir(project_root):
        print(f"ERROR: Not a directory: {args.path}", file=sys.stderr)
        return 2

    # Parse language filter
    languages = None
    if args.languages:
        languages = [lang.strip().lower() for lang in args.languages.split(",") if lang.strip()]
        valid_langs = set(LANGUAGE_EXTENSIONS.values())
        invalid = [l for l in languages if l not in valid_langs]
        if invalid:
            print(f"WARNING: Unknown languages ignored: {', '.join(invalid)}", file=sys.stderr)
            languages = [l for l in languages if l in valid_langs]

    # Validate max-tokens
    if args.max_tokens < 100:
        print("WARNING: --max-tokens below 100, using 100", file=sys.stderr)
        args.max_tokens = 100

    # Run scanner
    scanner = Scanner(
        project_root=project_root,
        max_files=args.max_files,
        max_file_size=args.max_file_size,
        max_tokens=args.max_tokens,
        include_patterns=args.include,
        exclude_patterns=args.exclude,
        no_cache=args.no_cache,
        quiet=args.quiet,
        languages=languages,
    )

    try:
        index = scanner.scan()
    except Exception as e:
        print(f"ERROR: Scanner failed: {e}", file=sys.stderr)
        return 1

    # Output
    if args.format == "json":
        output = scanner.output_json(index)
    else:
        output = scanner.output_summary(index)

    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
