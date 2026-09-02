(() => {
  const root = document.documentElement;
  const themeToggle = document.querySelector("#theme-toggle");
  const menuToggle = document.querySelector("#menu-toggle");
  const sidebar = document.querySelector("#sidebar");
  const overlay = document.querySelector("#sidebar-overlay");
  const searchInput = document.querySelector("#search-input");
  const searchResults = document.querySelector("#search-results");
  const scrollTop = document.querySelector("#scroll-top");

  themeToggle?.addEventListener("click", () => {
    const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    const url = new URL(window.location.href);
    url.searchParams.set("scoutTheme", next);
    window.history.replaceState({}, "", url);
  });

  const closeSidebar = () => {
    sidebar?.classList.remove("open");
    overlay?.classList.remove("visible");
  };

  menuToggle?.addEventListener("click", () => {
    sidebar?.classList.toggle("open");
    overlay?.classList.toggle("visible");
  });
  overlay?.addEventListener("click", closeSidebar);

  document.querySelectorAll("pre").forEach((pre) => {
    const button = document.createElement("button");
    button.className = "copy-button";
    button.type = "button";
    button.textContent = "Copy";
    button.addEventListener("click", async () => {
      await navigator.clipboard.writeText(pre.querySelector("code")?.innerText || "");
      button.textContent = "Copied";
      window.setTimeout(() => {
        button.textContent = "Copy";
      }, 1400);
    });
    pre.appendChild(button);
  });

  searchInput?.addEventListener("input", () => {
    const query = searchInput.value.trim().toLocaleLowerCase();
    if (!query) {
      searchResults.classList.remove("visible");
      searchResults.replaceChildren();
      return;
    }

    const language = document.documentElement.lang;
    const matches = (window.SEARCH_INDEX || [])
      .filter((item) => item.language === language)
      .filter((item) => `${item.title} ${item.text}`.toLocaleLowerCase().includes(query))
      .slice(0, 8);

    searchResults.replaceChildren();
    if (!matches.length) {
      const empty = document.createElement("div");
      empty.className = "search-empty";
      empty.textContent = searchResults.dataset.empty;
      searchResults.appendChild(empty);
    } else {
      matches.forEach((item) => {
        const link = document.createElement("a");
        link.href = item.url;
        link.textContent = item.title;
        searchResults.appendChild(link);
      });
    }
    searchResults.classList.add("visible");
  });

  document.addEventListener("click", (event) => {
    if (!event.target.closest(".search-shell")) {
      searchResults?.classList.remove("visible");
    }
  });

  window.addEventListener("scroll", () => {
    scrollTop?.classList.toggle("visible", window.scrollY > 480);
  });
  scrollTop?.addEventListener("click", () => {
    window.scrollTo({ top: 0, behavior: "smooth" });
  });

  const tocLinks = [...document.querySelectorAll(".article-toc-link")];
  const headings = tocLinks
    .map((link) => document.querySelector(link.getAttribute("href")))
    .filter(Boolean);
  if (headings.length) {
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
        if (!visible) return;
        tocLinks.forEach((link) => {
          link.classList.toggle("active", link.getAttribute("href") === `#${visible.target.id}`);
        });
      },
      { rootMargin: "-72px 0px -72% 0px", threshold: 0 }
    );
    headings.forEach((heading) => observer.observe(heading));
  }
})();
