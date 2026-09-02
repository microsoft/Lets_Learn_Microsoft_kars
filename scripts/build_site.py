#!/usr/bin/env python3

import html
import json
import os
import re
import shutil
from pathlib import Path

import markdown


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
ASSETS = ROOT / "site-assets"
OUTPUT = ROOT / "_site"
BASE_PATH = os.environ.get("BASE_PATH", "").rstrip("/")

LANGUAGES = {
    "en": {
        "label": "English",
        "switch": "中文",
        "home": "Home",
        "contents": "Tutorial",
        "search": "Search documentation...",
        "no_results": "No matching chapters",
        "previous": "Previous",
        "next": "Next",
        "github": "GitHub repository",
        "theme": "Toggle color theme",
        "menu": "Toggle navigation",
        "documentation": "Documentation",
        "in_this_article": "In this article",
        "description": "Learn KARS through a bilingual AI startup engineering story.",
    },
    "zh-cn": {
        "label": "简体中文",
        "switch": "English",
        "home": "首页",
        "contents": "教程",
        "search": "搜索文档...",
        "no_results": "没有匹配章节",
        "previous": "上一章",
        "next": "下一章",
        "github": "GitHub 仓库",
        "theme": "切换颜色主题",
        "menu": "切换导航",
        "documentation": "文档",
        "in_this_article": "本文内容",
        "description": "通过双语 AI 创业研发故事学习 KARS。",
    },
}

CHAPTER_FILES = [
    "README.md",
    "01-why-kars.md",
    "02-local-quickstart.md",
    "03-inside-the-sandbox.md",
    "04-kubernetes-api.md",
    "05-policies-and-tools.md",
    "06-runtimes-and-byo.md",
    "07-security-and-operations.md",
    "08-aks-and-multi-agent.md",
    "09-applied-project.md",
]

THEME = """
:root {
  color-scheme: light;
  --cp-bg: #f7f4ef;
  --cp-bg-elevated: #fcfbf8;
  --cp-surface: #ffffff;
  --cp-surface-soft: #f5f5f5;
  --cp-border: #dedede;
  --cp-border-strong: #919191;
  --cp-text: #242424;
  --cp-text-muted: #5c5c5c;
  --cp-text-soft: #6f6f6f;
  --cp-accent: #b11f4b;
  --cp-accent-hover: #9a1a41;
  --cp-accent-soft: rgba(177, 31, 75, 0.08);
  --cp-accent-fg: #ffffff;
  --cp-success: #16a34a;
  --cp-danger: #dc2626;
  --cp-warning: #f59e0b;
  --cp-link: #0078d4;
  --cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.12);
  --cp-overlay: rgba(255, 255, 255, 0.8);
  --cp-panel: rgba(255, 255, 255, 0.86);
  --cp-panel-strong: rgba(255, 255, 255, 0.96);
  --cp-sheen: rgba(255, 255, 255, 0.55);
  --cp-highlight: rgba(177, 31, 75, 0.12);
}
html[data-theme="dark"] {
  color-scheme: dark;
  --cp-bg: #3d3b3a;
  --cp-bg-elevated: #343231;
  --cp-surface: #292929;
  --cp-surface-soft: #2e2e2e;
  --cp-border: #474747;
  --cp-border-strong: #5f5f5f;
  --cp-text: #dedede;
  --cp-text-muted: #919191;
  --cp-text-soft: #b0b0b0;
  --cp-accent: #fd8ea1;
  --cp-accent-hover: #fb7b91;
  --cp-accent-soft: rgba(253, 142, 161, 0.14);
  --cp-accent-fg: #1a1a1a;
  --cp-success: #4ade80;
  --cp-danger: #f87171;
  --cp-warning: #fbbf24;
  --cp-link: #4da6ff;
  --cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.32);
  --cp-overlay: rgba(41, 41, 41, 0.88);
  --cp-panel: rgba(41, 41, 41, 0.72);
  --cp-panel-strong: rgba(41, 41, 41, 0.96);
  --cp-sheen: rgba(255, 255, 255, 0.04);
  --cp-highlight: rgba(253, 142, 161, 0.12);
}
""".strip()


def slug_for(filename: str) -> str:
    return "" if filename == "README.md" else filename.removesuffix(".md")


def page_url(language: str, filename: str) -> str:
    slug = slug_for(filename)
    suffix = f"/{language}/" if not slug else f"/{language}/{slug}/"
    return f"{BASE_PATH}{suffix}"


def first_heading(source: str) -> str:
    match = re.search(r"^#\s+(.+)$", source, re.MULTILINE)
    if not match:
        raise ValueError("Every page must have an H1")
    return match.group(1).strip()


def plain_text(rendered: str) -> str:
    text = re.sub(r"<[^>]+>", " ", rendered)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def rewrite_local_links(source: str, language: str) -> str:
    other = "zh-cn" if language == "en" else "en"
    source = source.replace(f"../{other}/README.md", page_url(other, "README.md"))
    for filename in CHAPTER_FILES:
        source = source.replace(f"]({filename})", f"]({page_url(language, filename)})")
    return source


def render_markdown(source: str, language: str) -> str:
    return markdown.markdown(
        rewrite_local_links(source, language),
        extensions=["fenced_code", "tables", "toc", "sane_lists"],
        extension_configs={"toc": {"permalink": True}},
    )


def sidebar(language: str, pages: list[dict], current: str) -> str:
    labels = LANGUAGES[language]
    links = []
    for page in pages:
        active = " active" if page["filename"] == current else ""
        number = "⌂" if page["filename"] == "README.md" else page["filename"][:2]
        links.append(
            f'<a class="sidebar-link{active}" href="{page["url"]}">'
            f'<span class="nav-number">{number}</span>'
            f'<span>{html.escape(page["title"])}</span></a>'
        )
    return (
        '<nav class="sidebar-nav">'
        f'<div class="sidebar-section-title">{labels["contents"]}</div>'
        + "".join(links)
        + "</nav>"
    )


def page_navigation(language: str, pages: list[dict], index: int) -> str:
    labels = LANGUAGES[language]
    previous = pages[index - 1] if index > 0 else None
    following = pages[index + 1] if index + 1 < len(pages) else None

    def item(page: dict | None, label: str, css_class: str) -> str:
        if not page:
            return "<div></div>"
        return (
            f'<a class="page-nav-item {css_class}" href="{page["url"]}">'
            f'<span>{label}</span><strong>{html.escape(page["title"])}</strong></a>'
        )

    return (
        '<nav class="page-nav">'
        + item(previous, labels["previous"], "previous")
        + item(following, labels["next"], "next")
        + "</nav>"
    )


def article_toc(rendered: str, label: str) -> str:
    entries = []
    for anchor, heading in re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', rendered, re.DOTALL):
        title = plain_text(heading).removesuffix("¶").strip()
        entries.append(
            f'<a class="article-toc-link" href="#{html.escape(anchor)}">'
            f"{html.escape(title)}</a>"
        )
    if not entries:
        return ""
    return (
        '<aside class="article-toc">'
        f'<div class="article-toc-title">{html.escape(label)}</div>'
        f'<nav>{"".join(entries)}</nav></aside>'
    )


def html_document(
    language: str,
    page: dict,
    pages: list[dict],
    index: int,
    search_index: list[dict],
    root_copy: bool = False,
) -> str:
    labels = LANGUAGES[language]
    other = "zh-cn" if language == "en" else "en"
    alternate = page_url(other, page["filename"])
    canonical = f"{BASE_PATH}/" if root_copy else page["url"]
    asset_base = f"{BASE_PATH}/assets"
    sidebar_html = sidebar(language, pages, page["filename"])
    navigation = page_navigation(language, pages, index)
    toc_html = article_toc(page["content"], labels["in_this_article"])
    search_json = json.dumps(search_index, ensure_ascii=False).replace("</", "<\\/")

    return f"""<!doctype html>
<html lang="{language}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script>
    (() => {{
      const param = new URLSearchParams(window.location.search).get("scoutTheme");
      const theme =
        param || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
      document.documentElement.setAttribute("data-theme", theme);
    }})();
  </script>
  <style>
{THEME}
  </style>
  <title>{html.escape(page["title"])} · Let's Learn KARS</title>
  <meta name="description" content="{html.escape(labels["description"])}">
  <link rel="canonical" href="{canonical}">
  <link rel="stylesheet" href="{asset_base}/style.css">
</head>
<body>
  <header class="site-header">
    <div class="header-inner">
      <div class="header-left">
        <button class="icon-button menu-toggle" id="menu-toggle" aria-label="{labels["menu"]}">☰</button>
        <a class="brand" href="{BASE_PATH}/{language}/">
          <img class="brand-logo" src="https://github.com/Azure/kars/raw/main/docs/assets/logo.png"
               alt="KARS logo" width="32" height="32">
          <span><strong>Let's Learn KARS</strong><small>Agent Reference Stack for Kubernetes</small></span>
        </a>
      </div>
      <div class="header-actions">
        <div class="search-shell">
          <span aria-hidden="true">⌕</span>
          <input id="search-input" type="search" placeholder="{labels["search"]}" autocomplete="off">
          <div class="search-results" id="search-results" data-empty="{labels["no_results"]}"></div>
        </div>
        <a class="header-button" id="language-toggle" href="{alternate}">{labels["switch"]}</a>
        <button class="icon-button" id="theme-toggle" aria-label="{labels["theme"]}">◐</button>
        <a class="icon-button github-link" href="https://github.com/kinfey/LetsLearnMicrosoftKars"
           aria-label="{labels["github"]}" target="_blank" rel="noopener noreferrer">
          <svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
        </a>
      </div>
    </div>
  </header>
  <div class="sidebar-overlay" id="sidebar-overlay"></div>
  <aside class="sidebar" id="sidebar">{sidebar_html}</aside>
  <div class="docs-layout">
    <div class="content-shell">
      <main class="main-content" id="main">
        <nav class="breadcrumbs" aria-label="Breadcrumb">
          <a href="{BASE_PATH}/{language}/">{html.escape(labels["documentation"])}</a>
          <span>/</span>
          <span>{html.escape(page["title"])}</span>
        </nav>
        <article class="article">{page["content"]}</article>
        {navigation}
        <footer class="site-footer">
          <span>MIT License · KARS v0.1.25 tutorial</span>
          <a href="https://github.com/Azure/kars" target="_blank" rel="noopener noreferrer">Azure/KARS ↗</a>
        </footer>
      </main>
      {toc_html}
    </div>
  </div>
  <button class="scroll-top" id="scroll-top" aria-label="Scroll to top">↑</button>
  <script>window.SEARCH_INDEX = {search_json};</script>
  <script src="{asset_base}/main.js"></script>
</body>
</html>
"""


def build() -> None:
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    (OUTPUT / "assets").mkdir(parents=True)
    shutil.copy2(ASSETS / "style.css", OUTPUT / "assets" / "style.css")
    shutil.copy2(ASSETS / "main.js", OUTPUT / "assets" / "main.js")
    (OUTPUT / ".nojekyll").touch()

    language_pages: dict[str, list[dict]] = {}
    all_search: list[dict] = []

    for language in LANGUAGES:
        pages = []
        for filename in CHAPTER_FILES:
            source = (DOCS / language / filename).read_text(encoding="utf-8")
            rendered = render_markdown(source, language)
            page = {
                "filename": filename,
                "title": first_heading(source),
                "content": rendered,
                "url": page_url(language, filename),
                "language": language,
            }
            pages.append(page)
            all_search.append(
                {
                    "title": page["title"],
                    "url": page["url"],
                    "language": language,
                    "text": plain_text(rendered)[:5000],
                }
            )
        language_pages[language] = pages

    for language, pages in language_pages.items():
        for index, page in enumerate(pages):
            slug = slug_for(page["filename"])
            destination = OUTPUT / language / slug if slug else OUTPUT / language
            destination.mkdir(parents=True, exist_ok=True)
            document = html_document(language, page, pages, index, all_search)
            (destination / "index.html").write_text(document, encoding="utf-8")

    root_page = language_pages["en"][0]
    root_document = html_document(
        "en", root_page, language_pages["en"], 0, all_search, root_copy=True
    )
    (OUTPUT / "index.html").write_text(root_document, encoding="utf-8")

    print(f"Built {sum(len(pages) for pages in language_pages.values()) + 1} pages")


if __name__ == "__main__":
    build()
