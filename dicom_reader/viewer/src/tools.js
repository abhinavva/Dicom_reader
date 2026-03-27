/**
 * tools.js — Cornerstone3D tool registration and activation.
 *
 * Registers all supported tools for a Stack viewport and provides
 * helpers to switch the active primary-button tool.
 */

import {
  addTool,
  ToolGroupManager,
  annotation,
  Enums,
  // Navigation
  ZoomTool,
  PanTool,
  WindowLevelTool,
  StackScrollTool,
  MagnifyTool,
  PlanarRotateTool,
  // Measurement
  LengthTool,
  AngleTool,
  CobbAngleTool,
  BidirectionalTool,
  ProbeTool,
  // ROI
  EllipticalROITool,
  RectangleROITool,
  CircleROITool,
  PlanarFreehandROITool,
  // Annotation
  ArrowAnnotateTool,
  EraserTool,
} from '@cornerstonejs/tools';

const TOOL_GROUP_ID = 'dicom-stack-tools';

/**
 * All tool classes we register, in the order they appear in toolNames.
 */
const ALL_TOOLS = [
  // Navigation
  ZoomTool,
  PanTool,
  WindowLevelTool,
  StackScrollTool,
  MagnifyTool,
  PlanarRotateTool,
  // Measurement
  LengthTool,
  AngleTool,
  CobbAngleTool,
  BidirectionalTool,
  ProbeTool,
  // ROI
  EllipticalROITool,
  RectangleROITool,
  CircleROITool,
  PlanarFreehandROITool,
  // Annotation
  ArrowAnnotateTool,
  EraserTool,
];

export function registerStackTools(renderingEngineId, viewportId) {
  const existing = ToolGroupManager.getToolGroup(TOOL_GROUP_ID);
  if (existing) {
    ToolGroupManager.destroyToolGroup(TOOL_GROUP_ID);
  }

  for (const Tool of ALL_TOOLS) {
    try { addTool(Tool); } catch (_) { /* already registered */ }
  }

  const toolGroup = ToolGroupManager.createToolGroup(TOOL_GROUP_ID);

  // Support a single viewport ID or an array of IDs.
  const viewportIds = Array.isArray(viewportId) ? viewportId : [viewportId];
  for (const vpId of viewportIds) {
    toolGroup.addViewport(vpId, renderingEngineId);
  }

  for (const Tool of ALL_TOOLS) {
    toolGroup.addTool(Tool.toolName);
  }

  // Default active tools.
  toolGroup.setToolActive(WindowLevelTool.toolName, {
    bindings: [{ mouseButton: Enums.MouseBindings.Primary }],
  });
  toolGroup.setToolActive(StackScrollTool.toolName, {
    bindings: [{ mouseButton: Enums.MouseBindings.Wheel }],
  });

  return {
    toolGroup,
    toolNames: {
      // Navigation
      windowLevel: WindowLevelTool.toolName,
      zoom: ZoomTool.toolName,
      pan: PanTool.toolName,
      stackScroll: StackScrollTool.toolName,
      magnify: MagnifyTool.toolName,
      planarRotate: PlanarRotateTool.toolName,
      // Measurement
      length: LengthTool.toolName,
      angle: AngleTool.toolName,
      cobbAngle: CobbAngleTool.toolName,
      bidirectional: BidirectionalTool.toolName,
      probe: ProbeTool.toolName,
      // ROI
      ellipticalRoi: EllipticalROITool.toolName,
      rectangleRoi: RectangleROITool.toolName,
      circleRoi: CircleROITool.toolName,
      freehandRoi: PlanarFreehandROITool.toolName,
      // Annotation
      arrowAnnotate: ArrowAnnotateTool.toolName,
      eraser: EraserTool.toolName,
      // Scroll binding (always active on wheel)
      stackScrollWheel: StackScrollTool.toolName,
      primaryBinding: Enums.MouseBindings.Primary,
    },
  };
}

export function activatePrimaryTool(toolGroup, toolNames, toolId) {
  if (!toolGroup || !toolNames || !toolNames[toolId]) {
    return;
  }

  // Collect every registered tool name except internal helpers.
  const allNames = Object.entries(toolNames)
    .filter(([key]) => key !== 'stackScrollWheel' && key !== 'primaryBinding')
    .map(([, name]) => name)
    .filter(Boolean);

  // Deactivate all tools first.
  const unique = [...new Set(allNames)];
  for (const name of unique) {
    try { toolGroup.setToolPassive(name); } catch (_) { /* ok */ }
  }

  // Activate the requested tool on primary mouse button.
  toolGroup.setToolActive(toolNames[toolId], {
    bindings: [{ mouseButton: toolNames.primaryBinding }],
  });

  // Keep scroll on wheel always.
  toolGroup.setToolActive(toolNames.stackScrollWheel, {
    bindings: [{ mouseButton: Enums.MouseBindings.Wheel }],
  });
}

/**
 * Remove all annotations from the viewport.
 */
export function clearAnnotations() {
  try {
    annotation.state.removeAllAnnotations();
  } catch (_) {
    // Best effort.
  }
}
