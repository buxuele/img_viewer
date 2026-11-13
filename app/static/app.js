const MIN_ZOOM = 10;
const MAX_ZOOM = 800;
const ZOOM_STEPS = [10, 15, 25, 33, 50, 66, 75, 100, 125, 150, 200, 250, 300, 400, 500, 600, 800];
const RAW_PREVIEW_ONLY = new Set(["heic", "heif", "tif", "tiff"]);
const IMAGE_ACTIONS = new Set([
  "copy", "copy-path", "reveal", "save-as", "wallpaper",
  "rotate-left", "rotate-right", "delete", "properties",
]);

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
  slideOrder: [],
  slidePosition: 0,
  slidePaused: false,
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

function imageUrl(image, previewSize) {
  const extension = image.name.split(".").pop().toLowerCase();
  if (previewSize || RAW_PREVIEW_ONLY.has(extension)) {
    return `/api/preview?path=${encodeURIComponent(image.path)}&size=${previewSize || 2560}`;
  }
  return `/api/image?path=${encodeURIComponent(image.path)}`;
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
    if (state.settings && state.settings.fit_on_open === false) actualSize();
    else fitToWindow();
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
  updateMenuAvailability();
  loadPhoto(index);
}

function backToLibrary() {
  stopSlideshow();
  state.loadToken += 1;
  el("viewer").hidden = true;
  el("library").hidden = false;
  el("window-title").textContent = "照片查看器";
  document.title = "照片查看器";
  closeMenus();
  updateMenuAvailability();
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
  closeMenus();
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

/* 菜单与动作 */

function updateMenuAvailability() {
  const hasImage = !el("viewer").hidden && state.images.length > 0;
  for (const button of document.querySelectorAll("[data-action]")) {
    if (IMAGE_ACTIONS.has(button.dataset.action)) button.disabled = !hasImage;
  }
}

function openFileMenu() {
  el("menubar").hidden = false;
  el("file-menu").hidden = false;
  el("file-menu-button").setAttribute("aria-expanded", "true");
  updateMenuAvailability();
}

function closeMenus() {
  el("file-menu").hidden = true;
  el("file-menu-button").setAttribute("aria-expanded", "false");
  el("context-menu").hidden = true;
  if (!state.settings || !state.settings.always_show_menu) el("menubar").hidden = true;
}

function toggleFileMenu() {
  if (el("file-menu").hidden) openFileMenu();
  else closeMenus();
}

function contextMenuItems() {
  return [
    ["open-folder", "打开文件夹…"],
    ["separator"],
    ["copy", "复制"],
    ["copy-path", "复制文件路径"],
    ["reveal", "在访达中显示"],
    ["save-as", "另存为…"],
    ["separator"],
    ["wallpaper", "设为桌面背景"],
    ["rotate-left", "逆时针旋转"],
    ["rotate-right", "顺时针旋转"],
    ["delete", "删除"],
    ["separator"],
    ["properties", "属性"],
    ["options", "选项"],
  ];
}

function showContextMenu(x, y) {
  const menu = el("context-menu");
  menu.innerHTML = "";
  const hasImage = !el("viewer").hidden && state.images.length > 0;
  for (const item of contextMenuItems()) {
    if (item[0] === "separator") {
      const separator = document.createElement("div");
      separator.className = "menu-sep";
      menu.append(separator);
      continue;
    }
    const [action, label] = item;
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.action = action;
    button.textContent = label;
    button.disabled = IMAGE_ACTIONS.has(action) && !hasImage;
    menu.append(button);
  }
  menu.hidden = false;
  const rect = menu.getBoundingClientRect();
  menu.style.left = `${Math.max(8, Math.min(x, window.innerWidth - rect.width - 8))}px`;
  menu.style.top = `${Math.max(8, Math.min(y, window.innerHeight - rect.height - 8))}px`;
}

async function copyImage(image) {
  try {
    const response = await fetch(imageUrl(image));
    if (!response.ok) throw new Error("读取图片失败");
    let blob = await response.blob();
    if (blob.type !== "image/png") blob = await toPngBlob(blob);
    await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
    toast("图片已复制到剪贴板");
  } catch (error) {
    toast(`复制失败：${error.message}`);
  }
}

async function toPngBlob(blob) {
  const bitmap = await createImageBitmap(blob);
  const canvas = document.createElement("canvas");
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  canvas.getContext("2d").drawImage(bitmap, 0, 0);
  return new Promise((resolve, reject) => {
    canvas.toBlob((png) => (png ? resolve(png) : reject(new Error("图片转换失败"))), "image/png");
  });
}

function saveAs(image) {
  const link = document.createElement("a");
  link.href = imageUrl(image);
  link.download = image.name;
  document.body.append(link);
  link.click();
  link.remove();
  toast("已开始下载");
}

async function showProperties(image) {
  try {
    const info = await api(`/api/info?path=${encodeURIComponent(image.path)}`);
    const rows = [
      ["文件名", info.name],
      ["位置", info.folder],
      ["格式", info.format],
      ["尺寸", info.width ? `${info.width} × ${info.height} 像素` : "无法读取"],
      ["大小", formatSize(info.size)],
      ["修改时间", new Date(info.mtime * 1000).toLocaleString("zh-CN")],
      ["旋转", `${info.rotation} 度`],
    ];
    const list = el("properties-list");
    list.innerHTML = "";
    for (const [term, value] of rows) {
      const dt = document.createElement("dt");
      dt.textContent = term;
      const dd = document.createElement("dd");
      dd.textContent = value;
      list.append(dt, dd);
    }
    el("properties-dialog").showModal();
  } catch (error) {
    toast(error.message);
  }
}

function applySettings() {
  if (!state.settings) return;
  el("stage").dataset.background = state.settings.background || "light";
  el("menubar").hidden = !state.settings.always_show_menu;
  el("file-menu").hidden = true;
  el("file-menu-button").setAttribute("aria-expanded", "false");
}

function openOptions() {
  const settings = state.settings;
  el("opt-fit").checked = settings.fit_on_open;
  el("opt-menu").checked = settings.always_show_menu;
  el("opt-recent").checked = settings.remember_recent;
  el("opt-wheel").checked = settings.wheel_zoom;
  el("opt-double").checked = settings.double_click_zoom;
  el("opt-background").value = settings.background;
  el("opt-interval").value = String(settings.slideshow_interval);
  el("opt-loop").checked = settings.slideshow_loop;
  el("opt-shuffle").checked = settings.slideshow_shuffle;
  el("opt-theme").value = settings.slideshow_theme;
  switchOptionsTab("general");
  el("options-dialog").showModal();
  closeMenus();
}

function switchOptionsTab(name) {
  const general = name === "general";
  el("tab-general").classList.toggle("active", general);
  el("tab-slideshow").classList.toggle("active", !general);
  el("tab-general").setAttribute("aria-selected", String(general));
  el("tab-slideshow").setAttribute("aria-selected", String(!general));
  el("panel-general").hidden = !general;
  el("panel-slideshow").hidden = general;
}

async function saveOptions() {
  const payload = {
    fit_on_open: el("opt-fit").checked,
    always_show_menu: el("opt-menu").checked,
    remember_recent: el("opt-recent").checked,
    wheel_zoom: el("opt-wheel").checked,
    double_click_zoom: el("opt-double").checked,
    background: el("opt-background").value,
    slideshow_interval: Number(el("opt-interval").value),
    slideshow_loop: el("opt-loop").checked,
    slideshow_shuffle: el("opt-shuffle").checked,
    slideshow_theme: el("opt-theme").value,
  };
  try {
    state.settings = await api("/api/settings", {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    applySettings();
    el("options-dialog").close();
    toast("选项已保存");
  } catch (error) {
    toast(error.message);
  }
}

async function runAction(action) {
  const image = currentImage();
  if (IMAGE_ACTIONS.has(action) && (!image || el("viewer").hidden)) {
    toast("先打开一张图片");
    return;
  }
  closeMenus();
  try {
    if (action === "open-folder") await pickFolder();
    else if (action === "copy") await copyImage(image);
    else if (action === "copy-path") {
      await navigator.clipboard.writeText(image.path);
      toast("路径已复制");
    } else if (action === "reveal") {
      await api("/api/reveal", { method: "POST", body: JSON.stringify({ path: image.path }) });
    } else if (action === "save-as") saveAs(image);
    else if (action === "wallpaper") {
      await api("/api/wallpaper", { method: "POST", body: JSON.stringify({ path: image.path }) });
      toast("已设为桌面背景");
    } else if (action === "rotate-left") await rotate(-90);
    else if (action === "rotate-right") await rotate(90);
    else if (action === "delete") askDelete();
    else if (action === "properties") await showProperties(image);
    else if (action === "options") openOptions();
    else if (action === "close") backToLibrary();
  } catch (error) {
    toast(error.message);
  }
}

/* 幻灯片 */

function slideshowOrder(start) {
  const indexes = state.images.map((_, index) => index);
  if (state.settings.slideshow_shuffle) {
    for (let i = indexes.length - 1; i > 0; i -= 1) {
      const j = Math.floor(Math.random() * (i + 1));
      [indexes[i], indexes[j]] = [indexes[j], indexes[i]];
    }
  }
  const position = indexes.indexOf(start);
  if (position > 0) {
    indexes.splice(position, 1);
    indexes.unshift(start);
  }
  return indexes;
}

function showSlide() {
  const index = state.slideOrder[state.slidePosition];
  if (index === undefined) return;
  state.index = index;
  const image = state.images[index];
  el("slideshow-photo").src = imageUrl(image, 2560);
  el("slideshow-hint").textContent =
    `第 ${state.slidePosition + 1} 张 / 共 ${state.slideOrder.length} 张 · 空格暂停 · Esc 退出`;
  updateCaption();
}

function scheduleSlide() {
  clearTimeout(state.slideTimer);
  if (state.slidePaused) return;
  const seconds = (state.settings && state.settings.slideshow_interval) || 5;
  state.slideTimer = setTimeout(() => advanceSlide(1), seconds * 1000);
}

function advanceSlide(step) {
  const next = state.slidePosition + step;
  if (next >= state.slideOrder.length) {
    if (state.settings.slideshow_loop === false) {
      stopSlideshow();
      return;
    }
    state.slidePosition = 0;
  } else if (next < 0) {
    if (state.settings.slideshow_loop === false) return;
    state.slidePosition = state.slideOrder.length - 1;
  } else {
    state.slidePosition = next;
  }
  showSlide();
  scheduleSlide();
}

function togglePause() {
  state.slidePaused = !state.slidePaused;
  el("slideshow-pause").textContent = state.slidePaused ? "继续" : "暂停";
  if (state.slidePaused) clearTimeout(state.slideTimer);
  else scheduleSlide();
}

function startSlideshow() {
  if (!state.images.length) return;
  el("slideshow").className = `slideshow theme-${(state.settings && state.settings.slideshow_theme) || "black"}`;
  el("slideshow").hidden = false;
  el("slideshow-pause").textContent = "暂停";
  state.slideOrder = slideshowOrder(state.index);
  state.slidePosition = 0;
  state.slidePaused = false;
  showSlide();
  document.documentElement.requestFullscreen?.().catch(() => {});
  scheduleSlide();
}

function stopSlideshow() {
  clearTimeout(state.slideTimer);
  state.slideTimer = null;
  if (el("slideshow").hidden) return;
  el("slideshow").hidden = true;
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  if (!el("viewer").hidden) loadPhoto(state.index);
}

function handleSlideshowKey(event) {
  const key = event.key;
  if (key === "Escape") {
    event.preventDefault();
    stopSlideshow();
  } else if (key === " ") {
    event.preventDefault();
    togglePause();
  } else if (key === "ArrowLeft" || key === "PageUp") {
    event.preventDefault();
    advanceSlide(-1);
  } else if (key === "ArrowRight" || key === "PageDown") {
    event.preventDefault();
    advanceSlide(1);
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
  el("slideshow-button").addEventListener("click", startSlideshow);
  el("confirm-cancel").addEventListener("click", () => el("confirm-dialog").close());
  el("confirm-delete").addEventListener("click", confirmDelete);
  el("zoom-slider").addEventListener("input", (event) => {
    const percent = Number(event.target.value);
    state.mode = "manual";
    state.zoom = MIN_ZOOM * Math.pow(MAX_ZOOM / MIN_ZOOM, percent / 100);
    applyZoom();
  });

  el("file-menu-button").addEventListener("click", (event) => {
    event.stopPropagation();
    toggleFileMenu();
  });
  el("menubar").addEventListener("click", (event) => {
    const action = event.target.closest("[data-action]");
    if (action) {
      event.stopPropagation();
      runAction(action.dataset.action);
    }
  });
  el("context-menu").addEventListener("click", (event) => {
    const action = event.target.closest("[data-action]");
    if (action) {
      event.stopPropagation();
      runAction(action.dataset.action);
    }
  });
  document.addEventListener("click", (event) => {
    if (!event.target.closest(".menu-popup") && !event.target.closest(".menu-trigger")) closeMenus();
  });
  el("stage").addEventListener("contextmenu", (event) => {
    event.preventDefault();
    closeMenus();
    showContextMenu(event.clientX, event.clientY);
  });

  el("tab-general").addEventListener("click", () => switchOptionsTab("general"));
  el("tab-slideshow").addEventListener("click", () => switchOptionsTab("slideshow"));
  el("options-cancel").addEventListener("click", () => el("options-dialog").close());
  el("options-save").addEventListener("click", saveOptions);
  el("properties-close").addEventListener("click", () => el("properties-dialog").close());

  el("slideshow-pause").addEventListener("click", togglePause);
  el("slideshow-prev").addEventListener("click", () => advanceSlide(-1));
  el("slideshow-next").addEventListener("click", () => advanceSlide(1));
  el("slideshow-exit").addEventListener("click", stopSlideshow);

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
  if (document.querySelector("dialog[open]")) return;
  if (event.key === "Alt") {
    event.preventDefault();
    if (state.settings && state.settings.always_show_menu) return;
    const bar = el("menubar");
    bar.hidden = !bar.hidden;
    if (!bar.hidden) el("file-menu-button").focus();
    return;
  }
  if (event.key === "Escape" && (!el("file-menu").hidden || !el("context-menu").hidden)) {
    event.preventDefault();
    closeMenus();
    return;
  }
  if (event.key === "Escape" && !el("menubar").hidden && !state.settings.always_show_menu) {
    el("menubar").hidden = true;
    return;
  }
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
    applySettings();
    renderRecent();
    if (state.recent.length && state.recent[0].exists) await openFolder(state.recent[0].path);
  } catch (error) {
    toast(error.message);
  }
}

boot();
