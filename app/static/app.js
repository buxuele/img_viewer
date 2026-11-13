const MIN_ZOOM = 10;
const MAX_ZOOM = 800;
const ZOOM_STEPS = [10, 15, 25, 33, 50, 66, 75, 100, 125, 150, 200, 250, 300, 400, 500, 600, 800];
const RAW_PREVIEW_ONLY = new Set(["heic", "heif", "tif", "tiff"]);

const state = {
  settings: null,
  recent: [],
  folder: null,
  images: [],
  index: 0,
  page: 1,
  zoom: 100,
  mode: "fit",
  rotation: 0,
  panX: 0,
  panY: 0,
  loadToken: 0,
  toastTimer: null,
  slideTimer: null,
  dragging: null,
};

const el = (id) => document.getElementById(id);

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!response.ok) {
    let message = "操作没有完成";
    try {
      const data = await response.json();
      if (data && data.detail) message = data.detail;
    } catch (error) {
      message = `操作没有完成（${response.status}）`;
    }
    throw new Error(message);
  }
  return response.json();
}

function toast(message) {
  const box = el("toast");
  box.textContent = message;
  box.hidden = false;
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => { box.hidden = true; }, 3200);
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} 字节`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/* 图片库 */

function renderRecent() {
  const box = el("recent");
  box.innerHTML = "";
  for (const entry of state.recent) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "recent-chip";
    chip.title = entry.path;
    const label = document.createElement("span");
    label.textContent = entry.name + (entry.exists ? "" : "（已不存在）");
    chip.append(label);
    const remove = document.createElement("span");
    remove.className = "chip-remove";
    remove.textContent = "×";
    remove.title = "从最近列表中移除";
    remove.addEventListener("click", async (event) => {
      event.stopPropagation();
      state.recent = (await api(`/api/recent?path=${encodeURIComponent(entry.path)}`, { method: "DELETE" })).recent;
      renderRecent();
    });
    chip.append(remove);
    chip.addEventListener("click", () => {
      if (!entry.exists) { toast("这个文件夹已经不存在"); return; }
      openFolder(entry.path);
    });
    box.append(chip);
  }
}

function renderGrid() {
  const grid = el("grid");
  const empty = el("grid-empty");
  grid.innerHTML = "";
  const total = state.images.length;
  if (!total) {
    empty.hidden = false;
    renderPager();
    return;
  }
  empty.hidden = true;
  const size = state.settings.grid_page_size || 30;
  const start = (state.page - 1) * size;
  const slice = state.images.slice(start, start + size);
  for (const image of slice) {
    const absolute = state.images.indexOf(image);
    const tile = document.createElement("button");
    tile.type = "button";
    tile.className = "tile";
    tile.title = image.name;
    const frame = document.createElement("div");
    frame.className = "tile-frame";
    const thumb = document.createElement("img");
    thumb.loading = "lazy";
    thumb.alt = image.name;
    thumb.src = `/api/preview?path=${encodeURIComponent(image.path)}&size=360`;
    frame.append(thumb);
    const name = document.createElement("div");
    name.className = "tile-name";
    name.textContent = image.name;
    const meta = document.createElement("div");
    meta.className = "tile-meta";
    meta.textContent = formatSize(image.size);
    tile.append(frame, name, meta);
    tile.addEventListener("click", () => openViewer(absolute));
    grid.append(tile);
  }
  renderPager();
}

function pageNumbers(current, total) {
  if (total <= 7) return Array.from({ length: total }, (_, index) => index + 1);
  const pages = new Set([1, total, current, current - 1, current + 1]);
  const list = [...pages].filter((page) => page >= 1 && page <= total).sort((a, b) => a - b);
  const result = [];
  let previous = 0;
  for (const page of list) {
    if (previous && page - previous > 1) result.push("...");
    result.push(page);
    previous = page;
  }
  return result;
}

function renderPager() {
  const pager = el("pager");
  pager.innerHTML = "";
  const size = (state.settings && state.settings.grid_page_size) || 30;
  const totalPages = Math.max(1, Math.ceil(state.images.length / size));
  if (state.images.length <= size) {
    if (state.images.length) {
      const total = document.createElement("span");
      total.className = "page-total";
      total.textContent = `共 ${state.images.length} 张`;
      pager.append(total);
    }
    return;
  }
  const makeButton = (text, page, disabled) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "page-button";
    button.textContent = text;
    button.disabled = disabled;
    if (page === state.page) button.setAttribute("aria-current", "page");
    if (!disabled && page !== state.page) {
      button.addEventListener("click", () => {
        state.page = page;
        renderGrid();
        el("grid").scrollTop = 0;
      });
    }
    return button;
  };
  pager.append(makeButton("上一页", state.page - 1, state.page === 1));
  for (const page of pageNumbers(state.page, totalPages)) {
    if (page === "...") {
      const dots = document.createElement("span");
      dots.textContent = "…";
      dots.className = "page-total";
      pager.append(dots);
    } else {
      pager.append(makeButton(String(page), page, false));
    }
  }
  pager.append(makeButton("下一页", state.page + 1, state.page === totalPages));
  const total = document.createElement("span");
  total.className = "page-total";
  total.textContent = `共 ${state.images.length} 张 · 第 ${state.page} / ${totalPages} 页`;
  pager.append(total);
}

async function openFolder(path) {
  try {
    const query = path ? `?path=${encodeURIComponent(path)}` : "";
    const data = await api(`/api/folders${query}`);
    state.folder = data;
    state.images = data.images;
    state.page = 1;
    el("path-input").value = data.path;
    renderGrid();
    state.recent = (await api("/api/recent")).recent;
    renderRecent();
  } catch (error) {
    toast(error.message);
  }
}

async function pickFolder() {
  try {
    const data = await api("/api/pick-folder", { method: "POST" });
    await openFolder(data.path);
  } catch (error) {
    toast(error.message);
  }
}

/* 查看器 */

function currentImage() {
  return state.images[state.index] || null;
}

function naturalSize() {
  const photo = el("photo");
  return { width: photo.naturalWidth, height: photo.naturalHeight };
}

function stageBox() {
  const rect = el("stage").getBoundingClientRect();
  return { width: Math.max(120, rect.width - 32), height: Math.max(120, rect.height - 24) };
}

function displayedSize() {
  const { width, height } = naturalSize();
  const ratio = state.zoom / 100;
  const scaled = { width: width * ratio, height: height * ratio };
  return state.rotation % 180 !== 0
    ? { width: scaled.height, height: scaled.width }
    : scaled;
}

function canPan() {
  const size = displayedSize();
  const stage = el("stage").getBoundingClientRect();
  return size.width > stage.width + 1 || size.height > stage.height + 1;
}

function fitZoom() {
  const { width, height } = naturalSize();
  if (!width || !height) return 100;
  const swapped = state.rotation % 180 !== 0;
  const contentWidth = swapped ? height : width;
  const contentHeight = swapped ? width : height;
  const box = stageBox();
  return Math.min(box.width / contentWidth, box.height / contentHeight, 1) * 100;
}

function clampPan() {
  const stage = el("stage").getBoundingClientRect();
  const size = displayedSize();
  const maxX = Math.max(0, (size.width - stage.width) / 2);
  const maxY = Math.max(0, (size.height - stage.height) / 2);
  state.panX = Math.min(maxX, Math.max(-maxX, state.panX));
  state.panY = Math.min(maxY, Math.max(-maxY, state.panY));
}

function applyZoom() {
  const photo = el("photo");
  const { width, height } = naturalSize();
  if (!width || !height) return;
  clampPan();
  const ratio = state.zoom / 100;
  photo.style.width = `${width * ratio}px`;
  photo.style.height = `${height * ratio}px`;
  photo.style.transform = `translate(${state.panX}px, ${state.panY}px) rotate(${state.rotation}deg)`;
  el("canvas").classList.toggle("pannable", canPan());
  updateZoomUi();
}

function updateZoomUi() {
  el("zoom-label").textContent = `${Math.round(state.zoom)}%`;
  const slider = el("zoom-slider");
  const percent = Math.log(state.zoom / MIN_ZOOM) / Math.log(MAX_ZOOM / MIN_ZOOM) * 100;
  slider.value = String(Math.max(0, Math.min(100, percent)));
  el("zoom-out").disabled = state.zoom <= MIN_ZOOM;
  el("zoom-in").disabled = state.zoom >= MAX_ZOOM;
  el("fit-button").textContent = state.mode === "fit" ? "实际大小" : "适应窗口";
}

function fitToWindow() {
  state.mode = "fit";
  state.zoom = fitZoom();
  state.panX = 0;
  state.panY = 0;
  applyZoom();
}

function actualSize() {
  state.mode = "manual";
  state.zoom = 100;
  state.panX = 0;
  state.panY = 0;
  applyZoom();
}

function toggleSize() {
  if (state.mode === "fit") actualSize();
  else fitToWindow();
}

function stepZoom(direction) {
  let target;
  if (direction > 0) target = ZOOM_STEPS.find((step) => step > state.zoom + 0.01) ?? MAX_ZOOM;
  else target = [...ZOOM_STEPS].reverse().find((step) => step < state.zoom - 0.01) ?? MIN_ZOOM;
  state.mode = "manual";
  state.zoom = target;
  applyZoom();
}

function zoomAt(target, clientX, clientY) {
  const stage = el("stage").getBoundingClientRect();
  const cursorX = clientX - stage.left - stage.width / 2;
  const cursorY = clientY - stage.top - stage.height / 2;
  const ratio = target / state.zoom;
  state.panX = cursorX - (cursorX - state.panX) * ratio;
  state.panY = cursorY - (cursorY - state.panY) * ratio;
  state.zoom = target;
  state.mode = "manual";
  applyZoom();
}

function updateCaption() {
  const image = currentImage();
  const name = image ? image.name : "";
  el("window-title").textContent = name ? `${name} - 照片查看器` : "照片查看器";
  document.title = el("window-title").textContent;
  el("counter").textContent = state.images.length
    ? `第 ${state.index + 1} 张 / 共 ${state.images.length} 张`
    : "";
  el("prev-button").disabled = state.index <= 0;
  el("next-button").disabled = state.index >= state.images.length - 1;
}

function preloadNeighbours(index) {
  for (const offset of [-1, 1]) {
    const image = state.images[index + offset];
    if (!image) continue;
    const preload = new Image();
    preload.src = `/api/preview?path=${encodeURIComponent(image.path)}&size=1200`;
  }
}

function loadPhoto(index) {
  const image = state.images[index];
  if (!image) return;
  state.index = index;
  state.rotation = image.rotation || 0;
  state.mode = "fit";
  state.panX = 0;
  state.panY = 0;
  updateCaption();
  const token = ++state.loadToken;
  const photo = el("photo");
  photo.hidden = false;
  el("photo-error").hidden = true;
  el("loading").hidden = false;
  let requestedFull = false;

  photo.onload = () => {
    if (token !== state.loadToken) return;
    el("loading").hidden = true;
    fitToWindow();
    preloadNeighbours(index);
    const extension = image.name.split(".").pop().toLowerCase();
    if (requestedFull || RAW_PREVIEW_ONLY.has(extension)) return;
    requestedFull = true;
    const full = new Image();
    full.onload = () => {
      if (token !== state.loadToken) return;
      photo.src = full.src;
    };
    full.src = `/api/image?path=${encodeURIComponent(image.path)}`;
  };
  photo.onerror = () => {
    if (token !== state.loadToken) return;
    el("loading").hidden = true;
    el("photo-error").hidden = false;
  };
  photo.src = `/api/preview?path=${encodeURIComponent(image.path)}&size=2560`;
}

function openViewer(index) {
  if (!state.images.length) return;
  el("library").hidden = true;
  el("viewer").hidden = false;
  loadPhoto(index);
}

function backToLibrary() {
  stopSlideshow();
  state.loadToken += 1;
  el("viewer").hidden = true;
  el("library").hidden = false;
  el("window-title").textContent = "照片查看器";
  document.title = "照片查看器";
  renderGrid();
}

function navigate(offset) {
  const next = state.index + offset;
  if (next < 0 || next >= state.images.length) return;
  loadPhoto(next);
}

async function rotate(delta) {
  const image = currentImage();
  if (!image) return;
  const angle = ((state.rotation + delta) % 360 + 360) % 360;
  try {
    const result = await api("/api/rotation", {
      method: "POST",
      body: JSON.stringify({ path: image.path, angle }),
    });
    image.rotation = result.rotation;
    state.rotation = result.rotation;
    if (state.mode === "fit") fitToWindow();
    else applyZoom();
  } catch (error) {
    toast(error.message);
  }
}

function askDelete() {
  const image = currentImage();
  if (!image) return;
  el("confirm-text").textContent = `要把“${image.name}”放入废纸篓吗？原文件会从当前文件夹移除。`;
  el("confirm-dialog").showModal();
}

async function confirmDelete() {
  const image = currentImage();
  if (!image) return;
  try {
    await api("/api/trash", {
      method: "POST",
      body: JSON.stringify({ path: image.path, confirm: true }),
    });
    state.images.splice(state.index, 1);
    el("confirm-dialog").close();
    if (!state.images.length) {
      backToLibrary();
      toast("文件夹里已经没有图片了");
      return;
    }
    if (state.index >= state.images.length) state.index = state.images.length - 1;
    loadPhoto(state.index);
    toast("已放入废纸篓");
  } catch (error) {
    el("confirm-dialog").close();
    toast(error.message);
  }
}

/* 幻灯片 */

function slideshowPhoto() {
  const image = state.images[state.index];
  return image ? `/api/image?path=${encodeURIComponent(image.path)}` : "";
}

function showSlideshowImage() {
  el("slideshow-photo").src = slideshowPhoto();
  updateCaption();
}

function scheduleSlide() {
  clearTimeout(state.slideTimer);
  const seconds = (state.settings && state.settings.slideshow_interval) || 5;
  state.slideTimer = setTimeout(() => {
    let next = state.index + 1;
    if (next >= state.images.length) {
      if (state.settings && state.settings.slideshow_loop === false) {
        stopSlideshow();
        return;
      }
      next = 0;
    }
    state.index = next;
    showSlideshowImage();
    scheduleSlide();
  }, seconds * 1000);
}

function startSlideshow() {
  if (!state.images.length) return;
  el("slideshow").hidden = false;
  showSlideshowImage();
  document.documentElement.requestFullscreen?.().catch(() => {});
  scheduleSlide();
}

function stopSlideshow() {
  clearTimeout(state.slideTimer);
  state.slideTimer = null;
  el("slideshow").hidden = true;
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  if (!el("viewer").hidden) loadPhoto(state.index);
}

function handleSlideshowKey(event) {
  const key = event.key;
  if (key === "Escape") {
    event.preventDefault();
    stopSlideshow();
  } else if (key === "ArrowLeft" || key === "PageUp") {
    event.preventDefault();
    state.index = Math.max(0, state.index - 1);
    showSlideshowImage();
    scheduleSlide();
  } else if (key === "ArrowRight" || key === "PageDown") {
    event.preventDefault();
    state.index = Math.min(state.images.length - 1, state.index + 1);
    showSlideshowImage();
    scheduleSlide();
  }
}

/* 事件 */

function bindEvents() {
  el("pick-folder").addEventListener("click", pickFolder);
  el("path-open").addEventListener("click", () => openFolder(el("path-input").value.trim()));
  el("path-input").addEventListener("keydown", (event) => {
    if (event.key === "Enter") openFolder(el("path-input").value.trim());
  });
  el("close-button").addEventListener("click", () => {
    if (!el("viewer").hidden) backToLibrary();
    else toast("当前已经是图片库");
  });
  el("fullscreen-button").addEventListener("click", async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await document.documentElement.requestFullscreen();
    } catch (error) {
      toast("这个浏览器不允许全屏");
    }
  });
  el("prev-button").addEventListener("click", () => navigate(-1));
  el("next-button").addEventListener("click", () => navigate(1));
  el("zoom-in").addEventListener("click", () => stepZoom(1));
  el("zoom-out").addEventListener("click", () => stepZoom(-1));
  el("fit-button").addEventListener("click", toggleSize);
  el("rotate-left").addEventListener("click", () => rotate(-90));
  el("rotate-right").addEventListener("click", () => rotate(90));
  el("delete-button").addEventListener("click", askDelete);
  el("confirm-cancel").addEventListener("click", () => el("confirm-dialog").close());
  el("confirm-delete").addEventListener("click", confirmDelete);
  el("zoom-slider").addEventListener("input", (event) => {
    const percent = Number(event.target.value);
    state.mode = "manual";
    state.zoom = MIN_ZOOM * Math.pow(MAX_ZOOM / MIN_ZOOM, percent / 100);
    applyZoom();
  });

  el("stage").addEventListener("wheel", (event) => {
    if (el("viewer").hidden) return;
    if (state.settings && state.settings.wheel_zoom === false) return;
    event.preventDefault();
    const target = event.deltaY < 0
      ? (ZOOM_STEPS.find((step) => step > state.zoom + 0.5) ?? MAX_ZOOM)
      : ([...ZOOM_STEPS].reverse().find((step) => step < state.zoom - 0.5) ?? MIN_ZOOM);
    zoomAt(target, event.clientX, event.clientY);
  }, { passive: false });

  const canvas = el("canvas");
  canvas.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || !canPan()) return;
    state.dragging = { x: event.clientX, y: event.clientY, panX: state.panX, panY: state.panY };
    canvas.setPointerCapture(event.pointerId);
    canvas.classList.add("dragging");
  });
  canvas.addEventListener("pointermove", (event) => {
    if (!state.dragging) return;
    state.panX = state.dragging.panX + (event.clientX - state.dragging.x);
    state.panY = state.dragging.panY + (event.clientY - state.dragging.y);
    applyZoom();
  });
  const endDrag = (event) => {
    if (!state.dragging) return;
    state.dragging = null;
    canvas.classList.remove("dragging");
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
  };
  canvas.addEventListener("pointerup", endDrag);
  canvas.addEventListener("pointercancel", endDrag);

  canvas.addEventListener("dblclick", (event) => {
    if (state.settings && state.settings.double_click_zoom === false) return;
    event.preventDefault();
    toggleSize();
  });

  window.addEventListener("resize", () => {
    if (el("viewer").hidden) return;
    if (state.mode === "fit") fitToWindow();
    else applyZoom();
  });

  document.addEventListener("keydown", onKeyDown);
}

function onKeyDown(event) {
  const tag = (event.target.tagName || "").toLowerCase();
  if (tag === "input" || tag === "textarea" || event.target.isContentEditable) return;
  if (!el("slideshow").hidden) {
    handleSlideshowKey(event);
    return;
  }
  if (el("viewer").hidden) return;
  const key = event.key;
  const withCtrl = event.ctrlKey || event.metaKey;

  if (withCtrl) {
    if (key === "0") { event.preventDefault(); fitToWindow(); }
    else if (key === "1") { event.preventDefault(); actualSize(); }
    else if (key === ".") { event.preventDefault(); rotate(90); }
    else if (key === ",") { event.preventDefault(); rotate(-90); }
    else if (key.toLowerCase() === "r") { event.preventDefault(); rotate(event.shiftKey ? -90 : 90); }
    else if (key.toLowerCase() === "l") { event.preventDefault(); rotate(-90); }
    return;
  }

  if (key === "ArrowLeft" || key === "PageUp") { event.preventDefault(); navigate(-1); }
  else if (key === "ArrowRight" || key === "PageDown") { event.preventDefault(); navigate(1); }
  else if (key === "Home") { event.preventDefault(); loadPhoto(0); }
  else if (key === "End") { event.preventDefault(); loadPhoto(state.images.length - 1); }
  else if (key === "+" || key === "=") { event.preventDefault(); stepZoom(1); }
  else if (key === "-" || key === "_") { event.preventDefault(); stepZoom(-1); }
  else if (key === "Delete" || key === "Backspace") { event.preventDefault(); askDelete(); }
  else if (key === "F11") { event.preventDefault(); startSlideshow(); }
  else if (key === "Escape") {
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    else backToLibrary();
  }
}

async function boot() {
  bindEvents();
  try {
    const startup = await api("/api/startup");
    state.settings = startup.settings;
    state.recent = startup.recent;
    renderRecent();
    if (state.recent.length && state.recent[0].exists) await openFolder(state.recent[0].path);
  } catch (error) {
    toast(error.message);
  }
}

boot();
