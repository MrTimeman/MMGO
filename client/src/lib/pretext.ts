import { layout, prepareWithSegments, walkLineRanges } from "@chenglou/pretext";

const FONT = '16px "PT Serif"';
const LINE_HEIGHT = 24;
const HORIZONTAL_PADDING = 28;
const VERTICAL_PADDING = 24;

export interface BubbleMetrics {
  width: number;
  height: number;
  lineCount: number;
}

export function measureBubble(text: string, containerWidth: number): BubbleMetrics {
  const safeWidth = Math.max(180, Math.floor(containerWidth));
  const maxTextWidth = Math.max(96, safeWidth - HORIZONTAL_PADDING);
  const prepared = prepareWithSegments(text, FONT);

  let widestLine = 0;

  const lineCount = walkLineRanges(prepared, maxTextWidth, (line) => {
    widestLine = Math.max(widestLine, line.width);
  });

  const bubbleTextWidth = Math.max(120, Math.ceil(widestLine));
  const bubbleWidth = Math.min(safeWidth, bubbleTextWidth + HORIZONTAL_PADDING);
  const laidOut = layout(prepared, bubbleWidth - HORIZONTAL_PADDING, LINE_HEIGHT);

  return {
    width: bubbleWidth,
    height: laidOut.height + VERTICAL_PADDING,
    lineCount
  };
}

export function bubbleTypography() {
  return {
    font: FONT,
    lineHeight: LINE_HEIGHT
  };
}
