const viewerElement = document.getElementById('viewport');
const statusPill = document.getElementById('status-pill');

const state = {
  imports: null,
  renderingEngine: null,
  viewport: null,
  toolGroup: null,
  toolNames: {},
  initialized: false,
  currentSeries: null,
  activeTool: 'windowLevel',
};

let reportTimer = null;
let loadProgressTimer = null;

function emitLoadProgress(seriesUid, loaded, total) {
  clearTimeout(loadProgressTimer);
  loadProgressTimer = setTimeout(() => {
    emit('imageProgress', {
      seriesInstanceUid: seriesUid,
      loaded: loaded,
      total: total,
    });
  }, 100);
}

function emit(type, payload) {
  if (window.flutter_inappwebview?.callHandler) {
    window.flutter_inappwebview.callHandler('viewerEvent', { type, payload });
  }
}

function setStatus(message) {
  statusPill.textContent = message;
  emit('status', message);
}

function scheduleReport(message) {
  clearTimeout(reportTimer);
  reportTimer = setTimeout(() => reportViewportState(message), 60);
}

// Try jsDelivr first (avoids ERR_CERT_VERIFIER_CHANGED common with esm.sh in WebView).
// Fallback to esm.sh with ?standalone for environments where jsDelivr fails.
const CDN_ORIGINS = [
  {
    core: 'https://cdn.jsdelivr.net/npm/@cornerstonejs/core@latest/+esm',
    tools: 'https://cdn.jsdelivr.net/npm/@cornerstonejs/tools@latest/+esm',
    dicom: 'https://cdn.jsdelivr.net/npm/@cornerstonejs/dicom-image-loader@latest/+esm',
  },
  {
    core: 'https://esm.sh/@cornerstonejs/core?standalone',
    tools: 'https://esm.sh/@cornerstonejs/tools?standalone',
    dicom: 'https://esm.sh/@cornerstonejs/dicom-image-loader?standalone',
  },
];

async function loadPackages() {
  if (state.imports) {
    return state.imports;
  }

  setStatus('Loading Cornerstone modules...');

  let lastError;
  for (const urls of CDN_ORIGINS) {
    try {
      const [coreModule, toolsModule, dicomImageLoaderModule] = await Promise.all([
        import(urls.core),
        import(urls.tools),
        import(urls.dicom),
      ]);

      const core = coreModule.default ?? coreModule;
      const tools = toolsModule.default ?? toolsModule;
      const dicomImageLoader = dicomImageLoaderModule.default ?? dicomImageLoaderModule;

      state.imports = { core, tools, dicomImageLoader };
      return state.imports;
    } catch (e) {
      lastError = e;
      continue;
    }
  }
  throw lastError ?? new Error('Failed to load Cornerstone from any CDN');
}

function registerTools(tools, renderingEngineId, viewportId) {
  const {
    addTool,
    ToolGroupManager,
    Enums,
    ZoomTool,
    PanTool,
    WindowLevelTool,
    StackScrollTool,
    StackScrollMouseWheelTool,
    LengthTool,
    AngleTool,
  } = tools;

  const toolGroupId = 'dicom-stack-tools';
  const existingGroup = ToolGroupManager.getToolGroup(toolGroupId);
  if (existingGroup) {
    ToolGroupManager.destroyToolGroup(toolGroupId);
  }

  const toolSet = [
    ZoomTool,
    PanTool,
    WindowLevelTool,
    StackScrollTool,
    StackScrollMouseWheelTool,
    LengthTool,
    AngleTool,
  ];

  toolSet.forEach((tool) => addTool(tool));

  const toolGroup = ToolGroupManager.createToolGroup(toolGroupId);
  toolGroup.addViewport(viewportId, renderingEngineId);

  toolGroup.addTool(ZoomTool.toolName);
  toolGroup.addTool(PanTool.toolName);
  toolGroup.addTool(WindowLevelTool.toolName);
  toolGroup.addTool(StackScrollTool.toolName);
  toolGroup.addTool(StackScrollMouseWheelTool.toolName);
  toolGroup.addTool(LengthTool.toolName);
  toolGroup.addTool(AngleTool.toolName);

  toolGroup.setToolActive(WindowLevelTool.toolName, {
    bindings: [{ mouseButton: Enums.MouseBindings.Primary }],
  });
  toolGroup.setToolActive(StackScrollMouseWheelTool.toolName);

  state.toolNames = {
    zoom: ZoomTool.toolName,
    pan: PanTool.toolName,
    windowLevel: WindowLevelTool.toolName,
    stackScroll: StackScrollTool.toolName,
    length: LengthTool.toolName,
    angle: AngleTool.toolName,
    stackScrollWheel: StackScrollMouseWheelTool.toolName,
    bindings: Enums.MouseBindings.Primary,
  };
  state.toolGroup = toolGroup;
}

function attachInteractionListeners() {
  ['wheel', 'mouseup', 'mouseleave', 'touchend', 'dblclick'].forEach((eventName) => {
    viewerElement.addEventListener(eventName, () => scheduleReport());
  });

  window.addEventListener('resize', () => {
    try {
      state.renderingEngine?.resize(true, false);
    } catch (_) {
      /* Cornerstone resize is best-effort */
    }
    scheduleReport();
  });
}

function activatePrimaryTool(toolName) {
  if (!state.toolGroup || !toolName) {
    return;
  }

  const primaryTools = [
    state.toolNames.zoom,
    state.toolNames.pan,
    state.toolNames.windowLevel,
    state.toolNames.stackScroll,
    state.toolNames.length,
    state.toolNames.angle,
  ].filter(Boolean);

  primaryTools.forEach((name) => {
    try {
      state.toolGroup.setToolPassive(name);
    } catch (_) {
      /* noop */
    }
  });

  state.toolGroup.setToolActive(toolName, {
    bindings: [{ mouseButton: state.toolNames.bindings }],
  });
  state.toolGroup.setToolActive(state.toolNames.stackScrollWheel);
}

function extractWindowLevel(properties) {
  const voiRange = properties?.voiRange;
  if (!voiRange) {
    return { windowWidth: null, windowCenter: null };
  }

  const upper = voiRange.upper ?? null;
  const lower = voiRange.lower ?? null;
  if (upper == null || lower == null) {
    return { windowWidth: null, windowCenter: null };
  }

  return {
    windowWidth: Math.abs(upper - lower),
    windowCenter: (upper + lower) / 2,
  };
}

function reportViewportState(statusMessage = null) {
  if (!state.viewport) {
    return;
  }

  const properties = state.viewport.getProperties?.() ?? {};
  const { windowWidth, windowCenter } = extractWindowLevel(properties);
  const zoom = typeof state.viewport.getZoom === 'function'
    ? state.viewport.getZoom()
    : 1;
  const currentImageIndex = typeof state.viewport.getCurrentImageIdIndex === 'function'
    ? state.viewport.getCurrentImageIdIndex()
    : 0;

  emit('viewport', {
    zoom: Number.isFinite(zoom) ? zoom : 1,
    windowWidth,
    windowCenter,
    currentImageIndex,
    totalImages: state.currentSeries?.imageIds?.length ?? 0,
    isReady: true,
    statusMessage,
  });
}

async function initializeViewer() {
  if (state.initialized) {
    emit('ready', true);
    return;
  }

  try {
    const { core, tools, dicomImageLoader } = await loadPackages();

    if (typeof core.init === 'function') {
      await core.init();
    }
    if (typeof tools.init === 'function') {
      tools.init();
    }
    if (typeof dicomImageLoader.init === 'function') {
      dicomImageLoader.init({
        maxWebWorkers: Math.max(1, Math.min(4, navigator.hardwareConcurrency || 1)),
      });
    }

    const renderingEngineId = 'dicom-rendering-engine';
    const viewportId = 'dicom-stack-viewport';

    state.renderingEngine = new core.RenderingEngine(renderingEngineId);
    state.renderingEngine.enableElement({
      viewportId,
      element: viewerElement,
      type: core.Enums.ViewportType.STACK,
      defaultOptions: {
        background: [0, 0, 0],
      },
    });

    state.viewport = state.renderingEngine.getViewport(viewportId);
    registerTools(tools, renderingEngineId, viewportId);
    attachInteractionListeners();

    state.initialized = true;
    setStatus('Cornerstone ready');
    reportViewportState('Viewer ready');
    emit('ready', true);
  } catch (error) {
    console.error(error);
    const message = error?.message || String(error);
    setStatus('Cornerstone failed to initialize');
    emit('error', message);
  }
}

async function loadSeries(payload) {
  try {
    await initializeViewer();
    if (!state.viewport) {
      return;
    }

    state.currentSeries = payload;
    const total = payload.imageIds.length;
    const seriesUid = payload.seriesInstanceUid || '';
    emit('imageProgress', { seriesInstanceUid: seriesUid, loaded: 0, total: total });
    setStatus(`Loading ${total} slices...`);

    await state.viewport.setStack(payload.imageIds, 0);
    state.viewport.render();
    await setTool(state.activeTool);

    emit('imageProgress', { seriesInstanceUid: seriesUid, loaded: total, total: total });
    setStatus('Series loaded');
    reportViewportState('Series loaded');
  } catch (error) {
    console.error(error);
    const message = error?.message || String(error);
    setStatus('Failed to load series');
    emit('error', message);
  }
}

async function setTool(toolId) {
  state.activeTool = toolId;
  viewerElement.classList.toggle('crosshair-mode', toolId === 'crosshair');

  if (!state.toolGroup) {
    return;
  }

  if (toolId === 'crosshair') {
    setStatus('Crosshair cursor enabled');
    scheduleReport('Crosshair cursor enabled');
    return;
  }

  activatePrimaryTool(state.toolNames[toolId]);
  setStatus(`Tool: ${toolId}`);
  scheduleReport(`Tool: ${toolId}`);
}

async function resetViewport() {
  if (!state.viewport) {
    return;
  }

  try {
    state.viewport.resetCamera();
    state.viewport.resetProperties?.();
    state.viewport.render();
    setStatus('Viewport reset');
    reportViewportState('Viewport reset');
  } catch (error) {
    console.error(error);
    const message = error?.message || String(error);
    setStatus('Reset failed');
    emit('error', message);
  }
}

window.cornerstoneViewer = {
  initializeViewer,
  loadSeries,
  setTool,
  resetViewport,
};

setStatus('Viewer shell ready');
