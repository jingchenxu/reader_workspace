(function () {
  let book = null;
  let rendition = null;
  let currentFlow = "scrolled";
  let fontSize = 18;
  let lineHeight = 1.6;
  let fontFamily = "system";
  let readingTheme = "paper";
  let selectedText = "";
  let selectedCfi = "";
  let locationsReady = false;
  let autoTurning = false;
  const viewer = document.getElementById("viewer");
  const tocPanel = document.getElementById("toc-panel");
  const tocList = document.getElementById("toc-list");
  const searchPanel = document.getElementById("search-panel");
  const searchInput = document.getElementById("search-input");
  const searchResults = document.getElementById("search-results");
  const searchStatus = document.getElementById("search-status");
  const selectionMenu = document.getElementById("selection-menu");
  let lastChromeToggleAt = 0;

  function post(type, payload = {}) {
    if (window.ReaderBridge && window.ReaderBridge.postMessage) {
      window.ReaderBridge.postMessage(JSON.stringify({ type, ...payload }));
    }
  }

  function isMiddlePoint(x, y, width, height) {
    return x > width * 0.25 && x < width * 0.75 && y > height * 0.25 && y < height * 0.75;
  }

  function shouldIgnoreChromeToggle(target) {
    return Boolean(
      target &&
      target.closest &&
      target.closest("a, button, input, textarea, select, label")
    );
  }

  function registerMiddleTapToggle(target, getSize, getSelection) {
    let startX = 0;
    let startY = 0;
    let moved = false;
    target.addEventListener("touchstart", (event) => {
      if (!event.touches || !event.touches.length) return;
      startX = event.touches[0].clientX;
      startY = event.touches[0].clientY;
      moved = false;
    }, { capture: true, passive: true });

    target.addEventListener("touchmove", (event) => {
      if (!event.touches || !event.touches.length) return;
      const dx = Math.abs(event.touches[0].clientX - startX);
      const dy = Math.abs(event.touches[0].clientY - startY);
      if (dx > 12 || dy > 12) moved = true;
    }, { capture: true, passive: true });

    target.addEventListener("touchend", (event) => {
      if (moved || shouldIgnoreChromeToggle(event.target)) return;
      const selection = getSelection ? getSelection() : "";
      if (selection && selection.trim()) return;
      const touch = event.changedTouches && event.changedTouches.length ? event.changedTouches[0] : null;
      if (!touch) return;
      const size = getSize();
      if (isMiddlePoint(touch.clientX, touch.clientY, size.width, size.height)) {
        lastChromeToggleAt = Date.now();
        post("toggleChrome");
      }
    }, { capture: true, passive: true });

    target.addEventListener("click", (event) => {
      if (Date.now() - lastChromeToggleAt < 350 || shouldIgnoreChromeToggle(event.target)) return;
      const selection = getSelection ? getSelection() : "";
      if (selection && selection.trim()) return;
      const size = getSize();
      if (isMiddlePoint(event.clientX, event.clientY, size.width, size.height)) {
        lastChromeToggleAt = Date.now();
        post("toggleChrome");
      }
    }, true);
  }

  function base64ToArrayBuffer(base64) {
    const binary = window.atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
  }

  const readingThemes = {
    paper: { bg: "#fffdf9", fg: "#1f2937", panel: "#ffffff", line: "#e5e7eb", accent: "#667eea" },
    cream: { bg: "#f7f4e8", fg: "#2f2a22", panel: "#fffaf0", line: "#e7dcc4", accent: "#8a6f3d" },
    green: { bg: "#dceec8", fg: "#1f3324", panel: "#edf7df", line: "#bfd6aa", accent: "#4f7f43" },
    gray: { bg: "#666666", fg: "#f2f2f2", panel: "#575757", line: "#777777", accent: "#d5d5d5" },
    dark: { bg: "#111827", fg: "#f3f4f6", panel: "#1f2937", line: "#374151", accent: "#93c5fd" },
  };

  function activeTheme() {
    return readingThemes[readingTheme] || readingThemes.paper;
  }

  function themeCss() {
    const theme = activeTheme();
    const family = resolveFontFamily();
    return {
      html: {
        background: theme.bg,
      },
      body: {
        "font-size": `${fontSize}px`,
        "line-height": `${lineHeight}`,
        color: theme.fg,
        background: theme.bg,
        "font-family": family,
      },
      p: {
        "line-height": `${lineHeight}`,
      },
      a: {
        color: "#667eea",
      },
      "::selection": {
        background: "#facc15",
        color: "#111827",
      },
    };
  }

  function resolveFontFamily() {
    const fonts = {
      system: "system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      serif: "Georgia, 'Times New Roman', 'Songti SC', SimSun, serif",
      sans: "Arial, 'PingFang SC', 'Microsoft YaHei', sans-serif",
      kai: "'Kaiti SC', KaiTi, STKaiti, serif",
    };
    return fonts[fontFamily] || fonts.system;
  }

  function applyTheme() {
    if (!rendition) return;
    const theme = activeTheme();
    document.body.classList.toggle("dark", readingTheme === "dark");
    document.documentElement.style.setProperty("--bg", theme.bg);
    document.documentElement.style.setProperty("--fg", theme.fg);
    document.documentElement.style.setProperty("--panel", theme.panel);
    document.documentElement.style.setProperty("--line", theme.line);
    document.documentElement.style.setProperty("--accent", theme.accent);
    rendition.themes.default(themeCss());
    rendition.themes.select("default");
    if (rendition.getContents) {
      rendition.getContents().forEach((contents) => applyContentTheme(contents));
    }
  }

  function applyContentTheme(contents) {
    const theme = activeTheme();
    const doc = contents && contents.document;
    if (!doc) return;
    const html = doc.documentElement;
    const body = doc.body;
    if (html) html.style.backgroundColor = theme.bg;
    if (body) {
      body.style.backgroundColor = theme.bg;
      body.style.color = theme.fg;
      body.style.fontSize = `${fontSize}px`;
      body.style.lineHeight = `${lineHeight}`;
    }
    upsertReaderStyle(doc, theme);
  }

  function upsertReaderStyle(doc, theme) {
    let style = doc.getElementById("epub-mobile-reader-style");
    if (!style) {
      style = doc.createElement("style");
      style.id = "epub-mobile-reader-style";
      doc.head.appendChild(style);
    }
    const family = resolveFontFamily();
    style.textContent = `
      html, body {
        background: ${theme.bg} !important;
        color: ${theme.fg} !important;
      }
      body, body * {
        font-family: ${family} !important;
      }
      body {
        font-size: ${fontSize}px !important;
        line-height: ${lineHeight} !important;
      }
      p, div, section, article, blockquote, li {
        line-height: ${lineHeight} !important;
      }
      p {
        margin-top: ${Math.max(0.4, lineHeight - 1.1)}em !important;
        margin-bottom: ${Math.max(0.4, lineHeight - 1.1)}em !important;
      }
    `;
  }

  function createRendition(targetCfi) {
    viewer.innerHTML = "";
    rendition = book.renderTo("viewer", {
      width: "100%",
      height: "100%",
      flow: currentFlow === "scrolled" ? "scrolled-doc" : "paginated",
      spread: "none",
      minSpreadWidth: 0,
    });
    rendition.hooks.content.register((contents) => {
      applyTheme();
      const doc = contents.document;
      doc.addEventListener("selectionchange", () => {
        const selection = contents.window.getSelection();
        selectedText = selection ? selection.toString().trim() : "";
      });
      doc.addEventListener("contextmenu", (event) => {
        const selection = contents.window.getSelection();
        selectedText = selection ? selection.toString().trim() : "";
        if (!selectedText) return;
        event.preventDefault();
        try {
          selectedCfi = contents.cfiFromRange(selection.getRangeAt(0));
        } catch (_) {
          selectedCfi = "";
        }
        showSelectionMenu(event.clientX, event.clientY);
      });
      registerMiddleTapToggle(
        doc,
        () => ({
          width: contents.window.innerWidth || doc.documentElement.clientWidth || 0,
          height: contents.window.innerHeight || doc.documentElement.clientHeight || 0,
        }),
        () => {
          const selection = contents.window.getSelection();
          return selection ? selection.toString() : "";
        }
      );
      registerScrollAutoTurn(contents);
    });
    rendition.on("relocated", (location) => {
      const cfi = location && location.start ? location.start.cfi : null;
      const progress = resolveProgress(location);
      post("progress", { cfi, progress });
    });
    applyTheme();
    return rendition.display(targetCfi || undefined);
  }

  function registerScrollAutoTurn(contents) {
    if (currentFlow !== "scrolled") return;

    const managerContainer = rendition && rendition.manager
      ? rendition.manager.container
      : null;
    const documentScroller = contents.document.scrollingElement || contents.document.documentElement;
    const scrollTarget = managerContainer || documentScroller;
    if (!scrollTarget) return;

    const doc = contents.document;
    if (doc.documentElement) doc.documentElement.style.touchAction = "pan-x pinch-zoom";
    if (doc.body) doc.body.style.touchAction = "pan-x pinch-zoom";
    if (managerContainer) managerContainer.style.touchAction = "pan-x pinch-zoom";

    let startTouchX = null;
    let startTouchY = null;
    let lastTouchY = null;
    let lastMoveAt = 0;
    let gesturePull = 0;
    let scrollVelocity = 0;
    let gestureStartedAtBottom = false;
    let gestureStartedAtTop = false;
    let inertiaFrame = null;
    let wheelPull = 0;
    const edgeTolerance = 18;
    const shortChapterPullThreshold = 48;
    const edgePullThreshold = 72;
    const scrollScale = 0.42;
    const maxInertiaPerFrame = 14;

    const cancelInertia = () => {
      if (inertiaFrame !== null) {
        window.cancelAnimationFrame(inertiaFrame);
        inertiaFrame = null;
      }
    };
    const edgeState = () => {
      const scrollTop = scrollTarget.scrollTop || 0;
      const clientHeight = scrollTarget.clientHeight || contents.window.innerHeight || 0;
      const scrollHeight = scrollTarget.scrollHeight || 0;
      return {
        scrollTop,
        clientHeight,
        scrollHeight,
        shortChapter: scrollHeight <= clientHeight + edgeTolerance,
        nearBottom: scrollTop + clientHeight >= scrollHeight - edgeTolerance,
        nearTop: scrollTop <= edgeTolerance,
      };
    };
    const scrollBy = (delta) => {
      const maxScroll = Math.max(0, scrollTarget.scrollHeight - scrollTarget.clientHeight);
      const nextTop = Math.max(0, Math.min(maxScroll, (scrollTarget.scrollTop || 0) + delta));
      scrollTarget.scrollTop = nextTop;
      return nextTop;
    };

    const startInertia = () => {
      cancelInertia();
      let velocity = Math.max(-maxInertiaPerFrame, Math.min(maxInertiaPerFrame, scrollVelocity));
      const step = () => {
        if (autoTurning || currentFlow !== "scrolled" || Math.abs(velocity) < 0.35) {
          inertiaFrame = null;
          return;
        }
        const before = scrollTarget.scrollTop || 0;
        const after = scrollBy(velocity);
        if (Math.abs(after - before) < 0.1) {
          inertiaFrame = null;
          return;
        }
        velocity *= 0.86;
        inertiaFrame = window.requestAnimationFrame(step);
      };
      if (Math.abs(velocity) >= 0.35) {
        inertiaFrame = window.requestAnimationFrame(step);
      }
    };

    const handleWheel = (event) => {
      if (currentFlow !== "scrolled" || autoTurning) return;
      const rawDelta = event.deltaY || 0;
      if (!rawDelta) return;
      event.preventDefault();
      cancelInertia();
      const before = edgeState();
      scrollBy(Math.max(-80, Math.min(80, rawDelta * scrollScale)));
      const after = edgeState();
      if (after.shortChapter || (rawDelta > 0 && before.nearBottom) || (rawDelta < 0 && before.nearTop)) {
        wheelPull += rawDelta;
      } else {
        wheelPull = 0;
      }
      if (wheelPull >= edgePullThreshold) {
        wheelPull = 0;
        turnSpine("next");
      } else if (wheelPull <= -edgePullThreshold) {
        wheelPull = 0;
        turnSpine("prev");
      }
    };

    const handleTouchStart = (event) => {
      if (!event.touches || !event.touches.length) return;
      cancelInertia();
      const touch = event.touches[0];
      startTouchX = touch.clientX;
      startTouchY = touch.clientY;
      lastTouchY = touch.clientY;
      lastMoveAt = performance.now();
      gesturePull = 0;
      scrollVelocity = 0;
      const edge = edgeState();
      gestureStartedAtBottom = edge.nearBottom;
      gestureStartedAtTop = edge.nearTop;
    };

    const handleTouchMove = (event) => {
      if (lastTouchY === null || !event.touches || !event.touches.length) return;
      const touch = event.touches[0];
      const currentY = touch.clientY;
      const inputDelta = lastTouchY - currentY;
      const totalX = Math.abs(touch.clientX - startTouchX);
      const totalY = Math.abs(currentY - startTouchY);
      lastTouchY = currentY;
      if (totalY < 6 || totalX > totalY) return;

      event.preventDefault();
      gesturePull += inputDelta;
      const now = performance.now();
      const elapsed = Math.max(8, now - lastMoveAt);
      const manualDelta = inputDelta * scrollScale;
      scrollBy(manualDelta);
      const instantVelocity = (manualDelta / elapsed) * 16;
      scrollVelocity = scrollVelocity * 0.72 + instantVelocity * 0.28;
      lastMoveAt = now;
    };

    const finishTouch = () => {
      const edge = edgeState();
      let changedChapter = false;
      if (edge.shortChapter && gesturePull >= shortChapterPullThreshold) {
        turnSpine("next");
        changedChapter = true;
      } else if (edge.shortChapter && gesturePull <= -shortChapterPullThreshold) {
        turnSpine("prev");
        changedChapter = true;
      } else if (gestureStartedAtBottom && edge.nearBottom && gesturePull >= edgePullThreshold) {
        turnSpine("next");
        changedChapter = true;
      } else if (gestureStartedAtTop && edge.nearTop && gesturePull <= -edgePullThreshold) {
        turnSpine("prev");
        changedChapter = true;
      }

      if (!changedChapter) startInertia();
      startTouchX = null;
      startTouchY = null;
      lastTouchY = null;
      gesturePull = 0;
      gestureStartedAtBottom = false;
      gestureStartedAtTop = false;
    };

    const bindGestureTarget = (target) => {
      target.addEventListener("wheel", handleWheel, { capture: true, passive: false });
      target.addEventListener("touchstart", handleTouchStart, { capture: true, passive: true });
      target.addEventListener("touchmove", handleTouchMove, { capture: true, passive: false });
      target.addEventListener("touchend", finishTouch, { capture: true, passive: true });
      target.addEventListener("touchcancel", finishTouch, { capture: true, passive: true });
    };

    bindGestureTarget(doc);
    if (managerContainer && !managerContainer.__epubMobileOuterTouchBound) {
      managerContainer.__epubMobileOuterTouchBound = true;
      bindGestureTarget(managerContainer);
    }
  }

  async function turnSpine(direction) {
    if (!rendition || autoTurning) return;
    autoTurning = true;
    try {
      if (direction === "prev") {
        await rendition.prev();
      } else {
        await rendition.next();
      }
    } catch (_) {
      // Ignore attempts to move past the beginning or end of the book.
    } finally {
      setTimeout(() => {
        autoTurning = false;
      }, 450);
    }
  }

  function resolveProgress(location) {
    if (!location) return 0;
    if (typeof location.percentage === "number") return location.percentage * 100;
    if (location.start && typeof location.start.percentage === "number") {
      return location.start.percentage * 100;
    }
    if (book && book.locations && location.start && location.start.cfi) {
      const percentage = book.locations.percentageFromCfi(location.start.cfi);
      if (typeof percentage === "number") return percentage * 100;
    }
    if (book && book.spine && location.start && typeof location.start.index === "number") {
      const items = book.spine.items || [];
      if (items.length > 0) return (location.start.index / items.length) * 100;
    }
    return 0;
  }

  async function generateLocationsInBackground() {
    if (!book || locationsReady) return;
    try {
      await new Promise((resolve) => setTimeout(resolve, 150));
      await book.locations.generate(700);
      locationsReady = true;
      if (rendition) {
        const location = rendition.currentLocation();
        const cfi = location && location.start ? location.start.cfi : null;
        post("progress", { cfi, progress: resolveProgress(location) });
      }
    } catch (_) {
      locationsReady = false;
    }
  }

  function buildToc() {
    tocList.innerHTML = "";
    const toc = (book.navigation && book.navigation.toc) || [];
    if (!toc.length) {
      tocList.innerHTML = "<p>暂无目录</p>";
      return;
    }
    toc.forEach((item) => {
      const button = document.createElement("button");
      button.className = "toc-item";
      button.textContent = item.label || item.href;
      button.addEventListener("click", () => {
        rendition.display(item.href);
        tocPanel.classList.remove("open");
      });
      tocList.appendChild(button);
    });
  }

  function showSelectionMenu(x, y) {
    selectionMenu.style.left = `${Math.max(8, Math.min(x, window.innerWidth - 150))}px`;
    selectionMenu.style.top = `${Math.max(8, Math.min(y, window.innerHeight - 64))}px`;
    selectionMenu.classList.add("open");
  }

  async function runSearch() {
    const query = searchInput.value.trim();
    searchResults.innerHTML = "";
    if (!query || !book) return;
    searchStatus.textContent = "搜索中...";
    const lowerQuery = query.toLowerCase();
    const results = [];
    const spineItems = book.spine && book.spine.items ? book.spine.items : [];
    for (let i = 0; i < spineItems.length; i += 1) {
      const item = spineItems[i];
      try {
        const doc = await book.load(item.href);
        const text = (doc && doc.documentElement && doc.documentElement.textContent) || "";
        const lowerText = text.toLowerCase();
        let position = 0;
        while ((position = lowerText.indexOf(lowerQuery, position)) !== -1) {
          const start = Math.max(0, position - 48);
          const end = Math.min(text.length, position + query.length + 80);
          results.push({
            href: item.href,
            chapter: item.label || `第 ${i + 1} 章`,
            excerpt: text.slice(start, end).trim(),
          });
          position += query.length;
          if (results.length >= 80) break;
        }
      } catch (_) {
        // Ignore broken spine entries.
      }
      if (results.length >= 80) break;
    }
    searchStatus.textContent = results.length ? `找到 ${results.length} 个结果` : "没有匹配结果";
    results.forEach((result) => {
      const button = document.createElement("button");
      button.className = "search-item";
      button.innerHTML = `<strong>${escapeHtml(result.chapter)}</strong><br>${highlight(
        result.excerpt,
        query
      )}`;
      button.addEventListener("click", () => {
        rendition.display(result.href);
        searchPanel.classList.remove("open");
      });
      searchResults.appendChild(button);
    });
  }
  function escapeHtml(value) {
    return value.replace(/[&<>"']/g, (char) => {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char];
    });
  }

  function highlight(text, query) {
    const safeText = escapeHtml(text);
    const safeQuery = escapeHtml(query).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return safeText.replace(new RegExp(`(${safeQuery})`, "gi"), "<mark>$1</mark>");
  }

  document.getElementById("toc-close").addEventListener("click", () => {
    tocPanel.classList.remove("open");
  });
  document.getElementById("search-close").addEventListener("click", () => {
    searchPanel.classList.remove("open");
  });
  document.getElementById("search-run").addEventListener("click", runSearch);
  searchInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") runSearch();
  });
  document.getElementById("selection-bookmark").addEventListener("click", () => {
    selectionMenu.classList.remove("open");
    post("bookmark", { cfi: selectedCfi });
  });
  document.getElementById("selection-annotation").addEventListener("click", () => {
    selectionMenu.classList.remove("open");
    const note = window.prompt("输入批注内容");
    if (note) post("annotation", { cfi: selectedCfi, selectedText, note });
  });
  document.addEventListener("click", () => selectionMenu.classList.remove("open"));
  registerMiddleTapToggle(
    viewer,
    () => ({ width: window.innerWidth, height: window.innerHeight }),
    () => ""
  );

  window.reader = {
    async openBook(payload) {
      try {
        if (rendition) rendition.destroy();
        locationsReady = false;
        book = ePub(base64ToArrayBuffer(payload.base64));
        await book.ready;
        await createRendition(payload.cfi);
        buildToc();
        post("ready");
        generateLocationsInBackground();
      } catch (error) {
        post("error", { message: error && error.message ? error.message : String(error) });
      }
    },
    next() {
      turnSpine("next");
    },
    prev() {
      turnSpine("prev");
    },
    display(cfi) {
      if (rendition) rendition.display(cfi);
    },
    toggleToc() {
      tocPanel.classList.toggle("open");
    },
    toggleSearch() {
      searchPanel.classList.toggle("open");
      if (searchPanel.classList.contains("open")) searchInput.focus();
    },
    setDarkMode(value) {
      readingTheme = value ? "dark" : "paper";
      applyTheme();
    },
    setTheme(value) {
      readingTheme = readingThemes[value] ? value : "paper";
      applyTheme();
    },
    changeFontSize(delta) {
      fontSize = Math.max(12, Math.min(32, fontSize + delta));
      applyTheme();
    },
    changeLineHeight(delta) {
      lineHeight = Math.max(1.2, Math.min(2.2, lineHeight + delta));
      applyTheme();
    },
    setFontFamily(value) {
      fontFamily = value || "system";
      applyTheme();
    },
    setFlow(flow) {
      currentFlow = flow === "paginated" ? "paginated" : "scrolled";
      const location = rendition ? rendition.currentLocation() : null;
      const cfi = location && location.start ? location.start.cfi : undefined;
      if (rendition) rendition.destroy();
      createRendition(cfi);
    },
  };
})();
