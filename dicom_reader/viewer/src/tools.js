import {
  addTool,
  ToolGroupManager,
  Enums,
  ZoomTool,
  PanTool,
  WindowLevelTool,
  StackScrollTool,
  LengthTool,
  AngleTool,
} from '@cornerstonejs/tools';

const TOOL_GROUP_ID = 'dicom-stack-tools';

export function registerStackTools(renderingEngineId, viewportId) {
  const existing = ToolGroupManager.getToolGroup(TOOL_GROUP_ID);
  if (existing) {
    ToolGroupManager.destroyToolGroup(TOOL_GROUP_ID);
  }

  const toolSet = [
    ZoomTool,
    PanTool,
    WindowLevelTool,
    StackScrollTool,
    LengthTool,
    AngleTool,
  ];

  for (const Tool of toolSet) {
    addTool(Tool);
  }

  const toolGroup = ToolGroupManager.createToolGroup(TOOL_GROUP_ID);
  toolGroup.addViewport(viewportId, renderingEngineId);

  toolGroup.addTool(ZoomTool.toolName);
  toolGroup.addTool(PanTool.toolName);
  toolGroup.addTool(WindowLevelTool.toolName);
  toolGroup.addTool(StackScrollTool.toolName);
  toolGroup.addTool(LengthTool.toolName);
  toolGroup.addTool(AngleTool.toolName);

  toolGroup.setToolActive(WindowLevelTool.toolName, {
    bindings: [{ mouseButton: Enums.MouseBindings.Primary }],
  });
  toolGroup.setToolActive(StackScrollTool.toolName, {
    bindings: [{ mouseButton: Enums.MouseBindings.Wheel }],
  });

  return {
    toolGroup,
    toolNames: {
      zoom: ZoomTool.toolName,
      pan: PanTool.toolName,
      windowLevel: WindowLevelTool.toolName,
      stackScroll: StackScrollTool.toolName,
      length: LengthTool.toolName,
      angle: AngleTool.toolName,
      stackScrollWheel: StackScrollTool.toolName,
      primaryBinding: Enums.MouseBindings.Primary,
    },
  };
}

export function activatePrimaryTool(toolGroup, toolNames, toolId) {
  if (!toolGroup || !toolNames || !toolNames[toolId]) {
    return;
  }

  const primaryTools = [
    toolNames.zoom,
    toolNames.pan,
    toolNames.windowLevel,
    toolNames.stackScroll,
    toolNames.length,
    toolNames.angle,
  ].filter(Boolean);

  for (const name of primaryTools) {
    try {
      toolGroup.setToolPassive(name);
    } catch (_) {
      // Best effort: some tools may not be active yet.
    }
  }

  toolGroup.setToolActive(toolNames[toolId], {
    bindings: [{ mouseButton: toolNames.primaryBinding }],
  });
  toolGroup.setToolActive(toolNames.stackScrollWheel, {
    bindings: [{ mouseButton: Enums.MouseBindings.Wheel }],
  });
}
